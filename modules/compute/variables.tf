# modules/compute/variables.tf

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "application_security_group_id" {
  description = "Security group ID for application servers"
  type        = string
}

variable "integration_security_group_id" {
  description = "Security group ID for integration server"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group ID for bastion host"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "windows_ami_id" {
  description = "Windows AMI ID"
  type        = string
}

variable "app_instance_type" {
  description = "Instance type for application servers"
  type        = string
  default     = "m5.xlarge"
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

variable "integration_instance_type" {
  description = "Instance type for integration server"
  type        = string
  default     = "m5.large"
}

variable "scale_up_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 70
}

variable "scale_down_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 30
}

variable "ssl_certificate_arn" {
  description = "ARN of the SSL certificate"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Active Directory domain name"
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS name for AD domain"
  type        = string
}

variable "domain_admin_user" {
  description = "Domain admin username"
  type        = string
}

variable "domain_admin_password" {
  description = "Domain admin password"
  type        = string
  sensitive   = true
}

variable "fsx_dns_name" {
  description = "FSx file system DNS name"
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "RDS database endpoint"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "cortex_emr"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/compute/outputs.tf

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "load_balancer_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  value       = aws_lb.main.arn_suffix
}

output "auto_scaling_group_names" {
  description = "Names of the Auto Scaling Groups"
  value       = [aws_autoscaling_group.app.name]
}

output "integration_server_id" {
  description = "Instance ID of the integration server"
  value       = aws_instance.integration.id
}

output "integration_server_private_ip" {
  description = "Private IP of the integration server"
  value       = aws_instance.integration.private_ip
}

output "bastion_host_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "bastion_host_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "integration_nlb_dns_name" {
  description = "DNS name of the Integration Network Load Balancer"
  value       = aws_lb.integration.dns_name
}

output "target_group_arn" {
  description = "ARN of the application target group"
  value       = aws_lb_target_group.app.arn
}