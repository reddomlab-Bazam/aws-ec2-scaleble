# modules/monitoring/variables.tf

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
}

variable "auto_scaling_group_names" {
  description = "List of Auto Scaling Group names to monitor"
  type        = list(string)
  default     = []
}

variable "load_balancer_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "cpu_threshold_high" {
  description = "CPU utilization threshold for high alarm"
  type        = number
  default     = 80
}

variable "memory_threshold_high" {
  description = "Memory utilization threshold for high alarm"
  type        = number
  default     = 90
}

variable "disk_threshold_high" {
  description = "Disk utilization threshold for high alarm"
  type        = number
  default     = 85
}

variable "response_time_threshold" {
  description = "Response time threshold in seconds"
  type        = number
  default     = 5
}

variable "error_threshold" {
  description = "Error count threshold"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/monitoring/outputs.tf

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "composite_alarm_arn" {
  description = "ARN of the composite alarm for system health"
  value       = aws_cloudwatch_composite_alarm.system_health.arn
}

output "log_group_names" {
  description = "Names of CloudWatch log groups"
  value = [
    "/aws/ec2/cortex-emr/tomcat",
    "/aws/ec2/cortex-emr/system",
    "/aws/ec2/cortex-emr/integration"
  ]
}

output "cloudwatch_query_definitions" {
  description = "CloudWatch Insights query definitions"
  value = {
    error_analysis       = aws_cloudwatch_query_definition.error_analysis.name
    performance_analysis = aws_cloudwatch_query_definition.performance_analysis.name
  }
}