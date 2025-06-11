# environments/dev/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  cloud {
    organization = "your-org-name"
    workspaces {
      name = "cortex-emr-dev"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Cortex-EMR"
      ManagedBy   = "Terraform"
      Owner       = "Dev-Team"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "windows_2024" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["Windows_Server-2024-English-Full-Base-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local values
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
  
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Networking Module
module "networking" {
  source = "../../modules/networking"
  
  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
  
  # Subnet CIDRs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  db_subnet_cidrs      = var.db_subnet_cidrs
  
  # On-premises connectivity (optional for dev)
  on_premises_cidr    = var.on_premises_cidr
  vpn_customer_gateway_ip = var.vpn_customer_gateway_ip
  
  tags = local.common_tags
}

# Security Module
module "security" {
  source = "../../modules/security"
  
  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = var.vpc_cidr
  
  # On-premises access
  on_premises_cidr = var.on_premises_cidr
  
  tags = local.common_tags
}

# Database Module (Single AZ for cost savings in dev)
module "database" {
  source = "../../modules/database"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.database_subnet_ids
  
  # Security
  security_group_ids = [
    module.security.database_security_group_id
  ]
  
  # Database configuration (smaller for dev)
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  
  # Single AZ for dev environment
  multi_az = false
  
  # Shorter backup retention for dev
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  
  # Disable deletion protection for dev
  deletion_protection = false
  final_snapshot     = false
  
  # Credentials
  master_username = var.db_master_username
  master_password = var.db_master_password
  
  tags = local.common_tags
}

# Storage Module (Smaller capacity for dev)
module "storage" {
  source = "../../modules/storage"
  
  name_prefix = local.name_prefix
  
  # Networking
  subnet_ids = [module.networking.private_subnet_ids[0]]
  
  # Security
  security_group_ids = [
    module.security.file_server_security_group_id
  ]
  
  # Active Directory (optional for dev)
  active_directory_id = var.enable_active_directory ? aws_directory_service_directory.main[0].id : null
  
  # Storage configuration (smaller for dev)
  storage_capacity    = var.fsx_storage_capacity
  throughput_capacity = var.fsx_throughput_capacity
  deployment_type     = "SINGLE_AZ_2" # Single AZ for dev
  
  # Enable S3 integration for testing
  enable_s3_integration = true
  force_destroy_bucket  = true # Allow bucket deletion in dev
  
  tags = local.common_tags
}

# Compute Module (Smaller instances for dev)
module "compute" {
  source = "../../modules/compute"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  
  # Security
  application_security_group_id = module.security.application_security_group_id
  integration_security_group_id = module.security.integration_security_group_id
  bastion_security_group_id     = module.security.bastion_security_group_id
  alb_security_group_id         = module.security.alb_security_group_id
  instance_profile_name         = module.security.ec2_instance_profile_name
  kms_key_id                   = module.security.kms_key_id
  
  # AMI and instance configuration
  windows_ami_id = data.aws_ami.windows_2024.id
  
  # Application servers (smaller for dev)
  app_instance_type     = var.app_instance_type
  app_min_size         = var.app_min_size
  app_max_size         = var.app_max_size
  app_desired_capacity = var.app_desired_capacity
  
  # Integration server (smaller for dev)
  integration_instance_type = var.integration_instance_type
  
  # Active Directory (optional for dev)
  domain_name           = var.enable_active_directory ? var.ad_domain_name : ""
  domain_netbios_name   = var.enable_active_directory ? var.ad_domain_netbios : ""
  domain_admin_user     = var.enable_active_directory ? var.ad_service_account : ""
  domain_admin_password = var.enable_active_directory ? var.ad_admin_password : ""
  
  # File system
  fsx_dns_name = var.enable_active_directory ? module.storage.fsx_dns_name : ""
  
  # Database connection
  db_endpoint = module.database.db_endpoint
  db_name     = module.database.db_name
  
  # SSL certificate (optional for dev)
  ssl_certificate_arn = var.enable_ssl ? aws_acm_certificate.main[0].arn : ""
  
  tags = local.common_tags
}

# Monitoring Module (Basic monitoring for dev)
module "monitoring" {
  source = "../../modules/monitoring"
  
  name_prefix = local.name_prefix
  
  # Resources to monitor
  auto_scaling_group_names = module.compute.auto_scaling_group_names
  load_balancer_arn_suffix = module.compute.load_balancer_arn_suffix
  db_instance_identifier   = module.database.db_instance_identifier
  
  # Notification
  notification_email = var.notification_email
  
  tags = local.common_tags
}

# Optional Active Directory for dev testing
resource "aws_directory_service_directory" "main" {
  count = var.enable_active_directory ? 1 : 0
  
  name     = var.ad_domain_name
  password = var.ad_admin_password
  type     = "SimpleAD"
  size     = "Small"
  
  vpc_settings {
    vpc_id     = module.networking.vpc_id
    subnet_ids = module.networking.private_subnet_ids
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-simple-ad"
  })
}

# Optional SSL Certificate for dev testing
resource "aws_acm_certificate" "main" {
  count = var.enable_ssl ? 1 : 0
  
  domain_name       = "${var.emr_subdomain}.${var.domain_name}"
  validation_method = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssl-cert"
  })
}

# environments/dev/variables.tf

# Basic Configuration - UAE Region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "me-central-1"  # Middle East (UAE)
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cortex-emr"
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16" # Different from prod
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.20.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.1.30.0/24", "10.1.40.0/24"]
}

variable "on_premises_cidr" {
  description = "CIDR block for on-premises network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "vpn_customer_gateway_ip" {
  description = "Public IP address of the on-premises VPN gateway"
  type        = string
  default     = "203.0.113.12" # Example IP
}

# Feature Toggles for Dev Environment
variable "enable_active_directory" {
  description = "Enable Active Directory integration"
  type        = bool
  default     = false # Disabled by default for dev
}

variable "enable_ssl" {
  description = "Enable SSL certificate"
  type        = bool
  default     = false # Disabled by default for dev
}

# Active Directory Configuration (when enabled)
variable "ad_domain_name" {
  description = "Active Directory domain name"
  type        = string
  default     = "dev.corp.example.com"
}

variable "ad_domain_netbios" {
  description = "NetBIOS name for AD domain"
  type        = string
  default     = "DEVCORP"
}

variable "ad_service_account" {
  description = "Service account for AD connector"
  type        = string
  default     = "svc-aws-connector"
}

variable "ad_admin_password" {
  description = "Password for AD service account"
  type        = string
  sensitive   = true
  default     = "DevPassword123!"
}

# Database Configuration (smaller for dev)
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium" # Smaller for dev
}

variable "db_allocated_storage" {
  description = "Initial storage allocation for RDS"
  type        = number
  default     = 100 # Smaller for dev
}

variable "db_max_allocated_storage" {
  description = "Maximum storage allocation for RDS"
  type        = number
  default     = 200 # Smaller for dev
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7 # Shorter for dev
}

variable "db_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "db_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "admin"
}

variable "db_master_password" {
  description = "Master password for RDS"
  type        = string
  sensitive   = true
  default     = "DevDbPassword123!"
}

# Application Server Configuration (smaller for dev)
variable "app_instance_type" {
  description = "Instance type for application servers"
  type        = string
  default     = "t3.large" # Smaller for dev
}

variable "app_min_size" {
  description = "Minimum number of application servers"
  type        = number
  default     = 1
}

variable "app_max_size" {
  description = "Maximum number of application servers"
  type        = number
  default     = 2 # Smaller for dev
}

variable "app_desired_capacity" {
  description = "Desired number of application servers"
  type        = number
  default     = 1 # Smaller for dev
}

# Integration Server Configuration (smaller for dev)
variable "integration_instance_type" {
  description = "Instance type for integration server"
  type        = string
  default     = "t3.medium" # Smaller for dev
}

# File System Configuration (smaller for dev)
variable "fsx_storage_capacity" {
  description = "Storage capacity for FSx file system in GB"
  type        = number
  default     = 512 # Much smaller for dev (512 GB)
}

variable "fsx_throughput_capacity" {
  description = "Throughput capacity for FSx file system in MB/s"
  type        = number
  default     = 8 # Smaller for dev
}

# DNS Configuration
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "dev.example.com"
}

variable "emr_subdomain" {
  description = "Subdomain for EMR application"
  type        = string
  default     = "emr"
}

# Monitoring Configuration
variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = "dev-team@example.com"
}

# environments/dev/terraform.tfvars

# Basic Configuration - UAE Region
aws_region   = "me-central-1"  # Middle East (UAE)
environment  = "dev"
project_name = "cortex-emr"

# UAE Availability Zones
availability_zones = ["me-central-1a", "me-central-1b"]

# Feature toggles - customize based on testing needs
enable_active_directory = false  # Set to true to test AD integration
enable_ssl             = false  # Set to true to test SSL

# Networking Configuration (different from prod)
vpc_cidr                = "10.1.0.0/16"
public_subnet_cidrs     = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs    = ["10.1.10.0/24", "10.1.20.0/24"]
db_subnet_cidrs         = ["10.1.30.0/24", "10.1.40.0/24"]

# Database Configuration (cost-optimized for dev)
db_instance_class           = "db.t3.medium"
db_allocated_storage        = 100
db_max_allocated_storage    = 200
db_backup_retention_period  = 7

# Application Configuration (smaller instances for dev)
app_instance_type    = "t3.large"
app_min_size         = 1
app_max_size         = 2
app_desired_capacity = 1

# Integration Server (smaller for dev)
integration_instance_type = "t3.medium"

# File System (much smaller for dev)
fsx_storage_capacity    = 512  # 512 GB
fsx_throughput_capacity = 8    # 8 MB/s

# DNS Configuration - UAE Domain
domain_name   = "dev.yourcompany.ae"  # UAE domain for dev
emr_subdomain = "emr"

# Monitoring - UAE Team
notification_email = "dev-team@yourcompany.ae"