# environments/template/main.tf

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
  
  cloud {
    organization = var.terraform_cloud_organization
    workspaces {
      name = var.terraform_cloud_workspace
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

# Configure Azure AD Provider for Entra ID integration
provider "azuread" {
  tenant_id = var.entra_tenant_id
}

# Local values for consistent naming and tagging
locals {
  name_prefix = "${var.customer_code}-${var.environment}"
  
  common_tags = {
    Customer          = var.customer_name
    Environment       = var.environment
    Project          = "Cortex-EMR"
    ManagedBy        = "Terraform"
    DeployedBy       = var.deployed_by
    CostCenter       = var.cost_center
    Compliance       = "ADHICS"
    DataResidency    = "UAE"
    AccessType       = "Internal"
    CreatedDate      = formatdate("YYYY-MM-DD", timestamp())
  }
  
  # Automatically calculate subnet CIDRs based on customer VPC CIDR
  vpc_cidr_parts = split("/", var.vpc_cidr)
  vpc_prefix     = tonumber(local.vpc_cidr_parts[1])
  
  # Calculate subnets (assumes /16 VPC, creates /24 subnets)
  private_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 10), # 10.x.10.0/24
    cidrsubnet(var.vpc_cidr, 8, 20)  # 10.x.20.0/24
  ]
  
  database_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 30), # 10.x.30.0/24
    cidrsubnet(var.vpc_cidr, 8, 40)  # 10.x.40.0/24
  ]
  
  management_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 50), # 10.x.50.0/24
    cidrsubnet(var.vpc_cidr, 8, 60)  # 10.x.60.0/24
  ]
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

# Get current AWS account info
data "aws_caller_identity" "current" {}

# Networking Module
module "networking" {
  source = "../../modules/networking"
  
  # Naming and identification
  name_prefix    = local.name_prefix
  customer_code  = var.customer_code
  
  # Network configuration
  vpc_cidr                = var.vpc_cidr
  availability_zones      = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnet_cidrs    = local.private_subnet_cidrs
  database_subnet_cidrs   = local.database_subnet_cidrs
  management_subnet_cidrs = local.management_subnet_cidrs
  
  # FortiGate VPN configuration
  fortigate_vpn_config = {
    customer_gateway_ip   = var.fortigate_public_ip
    customer_gateway_asn  = var.fortigate_bgp_asn
    tunnel_inside_cidrs   = var.vpn_tunnel_inside_cidrs
    shared_secret        = var.vpn_shared_secret
  }
  
  # On-premises network access
  on_premises_cidrs = var.on_premises_cidrs
  
  # DNS configuration for internal access
  internal_domain_name = "${var.customer_code}.${var.internal_domain_suffix}"
  
  tags = local.common_tags
}

# Security Module
module "security" {
  source = "../../modules/security"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Network security
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = var.vpc_cidr
  
  # Access control
  on_premises_cidrs    = var.on_premises_cidrs
  management_ips       = var.management_ip_ranges
  
  # Compliance and monitoring
  enable_adhics_compliance = var.enable_adhics_compliance
  enable_enhanced_logging  = var.enable_enhanced_logging
  log_retention_days      = var.log_retention_days
  
  tags = local.common_tags
}

# Entra AD Integration Module
module "entra_ad_integration" {
  source = "../../modules/entra-ad-integration"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Entra ID configuration
  entra_tenant_id     = var.entra_tenant_id
  entra_client_id     = var.entra_client_id
  entra_client_secret = var.entra_client_secret
  
  # Application configuration
  application_redirect_uri = "https://${var.customer_code}-emr.${var.internal_domain_suffix}/auth/callback"
  allowed_user_groups     = var.entra_allowed_groups
  
  # Security groups for RBAC
  security_group_mappings = var.entra_security_group_mappings
  
  tags = local.common_tags
}

# Database Module
module "database" {
  source = "../../modules/database"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Networking
  vpc_id               = module.networking.vpc_id
  subnet_ids           = module.networking.database_subnet_ids
  
  # Security
  security_group_ids = [module.security.database_security_group_id]
  kms_key_id        = module.security.kms_key_id
  
  # Database configuration
  instance_class           = var.db_instance_class
  allocated_storage        = var.db_allocated_storage
  max_allocated_storage    = var.db_max_allocated_storage
  backup_retention_period  = var.db_backup_retention_period
  
  # Multi-AZ for production, single-AZ for dev/test
  multi_az = var.environment == "prod" ? true : false
  
  # Maintenance windows (UAE timezone)
  backup_window      = var.db_backup_window
  maintenance_window = var.db_maintenance_window
  
  # Database credentials (stored in Secrets Manager)
  create_random_password = var.create_random_db_password
  master_username       = var.db_master_username
  
  tags = local.common_tags
}

# Storage Module (Amazon FSx for Windows File Server)
module "storage" {
  source = "../../modules/storage"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Networking
  subnet_ids = [module.networking.private_subnet_ids[0]]
  
  # Security
  security_group_ids = [module.security.file_server_security_group_id]
  kms_key_id        = module.security.kms_key_id
  
  # Storage configuration
  storage_capacity     = var.fsx_storage_capacity
  throughput_capacity  = var.fsx_throughput_capacity
  deployment_type      = var.environment == "prod" ? "MULTI_AZ_1" : "SINGLE_AZ_2"
  
  # Backup configuration
  backup_retention_days = var.fsx_backup_retention_days
  backup_start_time    = var.fsx_backup_start_time
  maintenance_start_time = var.fsx_maintenance_start_time
  
  # Integration with Entra AD
  entra_domain_name = var.entra_domain_name
  
  tags = local.common_tags
}

# Compute Module (Internal-only with auto-scaling)
module "compute" {
  source = "../../modules/compute"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Networking (all internal)
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  management_subnet_ids = module.networking.management_subnet_ids
  
  # Security groups
  application_security_group_id = module.security.application_security_group_id
  integration_security_group_id = module.security.integration_security_group_id
  bastion_security_group_id     = module.security.bastion_security_group_id
  internal_alb_security_group_id = module.security.internal_alb_security_group_id
  
  # Instance configuration
  windows_ami_id        = data.aws_ami.windows_2024.id
  instance_profile_name = module.security.ec2_instance_profile_name
  kms_key_id           = module.security.kms_key_id
  
  # Application servers (auto-scaling)
  app_instance_type          = var.app_instance_type
  app_min_size              = var.app_min_size
  app_max_size              = var.app_max_size
  app_desired_capacity      = var.app_desired_capacity
  enable_mixed_instance_scaling = var.enable_mixed_instance_scaling
  
  # Integration server
  integration_instance_type = var.integration_instance_type
  
  # Bastion host for management
  bastion_instance_type = var.bastion_instance_type
  
  # Entra AD configuration
  entra_tenant_id   = var.entra_tenant_id
  entra_domain_name = var.entra_domain_name
  
  # File system integration
  fsx_dns_name = module.storage.fsx_dns_name
  
  # Database connection
  db_endpoint = module.database.db_endpoint
  db_name     = module.database.db_name
  
  # Internal DNS
  internal_domain_name = "${var.customer_code}.${var.internal_domain_suffix}"
  
  # Auto-scaling configuration
  scale_up_threshold     = var.scale_up_threshold
  scale_down_threshold   = var.scale_down_threshold
  enable_predictive_scaling = var.enable_predictive_scaling
  
  tags = local.common_tags
}

# Monitoring Module
module "monitoring" {
  source = "../../modules/monitoring"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Resources to monitor
  auto_scaling_group_names = module.compute.auto_scaling_group_names
  load_balancer_arn_suffix = module.compute.internal_load_balancer_arn_suffix
  db_instance_identifier   = module.database.db_instance_identifier
  
  # Notification configuration
  notification_email        = var.notification_email
  enable_teams_integration  = var.enable_teams_integration
  teams_webhook_url        = var.teams_webhook_url
  
  # Monitoring configuration
  enable_enhanced_monitoring = var.enable_enhanced_monitoring
  enable_application_insights = var.enable_application_insights
  
  tags = local.common_tags
}

# ADHICS Compliance Module (optional)
module "adhics_compliance" {
  count  = var.enable_adhics_compliance ? 1 : 0
  source = "../../modules/adhics-compliance"
  
  name_prefix   = local.name_prefix
  customer_code = var.customer_code
  
  # Security and compliance
  kms_key_id         = module.security.kms_key_id
  load_balancer_arn  = module.compute.internal_load_balancer_arn
  vpc_id            = module.networking.vpc_id
  
  # Compliance configuration
  log_retention_days = var.log_retention_days
  enable_guardduty  = var.enable_guardduty
  enable_security_hub = var.enable_security_hub
  enable_config     = var.enable_config
  
  tags = merge(local.common_tags, {
    Compliance = "ADHICS"
    Purpose   = "HealthcareCompliance"
  })
}

# Private Route 53 Hosted Zone for Internal DNS
resource "aws_route53_zone" "internal" {
  name = "${var.customer_code}.${var.internal_domain_suffix}"
  
  vpc {
    vpc_id = module.networking.vpc_id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-internal-dns"
    Type = "Internal"
  })
}

# Internal DNS Records
resource "aws_route53_record" "emr_internal" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "emr.${var.customer_code}.${var.internal_domain_suffix}"
  type    = "A"
  
  alias {
    name                   = module.compute.internal_load_balancer_dns_name
    zone_id                = module.compute.internal_load_balancer_zone_id
    evaluate_target_health = true
  }
}

# Customer-specific S3 bucket for logs and backups
resource "aws_s3_bucket" "customer_data" {
  bucket = "${var.customer_code}-cortex-emr-data-${random_string.bucket_suffix.result}"
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-data-bucket"
    Purpose = "CustomerData"
  })
}

resource "aws_s3_bucket_versioning" "customer_data" {
  bucket = aws_s3_bucket.customer_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "customer_data" {
  bucket = aws_s3_bucket.customer_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.security.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "customer_data" {
  bucket = aws_s3_bucket.customer_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Random string for unique resource naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}