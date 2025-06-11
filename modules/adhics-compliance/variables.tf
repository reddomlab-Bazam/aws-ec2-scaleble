# modules/adhics-compliance/variables.tf

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "load_balancer_arn" {
  description = "Application Load Balancer ARN for WAF association"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for compliance monitoring"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/adhics-compliance/outputs.tf

output "config_recorder_name" {
  description = "Name of the AWS Config recorder"
  value       = aws_config_configuration_recorder.adhics_recorder.name
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "security_hub_arn" {
  description = "Security Hub ARN"
  value       = aws_securityhub_account.main.arn
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN for ADHICS audit logging"
  value       = aws_cloudtrail.adhics_audit_trail.arn
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.adhics_waf.arn
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.adhics_waf.id
}

output "compliance_dashboard_url" {
  description = "URL to the ADHICS compliance dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.adhics_compliance.dashboard_name}"
}

output "config_bucket_name" {
  description = "AWS Config S3 bucket name"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail S3 bucket name"
  value       = aws_s3_bucket.cloudtrail_bucket.bucket
}

output "adhics_compliance_status" {
  description = "ADHICS compliance components status"
  value = {
    config_enabled      = aws_config_configuration_recorder.adhics_recorder.name != "" ? "Enabled" : "Disabled"
    guardduty_enabled   = aws_guardduty_detector.main.enable ? "Enabled" : "Disabled"
    security_hub_enabled = "Enabled"
    cloudtrail_enabled  = "Enabled"
    waf_enabled        = "Enabled"
    encryption_enabled = "Enabled"
    audit_logging      = "Enabled"
    data_residency     = "UAE (me-central-1)"
  }
}