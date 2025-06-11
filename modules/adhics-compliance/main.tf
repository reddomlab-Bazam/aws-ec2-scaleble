# modules/adhics-compliance/main.tf
# Abu Dhabi Health Information and Cyber Security Standards (ADHICS) Compliance Module

# AWS Config for ADHICS compliance monitoring
resource "aws_config_configuration_recorder" "adhics_recorder" {
  name     = "${var.name_prefix}-adhics-config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_config_delivery_channel.adhics_delivery_channel]
}

resource "aws_config_delivery_channel" "adhics_delivery_channel" {
  name           = "${var.name_prefix}-adhics-config-delivery"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
  
  snapshot_delivery_properties {
    delivery_frequency = "Daily"
  }
}

# S3 bucket for AWS Config
resource "aws_s3_bucket" "config_bucket" {
  bucket        = "${var.name_prefix}-adhics-config-${random_string.bucket_suffix.result}"
  force_destroy = false
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-adhics-config-bucket"
    Purpose = "ADHICS-Compliance"
  })
}

resource "aws_s3_bucket_versioning" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket" {
  bucket = aws_s3_bucket.config_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for AWS Config
resource "aws_iam_role" "config_role" {
  name = "${var.name_prefix}-adhics-config-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_policy" {
  name = "${var.name_prefix}-config-s3-policy"
  role = aws_iam_role.config_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.config_bucket.arn
      },
      {
        Effect = "Allow"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ADHICS Required Config Rules
resource "aws_config_config_rule" "root_access_key_check" {
  name = "${var.name_prefix}-root-access-key-check"
  
  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCESS_KEY_CHECK"
  }
  
  depends_on = [aws_config_configuration_recorder.adhics_recorder]
  
  tags = merge(var.tags, {
    ADHICSControl = "IAM-01"
  })
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${var.name_prefix}-encrypted-volumes"
  
  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
  
  depends_on = [aws_config_configuration_recorder.adhics_recorder]
  
  tags = merge(var.tags, {
    ADHICSControl = "CRYPTO-01"
  })
}

resource "aws_config_config_rule" "rds_encrypted" {
  name = "${var.name_prefix}-rds-storage-encrypted"
  
  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }
  
  depends_on = [aws_config_configuration_recorder.adhics_recorder]
  
  tags = merge(var.tags, {
    ADHICSControl = "CRYPTO-02"
  })
}

resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  name = "${var.name_prefix}-s3-bucket-public-access-prohibited"
  
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }
  
  depends_on = [aws_config_configuration_recorder.adhics_recorder]
  
  tags = merge(var.tags, {
    ADHICSControl = "DATA-01"
  })
}

resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  name = "${var.name_prefix}-vpc-flow-logs-enabled"
  
  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }
  
  input_parameters = jsonencode({
    trafficType = "ALL"
  })
  
  depends_on = [aws_config_configuration_recorder.adhics_recorder]
  
  tags = merge(var.tags, {
    ADHICSControl = "NETWORK-01"
  })
}

# GuardDuty for threat detection (ADHICS requirement)
resource "aws_guardduty_detector" "main" {
  enable = true
  
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-guardduty"
    ADHICSControl = "MONITOR-01"
  })
}

# Security Hub for centralized security findings
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
}

# Enable AWS Security Hub standards
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standard/aws-foundational-security/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standard/cis-aws-foundations-benchmark/v/1.2.0"
  depends_on    = [aws_securityhub_account.main]
}

# CloudTrail for comprehensive audit logging (ADHICS requirement)
resource "aws_cloudtrail" "adhics_audit_trail" {
  name           = "${var.name_prefix}-adhics-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_bucket.bucket
  
  # Enable for all regions for comprehensive coverage
  is_multi_region_trail         = true
  include_global_service_events = true
  
  # Enable log file validation for integrity
  enable_log_file_validation = true
  
  # KMS encryption for logs
  kms_key_id = var.kms_key_id
  
  # Enable CloudWatch Logs integration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs_role.arn
  
  # Data events for S3 and Lambda (if used)
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/*"]
    }
  }
  
  # Insight selectors for anomaly detection
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-adhics-cloudtrail"
    ADHICSControl = "AUDIT-01"
  })
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket        = "${var.name_prefix}-adhics-cloudtrail-${random_string.bucket_suffix.result}"
  force_destroy = false
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-adhics-cloudtrail-bucket"
    ADHICSControl = "AUDIT-01"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail_bucket" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_bucket" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_bucket" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id
  
  rule {
    id     = "adhics_log_retention"
    status = "Enabled"
    
    # Keep logs for 7 years as per ADHICS requirements
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 2555  # 7 years
      storage_class = "DEEP_ARCHIVE"
    }
    
    expiration {
      days = 2555  # 7 years retention
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-adhics-audit-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl": "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-adhics-audit-trail"
          }
        }
      },
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_bucket.arn,
          "${aws_s3_bucket.cloudtrail_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.name_prefix}-adhics"
  retention_in_days = 2555  # 7 years for ADHICS compliance
  kms_key_id        = var.kms_key_id
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudtrail-logs"
    ADHICSControl = "AUDIT-01"
  })
}

# IAM Role for CloudTrail CloudWatch Logs
resource "aws_iam_role" "cloudtrail_logs_role" {
  name = "${var.name_prefix}-cloudtrail-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_logs_policy" {
  name = "${var.name_prefix}-cloudtrail-logs-policy"
  role = aws_iam_role.cloudtrail_logs_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# WAF for web application protection (ADHICS requirement)
resource "aws_wafv2_web_acl" "adhics_waf" {
  name  = "${var.name_prefix}-adhics-waf"
  scope = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  # AWS Managed Rules for common threats
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "CommonRuleSetMetric"
      sampled_requests_enabled    = true
    }
  }
  
  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 2
    
    action {
      block {}
    }
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "RateLimitRuleMetric"
      sampled_requests_enabled    = true
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-adhics-waf"
    ADHICSControl = "NETWORK-02"
  })
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "${var.name_prefix}ADHICSWAFMetric"
    sampled_requests_enabled    = true
  }
}

# CloudWatch Log Group for WAF
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "/aws/waf/${var.name_prefix}-adhics"
  retention_in_days = 365
  kms_key_id        = var.kms_key_id
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-waf-logs"
    ADHICSControl = "NETWORK-02"
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "adhics_waf_logging" {
  resource_arn            = aws_wafv2_web_acl.adhics_waf.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
  
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# ADHICS Compliance Dashboard
resource "aws_cloudwatch_dashboard" "adhics_compliance" {
  dashboard_name = "${var.name_prefix}-adhics-compliance"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/Config", "ComplianceByConfigRule"],
            ["AWS/GuardDuty", "FindingCount"],
            ["AWS/SecurityHub", "Findings"],
            ["AWS/WAF", "AllowedRequests", "WebACL", aws_wafv2_web_acl.adhics_waf.name],
            [".", "BlockedRequests", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "ADHICS Compliance Metrics"
          period  = 300
        }
      }
    ]
  })
}

# Random string for unique naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}