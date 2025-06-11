# config/customers/customer-template.tfvars
# Customer-Specific Configuration Template
# Copy this file and customize for each customer deployment

# =============================================================================
# CUSTOMER IDENTIFICATION
# =============================================================================

# Full customer organization name
customer_name = "Al Noor Hospital"

# Short customer code (3-8 characters, lowercase alphanumeric)
# This will be used in resource naming: e.g., alnoor-prod-app-server
customer_code = "alnoor"

# Cost center or billing code for the customer
cost_center = "IT-INFRASTRUCTURE-2024"

# Person/team deploying this infrastructure
deployed_by = "healthcare-solutions-team@yourcompany.com"

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

# Environment: dev, test, or prod
environment = "prod"

# AWS region (UAE region for data sovereignty)
aws_region = "me-central-1"

# Terraform Cloud workspace name (will be: customer-code-environment)
terraform_cloud_workspace = "alnoor-prod"

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

# Customer VPC CIDR (must be /16, unique per customer)
# Recommended ranges: 10.100.0.0/16, 10.101.0.0/16, 10.102.0.0/16, etc.
vpc_cidr = "10.100.0.0/16"

# Customer's on-premises network CIDRs
on_premises_cidrs = [
  "192.168.0.0/16",    # Customer's main office network
  "172.16.0.0/12"      # Customer's branch networks
]

# Management IP ranges (for bastion access, monitoring, etc.)
management_ip_ranges = [
  "10.0.0.0/24"        # Your company's management network
]

# Internal domain suffix for private DNS
internal_domain_suffix = "healthcare.local"

# =============================================================================
# FORTIGATE VPN CONFIGURATION
# =============================================================================

# Customer's FortiGate public IP address
fortigate_public_ip = "203.0.113.100"  # Replace with actual IP

# BGP ASN for customer's FortiGate (private ASN range)
fortigate_bgp_asn = 65001

# VPN tunnel inside CIDR blocks (AWS will assign specific IPs)
vpn_tunnel_inside_cidrs = [
  "169.254.10.0/30",   # Tunnel 1
  "169.254.11.0/30"    # Tunnel 2
]

# VPN shared secret (will be stored securely in AWS Secrets Manager)
vpn_shared_secret = "your-secure-vpn-key-here-change-this"

# =============================================================================
# ENTRA AD (AZURE AD) CONFIGURATION
# =============================================================================

# Customer's Azure AD tenant ID
entra_tenant_id = "12345678-1234-1234-1234-123456789012"

# Azure AD application client ID (created for EMR access)
entra_client_id = "87654321-4321-4321-4321-210987654321"

# Azure AD application client secret
entra_client_secret = "your-azure-ad-client-secret-here"

# Customer's Azure AD domain name
entra_domain_name = "alnoor.onmicrosoft.com"

# Azure AD groups allowed to access EMR system
entra_allowed_groups = [
  "EMR-Administrators",
  "EMR-Doctors", 
  "EMR-Nurses",
  "EMR-Staff",
  "EMR-Pharmacy",
  "EMR-Lab-Technicians"
]

# Mapping of Azure AD groups to EMR roles and permissions
entra_security_group_mappings = {
  "EMR-Administrators" = {
    emr_role    = "admin"
    permissions = ["read", "write", "admin", "audit", "reports", "user-management"]
  }
  "EMR-Doctors" = {
    emr_role    = "physician"
    permissions = ["read", "write", "prescribe", "reports", "patient-records"]
  }
  "EMR-Nurses" = {
    emr_role    = "nurse"
    permissions = ["read", "write", "vitals", "patient-care", "medications"]
  }
  "EMR-Staff" = {
    emr_role    = "staff"
    permissions = ["read", "appointments", "billing"]
  }
  "EMR-Pharmacy" = {
    emr_role    = "pharmacist"
    permissions = ["read", "medications", "prescriptions", "inventory"]
  }
  "EMR-Lab-Technicians" = {
    emr_role    = "lab-tech"
    permissions = ["read", "write", "lab-results", "specimens"]
  }
}

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# Database instance class (recommended: db.m5.xlarge for prod, db.t3.large for dev)
db_instance_class = "db.m5.xlarge"  # 4 vCPU, 16 GB RAM

# Database storage configuration
db_allocated_storage     = 500   # Initial storage (GB)
db_max_allocated_storage = 2000  # Maximum auto-scaling storage (GB)

# Backup configuration
db_backup_retention_period = 30              # Backup retention (days)
db_backup_window          = "23:00-01:00"   # 3 AM - 5 AM UAE time
db_maintenance_window     = "fri:01:00-fri:02:00"  # Friday 5 AM - 6 AM UAE time

# Database credentials
create_random_db_password = true      # Generate secure random password
db_master_username       = "emradmin"

# =============================================================================
# COMPUTE CONFIGURATION
# =============================================================================

# Application server configuration
app_instance_type     = "m5.xlarge"  # 4 vCPU, 16 GB RAM (upgrade to m5.2xlarge for 8 vCPU, 32 GB)
app_min_size         = 2             # Minimum instances for HA
app_max_size         = 8             # Maximum instances for peak load
app_desired_capacity = 2             # Starting capacity

# Integration server (for external system connections)
integration_instance_type = "m5.large"  # 2 vCPU, 8 GB RAM

# Bastion host for management access
bastion_instance_type = "t3.small"  # 2 vCPU, 2 GB RAM

# Auto-scaling features
enable_mixed_instance_scaling = true  # Use different instance sizes intelligently

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

# Amazon FSx for Windows File Server
fsx_storage_capacity    = 1024  # Storage capacity (GB) - minimum 32 GB
fsx_throughput_capacity = 16    # Throughput (MB/s) - 8, 16, 32, 64, etc.

# Backup configuration for FSx
fsx_backup_retention_days = 30              # Backup retention (days)
fsx_backup_start_time    = "22:00"         # 2 AM UAE time
fsx_maintenance_start_time = "1:22:00"     # Sunday 2 AM UAE time

# =============================================================================
# AUTO-SCALING CONFIGURATION
# =============================================================================

# CPU thresholds for auto-scaling
scale_up_threshold   = 70    # Scale up when CPU > 70%
scale_down_threshold = 30    # Scale down when CPU < 30%

# Advanced scaling features
enable_predictive_scaling = true   # ML-based predictive scaling

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Primary notification email for alerts
notification_email = "it-team@alnoor.ae"

# Microsoft Teams integration (optional)
enable_teams_integration = true
teams_webhook_url       = "https://outlook.office.com/webhook/your-teams-webhook-url"

# Monitoring features
enable_enhanced_monitoring   = true
enable_application_insights = true

# =============================================================================
# COMPLIANCE AND SECURITY
# =============================================================================

# ADHICS compliance features (required for UAE healthcare)
enable_adhics_compliance = true
enable_enhanced_logging  = true
log_retention_days      = 2555  # 7 years for ADHICS compliance

# Security services
enable_guardduty   = true  # Threat detection
enable_security_hub = true  # Security findings aggregation
enable_config      = true  # Compliance monitoring

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

# Cost optimization features
enable_cost_optimization = true
use_reserved_instances   = true

# Scheduled scaling for predictable usage patterns
enable_scheduled_scaling = true
business_hours_schedule = {
  scale_up   = "0 6 * * SUN-THU"   # 6 AM UAE time, Sunday-Thursday
  scale_down = "0 18 * * SUN-THU"  # 6 PM UAE time, Sunday-Thursday
}

# =============================================================================
# BACKUP AND DISASTER RECOVERY
# =============================================================================

# Cross-region backup (disabled for data sovereignty)
enable_cross_region_backup = false

# Backup schedules (UAE timezone = UTC+4)
backup_schedule = {
  database_backup = "cron(0 21 * * ? *)"    # 1 AM UAE time daily
  fsx_backup     = "cron(0 22 * * ? *)"     # 2 AM UAE time daily
  ebs_backup     = "cron(0 23 ? * SAT *)"   # 3 AM UAE time Saturday
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

# Optional features configuration
feature_flags = {
  enable_waf                = false  # Not needed for internal-only access
  enable_cloudfront        = false  # Not needed for internal-only access
  enable_elasticsearch     = false  # Optional: advanced log analytics
  enable_redis_cache       = true   # Recommended: session management
  enable_backup_automation = true   # Recommended: automated backups
  enable_disaster_recovery = true   # Recommended: DR procedures
}

# =============================================================================
# CUSTOMER-SPECIFIC CUSTOMIZATIONS
# =============================================================================

# Add any customer-specific variables here
# Example:
# custom_integration_endpoints = [
#   "https://lab-system.alnoor.ae/api",
#   "https://pharmacy-system.alnoor.ae/api"
# ]

# custom_compliance_requirements = {
#   enable_pci_compliance = false
#   enable_hipaa_compliance = false  # ADHICS covers healthcare compliance for UAE
#   enable_iso27001 = true
# }