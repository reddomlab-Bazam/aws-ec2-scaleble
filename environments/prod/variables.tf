# environments/prod/variables.tf

# Basic Configuration - UAE Region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "me-central-1"  # Middle East (UAE)
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
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
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.30.0/24", "10.0.40.0/24"]
}

variable "on_premises_cidr" {
  description = "CIDR block for on-premises network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "vpn_customer_gateway_ip" {
  description = "Public IP address of the on-premises VPN gateway"
  type        = string
}

variable "on_premises_dns_ips" {
  description = "DNS server IPs in on-premises network"
  type        = list(string)
  default     = ["192.168.1.10", "192.168.1.11"]
}

# Active Directory Configuration
variable "ad_domain_name" {
  description = "Active Directory domain name"
  type        = string
  default     = "corp.example.com"
}

variable "ad_domain_netbios" {
  description = "NetBIOS name for AD domain"
  type        = string
  default     = "CORP"
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
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.m5.xlarge"  # 4 vCPU, 16 GB RAM - can be upgraded to db.m5.2xlarge for 8 vCPU, 32 GB
}

variable "db_allocated_storage" {
  description = "Initial storage allocation for RDS"
  type        = number
  default     = 500
}

variable "db_max_allocated_storage" {
  description = "Maximum storage allocation for RDS"
  type        = number
  default     = 1000
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
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
}

# Application Server Configuration
variable "app_instance_type" {
  description = "Instance type for application servers"
  type        = string
  default     = "m5.xlarge"  # 4 vCPU, 16 GB RAM - can be upgraded to m5.2xlarge for 8 vCPU, 32 GB
}

variable "app_min_size" {
  description = "Minimum number of application servers"
  type        = number
  default     = 1
}

variable "app_max_size" {
  description = "Maximum number of application servers"
  type        = number
  default     = 4
}

variable "app_desired_capacity" {
  description = "Desired number of application servers"
  type        = number
  default     = 2
}

# Integration Server Configuration
variable "integration_instance_type" {
  description = "Instance type for integration server"
  type        = string
  default     = "m5.large"  # 2 vCPU, 8 GB RAM - can be upgraded to m5.xlarge for 4 vCPU, 16 GB
}

# File System Configuration
variable "fsx_storage_capacity" {
  description = "Storage capacity for FSx file system in GB"
  type        = number
  default     = 3072  # 3 TB
}

variable "fsx_throughput_capacity" {
  description = "Throughput capacity for FSx file system in MB/s"
  type        = number
  default     = 34
}

# DNS Configuration
variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"
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
}

# Security Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_backup_encryption" {
  description = "Enable encryption for backups"
  type        = bool
  default     = true
}

# Cost Optimization
variable "use_reserved_instances" {
  description = "Use reserved instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Use spot instances for non-critical workloads"
  type        = bool
  default     = false
}

# Enhanced Auto-Scaling Configuration
variable "enable_mixed_instance_scaling" {
  description = "Enable mixed instance types for intelligent scaling"
  type        = bool
  default     = true
}

variable "enable_predictive_scaling" {
  description = "Enable ML-based predictive scaling"
  type        = bool
  default     = true
}

variable "enable_session_store" {
  description = "Enable Redis session store for session persistence"
  type        = bool
  default     = true
}

variable "enable_read_replica" {
  description = "Enable RDS read replica for database scaling"
  type        = bool
  default     = true
}

variable "enable_sticky_sessions" {
  description = "Enable sticky sessions on load balancer"
  type        = bool
  default     = true
}

variable "memory_scale_threshold" {
  description = "Memory threshold for auto-scaling"
  type        = number
  default     = 80
}

variable "response_time_threshold" {
  description = "Response time threshold in milliseconds for scaling"
  type        = number
  default     = 2000
}

variable "session_timeout" {
  description = "Session timeout in seconds"
  type        = number
  default     = 86400
}

variable "warm_pool_size" {
  description = "Number of warm pool instances for faster scaling"
  type        = number
  default     = 2
}

# Application Configuration
variable "application_port" {
  description = "Port for the Cortex EMR application"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for load balancer"
  type        = string
  default     = "/health"
}

# Backup Configuration
variable "ebs_backup_schedule" {
  description = "Schedule for EBS snapshots"
  type        = string
  default     = "cron(0 2 ? * SUN *)"  # Every Sunday at 2 AM
}

variable "rds_backup_schedule" {
  description = "Schedule for RDS snapshots"
  type        = string
  default     = "cron(0 1 * * ? *)"    # Daily at 1 AM
}