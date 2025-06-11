# environments/prod/main.tf

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
      name = "cortex-emr-prod"
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
      Owner       = "IT-Team"
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
  
  # On-premises connectivity
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

# Active Directory
resource "aws_directory_service_directory" "main" {
  name     = var.ad_domain_name
  password = var.ad_admin_password
  type     = "ADConnector"
  size     = "Small"
  
  connect_settings {
    customer_dns_ips  = var.on_premises_dns_ips
    customer_username = var.ad_service_account
    subnet_ids        = module.networking.private_subnet_ids
    vpc_id            = module.networking.vpc_id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ad-connector"
  })
}

# Database Module
module "database" {
  source = "../../modules/database"
  
  name_prefix = local.name_prefix
  
  # Networking
  vpc_id               = module.networking.vpc_id
  db_subnet_group_name = module.networking.db_subnet_group_name
  
  # Security
  security_group_ids = [
    module.security.database_security_group_id
  ]
  
  # Database configuration
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  
  # Backup and maintenance
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  
  # Credentials
  master_username = var.db_master_username
  master_password = var.db_master_password
  
  tags = local.common_tags
}

# Storage Module (Amazon FSx for Windows File Server)
module "storage" {
  source = "../../modules/storage"
  
  name_prefix = local.name_prefix
  
  # Networking
  subnet_ids = module.networking.private_subnet_ids
  
  # Security
  security_group_ids = [
    module.security.file_server_security_group_id
  ]
  
  # Active Directory
  active_directory_id = aws_directory_service_directory.main.id
  
  # Storage configuration
  storage_capacity    = var.fsx_storage_capacity
  throughput_capacity = var.fsx_throughput_capacity
  
  tags = local.common_tags
}

# Compute Module
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
  
  # AMI and instance configuration
  windows_ami_id = data.aws_ami.windows_2024.id
  
  # Application servers
  app_instance_type     = var.app_instance_type
  app_min_size         = var.app_min_size
  app_max_size         = var.app_max_size
  app_desired_capacity = var.app_desired_capacity
  
  # Integration server
  integration_instance_type = var.integration_instance_type
  
  # Active Directory
  domain_name           = var.ad_domain_name
  domain_netbios_name   = var.ad_domain_netbios
  domain_admin_user     = var.ad_service_account
  domain_admin_password = var.ad_admin_password
  
  # File system
  fsx_dns_name = module.storage.fsx_dns_name
  
  # Database connection
  db_endpoint = module.database.db_endpoint
  db_name     = module.database.db_name
  
  tags = local.common_tags
}

# Monitoring Module
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

# ADHICS Compliance Module for UAE Healthcare Standards
module "adhics_compliance" {
  source = "../../modules/adhics-compliance"
  
  name_prefix = local.name_prefix
  
  # Security and compliance
  kms_key_id         = module.security.kms_key_id
  load_balancer_arn  = module.compute.load_balancer_arn
  vpc_id            = module.networking.vpc_id
  
  tags = merge(local.common_tags, {
    Compliance = "ADHICS"
    DataSovereignty = "UAE"
    HealthcareCompliance = "Enabled"
  })
}

# Associate WAF with Application Load Balancer
resource "aws_wafv2_web_acl_association" "alb_waf" {
  resource_arn = module.compute.load_balancer_arn
  web_acl_arn  = module.adhics_compliance.waf_web_acl_arn
}

# Route 53 DNS
resource "aws_route53_zone" "main" {
  name = var.domain_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dns-zone"
  })
}

resource "aws_route53_record" "emr" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.emr_subdomain}.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = module.compute.load_balancer_dns_name
    zone_id                = module.compute.load_balancer_zone_id
    evaluate_target_health = true
  }
}

# SSL Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = "${var.emr_subdomain}.${var.domain_name}"
  validation_method = "DNS"
  
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssl-cert"
  })
}

# Certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  
  timeouts {
    create = "10m"
  }
}