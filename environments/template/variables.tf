# environments/template/variables.tf

# =============================================================================
# TERRAFORM CLOUD CONFIGURATION
# =============================================================================

variable "terraform_cloud_organization" {
  description = "Terraform Cloud organization name"
  type        = string
  default     = "your-healthcare-org"
}

variable "terraform_cloud_workspace" {
  description = "Terraform Cloud workspace name (will be customer-specific)"
  type        = string
}

# =============================================================================
# CUSTOMER IDENTIFICATION
# =============================================================================

variable "customer_name" {
  description = "Full customer organization name"
  type        = string
  validation {
    condition     = length(var.customer_name) > 0
    error_message = "Customer name cannot be empty."
  }
}

variable "customer_code" {
  description = "Short customer code (3-8 characters, alphanumeric only)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.customer_code))
    error_message = "Customer code must be 3-8 characters, lowercase alphanumeric only."
  }
}

variable "cost_center" {
  description = "Customer cost center or billing code"
  type        = string
  default     = ""
}

variable "deployed_by" {
  description = "Name/email of person deploying this infrastructure"
  type        = string
  default     = "terraform-automation"
}

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "me-central-1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for customer VPC (must be /16 for auto subnet calculation)"
  type        = string
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && split("/", var.vpc_cidr)[1] == "16"
    error_message = "VPC CIDR must be a valid /16 CIDR block (e.g., 10.100.0.0/16)."
  }
}

variable "on_premises_cidrs" {
  description = "List of on-premises network CIDR blocks that need access"
  type        = list(string)
  default     = ["192.168.0.0/16", "172.16.0.0/12"]
  validation {
    condition     = alltrue([for cidr in var.on_premises_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All on-premises CIDRs must be valid CIDR blocks."
  }
}

variable "management_ip_ranges" {
  description = "IP ranges allowed for management access (bastion, etc.)"
  type        = list(string)
  default     = []
}

variable "internal_domain_suffix" {
  description = "Internal domain suffix for private DNS (e.g., healthcare.local)"
  type        = string
  default     = "healthcare.local"
}

# =============================================================================
# FORTIGATE VPN CONFIGURATION
# =============================================================================

variable "fortigate_public_ip" {
  description = "Public IP address of the FortiGate firewall"
  type        = string
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.fortigate_public_ip))
    error_message = "FortiGate public IP must be a valid IPv4 address."
  }
}

variable "fortigate_bgp_asn" {
  description = "BGP ASN for FortiGate customer gateway"
  type        = number
  default     = 65000
  validation {
    condition     = var.fortigate_bgp_asn >= 64512 && var.fortigate_bgp_asn <= 65534
    error_message = "BGP ASN must be in private range (64512-65534)."
  }
}

variable "vpn_tunnel_inside_cidrs" {
  description = "Inside CIDR blocks for VPN tunnels (must be /30 networks)"
  type        = list(string)
  default     = ["169.254.10.0/30", "169.254.11.0/30"]
  validation {
    condition = alltrue([
      for cidr in var.vpn_tunnel_inside_cidrs : 
      can(cidrhost(cidr, 0)) && split("/", cidr)[1] == "30"
    ])
    error_message = "VPN tunnel CIDRs must be valid /30 networks."
  }
}

variable "vpn_shared_secret" {
  description = "Shared secret for VPN connection (will be stored in Secrets Manager)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.vpn_shared_secret) >= 8
    error_message = "VPN shared secret must be at least 8 characters long."
  }
}

# =============================================================================
# ENTRA AD (AZURE AD) CONFIGURATION
# =============================================================================

variable "entra_tenant_id" {
  description = "Azure AD (Entra ID) tenant ID"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.entra_tenant_id))
    error_message = "Entra tenant ID must be a valid GUID."
  }
}

variable "entra_client_id" {
  description = "Azure AD application client ID for EMR application"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.entra_client_id))
    error_message = "Entra client ID must be a valid GUID."
  }
}

variable "entra_client_secret" {
  description = "Azure AD application client secret"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.entra_client_secret) >= 1
    error_message = "Entra client secret cannot be empty."
  }
}

variable "entra_domain_name" {
  description = "Azure AD domain name (e.g., company.onmicrosoft.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.entra_domain_name))
    error_message = "Entra domain name must be a valid domain format."
  }
}

variable "entra_allowed_groups" {
  description = "List of Entra AD groups allowed to access the EMR system"
  type        = list(string)
  default     = ["EMR-Users", "Healthcare-Staff"]
}

variable "entra_security_group_mappings" {
  description = "Mapping of Entra AD groups to EMR application roles"
  type = map(object({
    emr_role    = string
    permissions = list(string)
  }))
  default = {
    "EMR-Administrators" = {
      emr_role    = "admin"
      permissions = ["read", "write", "admin", "audit"]
    }
    "EMR-Doctors" = {
      emr_role    = "physician"
      permissions = ["read", "write", "prescribe"]
    }
    "EMR-Nurses" = {
      emr_role    = "nurse"
      permissions = ["read", "write", "vitals"]
    }
    "EMR-Staff" = {
      emr_role    = "staff"
      permissions = ["read"]
    }
  }
}

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.m5.xlarge"
  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "Database instance class must be a valid RDS instance type."
  }
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for RDS (GB)"
  type        = number
  default     = 500
  validation {
    condition     = var.db_allocated_storage >= 100 && var.db_allocated_storage <= 65536
    error_message = "Database storage must be between 100 and 65536 GB."
  }
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS auto-scaling (GB)"
  type        = number
  default     = 1000
  validation {
    condition     = var.db_max_allocated_storage >= var.db_allocated_storage
    error_message = "Maximum storage must be greater than or equal to initial storage."
  }
}

variable "db_backup_retention_period" {
  description = "Database backup retention period (days)"
  type        = number
  default     = 30
  validation {
    condition     = var.db_backup_retention_period >= 7 && var.db_backup_retention_period <= 35
    error_message = "Backup retention must be between 7 and 35 days."
  }
}

variable "db_backup_window" {
  description = "Database backup window (UTC time)"
  type        = string
  default     = "03:00-04:00"
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.db_backup_window))
    error_message = "Backup window must be in HH:MM-HH:MM format."
  }
}

variable "db_maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "fri:04:00-fri:05:00"
  validation {
    condition     = can(regex("^(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]-(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]$", var.db_maintenance_window))
    error_message = "Maintenance window must be in ddd:hh:mm-ddd:hh:mm format."
  }
}

variable "create_random_db_password" {
  description = "Create random database password (stored in Secrets Manager)"
  type        = bool
  default     = true
}

variable "db_master_username" {
  description = "Database master username"
  type        = string
  default     = "emradmin"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,15}$", var.db_master_username))
    error_message = "Database username must be 3-16 characters, start with letter, alphanumeric only."
  }
}

# =============================================================================
# COMPUTE CONFIGURATION
# =============================================================================

variable "app_instance_type" {
  description = "Instance type for application servers"
  type        = string
  default     = "m5.xlarge"
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.app_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "app_min_size" {
  description = "Minimum number of application servers"
  type        = number
  default     = 2
  validation {
    condition     = var.app_min_size >= 1 && var.app_min_size <= 10
    error_message = "Minimum size must be between 1 and 10."
  }
}

variable "app_max_size" {
  description = "Maximum number of application servers"
  type        = number
  default     = 8
  validation {
    condition     = var.app_max_size >= var.app_min_size && var.app_max_size <= 50
    error_message = "Maximum size must be between minimum size and 50."
  }
}

variable "app_desired_capacity" {
  description = "Desired number of application servers"
  type        = number
  default     = 2
  validation {
    condition     = var.app_desired_capacity >= var.app_min_size && var.app_desired_capacity <= var.app_max_size
    error_message = "Desired capacity must be between minimum and maximum size."
  }
}

variable "integration_instance_type" {
  description = "Instance type for integration server"
  type        = string
  default     = "m5.large"
}

variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.small"
}

variable "enable_mixed_instance_scaling" {
  description = "Enable mixed instance types for intelligent scaling"
  type        = bool
  default     = true
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "fsx_storage_capacity" {
  description = "FSx storage capacity (GB)"
  type        = number
  default     = 1024
  validation {
    condition     = var.fsx_storage_capacity >= 32 && var.fsx_storage_capacity <= 65536
    error_message = "FSx storage capacity must be between 32 and 65536 GB."
  }
}

variable "fsx_throughput_capacity" {
  description = "FSx throughput capacity (MB/s)"
  type        = number
  default     = 16
  validation {
    condition     = contains([8, 16, 32, 64, 128, 256, 512, 1024, 2048], var.fsx_throughput_capacity)
    error_message = "FSx throughput must be one of: 8, 16, 32, 64, 128, 256, 512, 1024, 2048."
  }
}

variable "fsx_backup_retention_days" {
  description = "FSx backup retention (days)"
  type        = number
  default     = 30
  validation {
    condition     = var.fsx_backup_retention_days >= 7 && var.fsx_backup_retention_days <= 90
    error_message = "FSx backup retention must be between 7 and 90 days."
  }
}

variable "fsx_backup_start_time" {
  description = "FSx backup start time (HH:MM UTC)"
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.fsx_backup_start_time))
    error_message = "Backup start time must be in HH:MM format."
  }
}

variable "fsx_maintenance_start_time" {
  description = "FSx maintenance start time (d:HH:MM)"
  type        = string
  default     = "1:02:00"
  validation {
    condition     = can(regex("^[1-7]:[0-2][0-9]:[0-5][0-9]$", var.fsx_maintenance_start_time))
    error_message = "Maintenance start time must be in d:HH:MM format (1=Sunday)."
  }
}

# =============================================================================
# AUTO-SCALING CONFIGURATION
# =============================================================================

variable "scale_up_threshold" {
  description = "CPU threshold for scaling up (%)"
  type        = number
  default     = 70
  validation {
    condition     = var.scale_up_threshold >= 50 && var.scale_up_threshold <= 90
    error_message = "Scale up threshold must be between 50 and 90."
  }
}

variable "scale_down_threshold" {
  description = "CPU threshold for scaling down (%)"
  type        = number
  default     = 30
  validation {
    condition     = var.scale_down_threshold >= 10 && var.scale_down_threshold <= 50
    error_message = "Scale down threshold must be between 10 and 50."
  }
}

variable "enable_predictive_scaling" {
  description = "Enable predictive scaling based on usage patterns"
  type        = bool
  default     = true
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  validation {
    condition     = can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_teams_integration" {
  description = "Enable Microsoft Teams integration for alerts"
  type        = bool
  default     = false
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_application_insights" {
  description = "Enable application performance monitoring"
  type        = bool
  default     = true
}

# =============================================================================
# COMPLIANCE AND SECURITY
# =============================================================================

variable "enable_adhics_compliance" {
  description = "Enable ADHICS compliance features"
  type        = bool
  default     = true
}

variable "enable_enhanced_logging" {
  description = "Enable enhanced security logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period (days)"
  type        = number
  default     = 2555  # 7 years for ADHICS compliance
  validation {
    condition     = contains([30, 90, 180, 365, 400, 545, 731, 1827, 2555, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty threat detection"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config for compliance monitoring"
  type        = bool
  default     = true
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "use_reserved_instances" {
  description = "Use reserved instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling for predictable usage patterns"
  type        = bool
  default     = false
}

variable "business_hours_schedule" {
  description = "Business hours schedule for scaled-up capacity (cron format)"
  type = object({
    scale_up   = string  # e.g., "0 7 * * MON-FRI"
    scale_down = string  # e.g., "0 19 * * MON-FRI" 
  })
  default = {
    scale_up   = "0 7 * * MON-FRI"
    scale_down = "0 19 * * MON-FRI"
  }
}

# =============================================================================
# BACKUP AND DISASTER RECOVERY
# =============================================================================

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup (may impact data residency)"
  type        = bool
  default     = false
}

variable "backup_schedule" {
  description = "Backup schedule configuration"
  type = object({
    database_backup = string  # e.g., "cron(0 1 * * ? *)"
    fsx_backup     = string  # e.g., "cron(0 2 * * ? *)"
    ebs_backup     = string  # e.g., "cron(0 3 ? * SUN *)"
  })
  default = {
    database_backup = "cron(0 1 * * ? *)"     # Daily at 1 AM UTC
    fsx_backup     = "cron(0 2 * * ? *)"      # Daily at 2 AM UTC  
    ebs_backup     = "cron(0 3 ? * SUN *)"    # Weekly on Sunday at 3 AM UTC
  }
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

variable "feature_flags" {
  description = "Feature flags for optional components"
  type = object({
    enable_waf                = bool
    enable_cloudfront        = bool
    enable_elasticsearch     = bool
    enable_redis_cache       = bool
    enable_backup_automation = bool
    enable_disaster_recovery = bool
  })
  default = {
    enable_waf                = false  # Not needed for internal-only access
    enable_cloudfront        = false  # Not needed for internal-only access
    enable_elasticsearch     = false  # Optional log analytics
    enable_redis_cache       = true   # Session management
    enable_backup_automation = true
    enable_disaster_recovery = true
  }
}