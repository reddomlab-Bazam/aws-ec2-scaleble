# environments/prod/terraform.tfvars

# Basic Configuration - UAE Region
aws_region   = "me-central-1"  # Middle East (UAE)
environment  = "prod"
project_name = "cortex-emr"

# UAE Availability Zones
availability_zones = ["me-central-1a", "me-central-1b"]

# Networking Configuration
vpc_cidr                = "10.0.0.0/16"
public_subnet_cidrs     = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs    = ["10.0.10.0/24", "10.0.20.0/24"]
db_subnet_cidrs         = ["10.0.30.0/24", "10.0.40.0/24"]
on_premises_cidr        = "192.168.0.0/16"
vpn_customer_gateway_ip = "203.0.113.12"  # Replace with your actual public IP
on_premises_dns_ips     = ["192.168.1.10", "192.168.1.11"]

# Active Directory Configuration - UAE Compliant
ad_domain_name      = "uae.corp.yourcompany.com"
ad_domain_netbios   = "UAECORP"
ad_service_account  = "svc-aws-connector"
ad_admin_password   = "SecurePassword123!"  # Use AWS Secrets Manager in production

# Database Configuration - ADHICS Compliant
db_instance_class           = "db.m5.xlarge"    # 4 vCPU, 16 GB - upgrade to db.m5.2xlarge for 8 vCPU, 32 GB
db_allocated_storage        = 500
db_max_allocated_storage    = 1000
db_backup_retention_period  = 30
db_backup_window           = "03:00-04:00"      # UAE time consideration
db_maintenance_window      = "fri:04:00-fri:05:00"  # Friday maintenance (weekend in UAE)
db_master_username         = "admin"
db_master_password         = "DatabasePassword123!"  # Use AWS Secrets Manager in production

# Application Server Configuration
app_instance_type    = "m5.xlarge"  # 4 vCPU, 16 GB - upgrade to m5.2xlarge for 8 vCPU, 32 GB
app_min_size         = 1
app_max_size         = 4
app_desired_capacity = 2

# Integration Server Configuration
integration_instance_type = "m5.large"  # 2 vCPU, 8 GB - upgrade to m5.xlarge for 4 vCPU, 16 GB

# File System Configuration
fsx_storage_capacity    = 3072  # 3 TB
fsx_throughput_capacity = 34    # MB/s

# DNS Configuration - UAE Domain
domain_name    = "yourcompany.ae"  # UAE domain
emr_subdomain  = "emr"

# Monitoring Configuration - ADHICS Compliant
notification_email = "security-team@yourcompany.ae"

# Security Configuration - ADHICS Enhanced
enable_detailed_monitoring = true
enable_backup_encryption   = true

# Cost Optimization
use_reserved_instances = true
enable_spot_instances  = false  # Disabled for healthcare workloads

# Scaling Configuration
scale_up_threshold   = 70
scale_down_threshold = 30

# Application Configuration
application_port    = 8080
health_check_path   = "/health"

# Backup Configuration - UAE Timezone (UTC+4)
ebs_backup_schedule = "cron(0 22 ? * THU *)"  # Thursday 10 PM UTC (2 AM Friday UAE time)
rds_backup_schedule = "cron(0 23 * * ? *)"    # Daily 11 PM UTC (3 AM UAE time)

# ADHICS Compliance Settings
# Additional production specific settings for ADHICS compliance

# Enhanced logging for ADHICS audit requirements
enable_enhanced_logging = true
log_retention_days     = 365  # 1 year retention for ADHICS compliance

# Data sovereignty - ensure data remains in UAE
data_residency_region = "me-central-1"
cross_region_backup   = false  # Keep all data in UAE for ADHICS compliance

# Enhanced security for healthcare data
enable_waf                    = true
enable_shield_advanced       = true
enable_guardduty             = true
enable_security_hub          = true
enable_config_compliance     = true

# ADHICS required monitoring
enable_cloudtrail_insights   = true
enable_vpc_flow_logs        = true
enable_dns_query_logging    = true

# Additional Production Specific Settings
# These values should be adjusted based on your specific requirements

# For matching the application provider specs exactly:
# app_instance_type = "m5.2xlarge"      # 8 vCPU, 32 GB RAM
# db_instance_class = "db.m5.2xlarge"   # 8 vCPU, 32 GB RAM
# integration_instance_type = "m5.xlarge" # 4 vCPU, 16 GB RAM

# For cost optimization start with smaller instances and scale up:
# app_instance_type = "m5.large"        # 2 vCPU, 8 GB RAM
# db_instance_class = "db.m5.large"     # 2 vCPU, 8 GB RAM