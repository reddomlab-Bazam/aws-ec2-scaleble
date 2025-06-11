# modules/storage/variables.tf

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for FSx deployment"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for FSx"
  type        = list(string)
}

variable "active_directory_id" {
  description = "Active Directory ID for FSx integration"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "storage_capacity" {
  description = "Storage capacity for FSx in GB"
  type        = number
  default     = 3072 # 3 TB
}

variable "throughput_capacity" {
  description = "Throughput capacity for FSx in MB/s"
  type        = number
  default     = 34
}

variable "deployment_type" {
  description = "FSx deployment type"
  type        = string
  default     = "MULTI_AZ_1"
  
  validation {
    condition = contains(["SINGLE_AZ_1", "SINGLE_AZ_2", "MULTI_AZ_1"], var.deployment_type)
    error_message = "Deployment type must be SINGLE_AZ_1, SINGLE_AZ_2, or MULTI_AZ_1."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain automatic backups"
  type        = number
  default     = 30
}

variable "backup_start_time" {
  description = "Time of day for automatic backups (HH:MM format)"
  type        = string
  default     = "02:00"
}

variable "maintenance_start_time" {
  description = "Time of week for maintenance window (d:HH:MM format)"
  type        = string
  default     = "1:02:00" # Sunday at 2 AM
}

variable "aliases" {
  description = "DNS aliases for FSx file system"
  type        = list(string)
  default     = []
}

variable "force_destroy_bucket" {
  description = "Force destroy S3 bucket even if not empty"
  type        = bool
  default     = false
}

variable "enable_s3_notifications" {
  description = "Enable S3 bucket notifications"
  type        = bool
  default     = false
}

variable "enable_s3_integration" {
  description = "Enable FSx S3 data repository integration"
  type        = bool
  default     = false
}

variable "enable_file_processing" {
  description = "Enable Lambda function for file processing"
  type        = bool
  default     = false
}

variable "enable_automated_backups" {
  description = "Enable automated backup scheduling"
  type        = bool
  default     = false
}

variable "backup_schedule_expression" {
  description = "CloudWatch Events schedule expression for backups"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/storage/outputs.tf

output "fsx_id" {
  description = "FSx file system ID"
  value       = aws_fsx_windows_file_system.main.id
}

output "fsx_arn" {
  description = "FSx file system ARN"
  value       = aws_fsx_windows_file_system.main.arn
}

output "fsx_dns_name" {
  description = "FSx file system DNS name"
  value       = aws_fsx_windows_file_system.main.dns_name
}

output "fsx_network_interface_ids" {
  description = "FSx file system network interface IDs"
  value       = aws_fsx_windows_file_system.main.network_interface_ids
}

output "fsx_preferred_file_server_ip" {
  description = "FSx preferred file server IP address"
  value       = aws_fsx_windows_file_system.main.preferred_file_server_ip
}

output "fsx_vpc_id" {
  description = "VPC ID where FSx is deployed"
  value       = aws_fsx_windows_file_system.main.vpc_id
}

output "s3_bucket_name" {
  description = "Name of the S3 storage bucket"
  value       = aws_s3_bucket.file_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 storage bucket"
  value       = aws_s3_bucket.file_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_storage.bucket_regional_domain_name
}

output "lambda_function_arn" {
  description = "ARN of the file processing Lambda function"
  value       = var.enable_file_processing ? aws_lambda_function.file_processor[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for FSx"
  value       = aws_cloudwatch_log_group.fsx_performance.name
}