# variables.tf - Simplified Variables with Existing Infrastructure Integration

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cortex-emr"
}

# Existing Infrastructure Integration
variable "use_existing_infrastructure" {
  description = "Use existing AWS infrastructure (VPC, VPN, Route53)"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to deploy into (if use_existing_infrastructure = true)"
  type        = string
  default     = ""
}

variable "existing_route53_zone_id" {
  description = "ID of existing Route 53 hosted zone"
  type        = string
  default     = ""
}

variable "existing_route53_domain" {
  description = "Domain name of existing Route 53 hosted zone (e.g., company.local)"
  type        = string
  default     = ""
}

# FortiGate VPN Integration
variable "existing_vpn_gateway_id" {
  description = "ID of existing VPN Gateway connected to FortiGate"
  type        = string
  default     = ""
}

variable "fortigate_tunnel_info" {
  description = "FortiGate tunnel configuration information"
  type = object({
    tunnel_1_ip     = string  # Inside IP of tunnel 1 (e.g., 169.254.10.1/30)
    tunnel_2_ip     = string  # Inside IP of tunnel 2 (e.g., 169.254.11.1/30)
    on_premises_cidr = string # On-premises network CIDR (e.g., 192.168.0.0/16)
    tunnel_name     = string  # Name identifier for the tunnel
  })
  default = {
    tunnel_1_ip      = "169.254.10.1/30"
    tunnel_2_ip      = "169.254.11.1/30"
    on_premises_cidr = "192.168.0.0/16"
    tunnel_name      = "fortigate-tunnel"
  }
}

# Subnet Planning (to avoid conflicts)
variable "subnet_planning" {
  description = "Subnet CIDR blocks for Cortex EMR (ensure no conflicts with existing services)"
  type = object({
    public_subnet_cidrs  = list(string)  # For load balancers
    private_subnet_cidrs = list(string)  # For application servers
    database_subnet_cidrs = list(string) # For databases
  })
  default = {
    public_subnet_cidrs   = ["10.0.100.0/24", "10.0.101.0/24"]    # Adjust these to avoid conflicts
    private_subnet_cidrs  = ["10.0.110.0/24", "10.0.111.0/24"]   # Adjust these to avoid conflicts
    database_subnet_cidrs = ["10.0.120.0/24", "10.0.121.0/24"]   # Adjust these to avoid conflicts
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allow_internet_access" {
  description = "Allow direct internet access or force through FortiGate tunnel"
  type        = bool
  default     = false  # Force all traffic through FortiGate tunnel
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "Initial storage allocation for RDS (GB)"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Maximum storage allocation for RDS (GB)"
  type        = number
  default     = 500
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "cortex_emr"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_backup_retention_period" {
  description = "Database backup retention period (days)"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Database backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# Application Server Configuration
variable "app_instance_type" {
  description = "Instance type for application servers"
  type        = string
  default     = "t3.large"
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

# Optional Components
variable "create_bastion" {
  description = "Create bastion host for management access"
  type        = bool
  default     = true
}