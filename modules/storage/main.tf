# modules/storage/main.tf

# Amazon FSx for Windows File Server
resource "aws_fsx_windows_file_system" "main" {
  storage_capacity    = var.storage_capacity
  subnet_ids          = [var.subnet_ids[0]] # FSx requires a single subnet
  throughput_capacity = var.throughput_capacity
  
  # Active Directory configuration
  active_directory_id = var.active_directory_id
  
  # Security
  security_group_ids = var.security_group_ids
  
  # Storage configuration
  storage_type                    = "SSD"
  deployment_type                = var.deployment_type
  preferred_subnet_id            = var.subnet_ids[0]
  automatic_backup_retention_days = var.backup_retention_days
  
  # Backup configuration
  daily_automatic_backup_start_time = var.backup_start_time
  weekly_maintenance_start_time     = var.maintenance_start_time
  copy_tags_to_backups             = true
  
  # Performance
  aliases = var.aliases
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-fsx-windows"
    Type = "FileServer"
  })
}

# S3 Bucket for additional file storage and backups
resource "aws_s3_bucket" "file_storage" {
  bucket        = "${var.name_prefix}-file-storage-${random_string.bucket_suffix.result}"
  force_destroy = var.force_destroy_bucket
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-file-storage"
    Type = "Storage"
  })
}

resource "aws_s3_bucket_versioning" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  
  rule {
    id     = "file_lifecycle"
    status = "Enabled"
    
    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    # Transition to Deep Archive after 365 days
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
    
    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    
    # Clean up old versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    
    # Transition old versions to IA after 30 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
  }
}

# S3 Bucket notification for file uploads (optional)
resource "aws_s3_bucket_notification" "file_storage_notification" {
  count  = var.enable_s3_notifications ? 1 : 0
  bucket = aws_s3_bucket.file_storage.id
  
  cloudwatch_configuration {
    cloudwatch_configuration_id = "file-upload-events"
    events                      = ["s3:ObjectCreated:*"]
  }
}

# CloudWatch Log Group for FSx performance logs
resource "aws_cloudwatch_log_group" "fsx_performance" {
  name              = "/aws/fsx/performance/${var.name_prefix}"
  retention_in_days = 30
  
  tags = var.tags
}

# CloudWatch Alarms for FSx monitoring
resource "aws_cloudwatch_metric_alarm" "fsx_storage_utilization" {
  alarm_name          = "${var.name_prefix}-fsx-storage-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StorageUtilization"
  namespace           = "AWS/FSx"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors FSx storage utilization"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    FileSystemId = aws_fsx_windows_file_system.main.id
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "fsx_throughput_utilization" {
  alarm_name          = "${var.name_prefix}-fsx-throughput-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThroughputUtilization"
  namespace           = "AWS/FSx"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors FSx throughput utilization"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    FileSystemId = aws_fsx_windows_file_system.main.id
  }
  
  tags = var.tags
}

# FSx Data Repository Task for S3 integration (optional)
resource "aws_fsx_data_repository_association" "s3_integration" {
  count = var.enable_s3_integration ? 1 : 0
  
  file_system_id       = aws_fsx_windows_file_system.main.id
  data_repository_path = "s3://${aws_s3_bucket.file_storage.bucket}"
  file_system_path     = "/s3-backup"
  
  s3 {
    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
    
    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-fsx-s3-integration"
  })
}

# Lambda function for automated file processing (optional)
resource "aws_lambda_function" "file_processor" {
  count = var.enable_file_processing ? 1 : 0
  
  filename         = "${path.module}/lambda/file_processor.zip"
  function_name    = "${var.name_prefix}-file-processor"
  role            = aws_iam_role.lambda_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  
  environment {
    variables = {
      FSX_DNS_NAME = aws_fsx_windows_file_system.main.dns_name
      S3_BUCKET    = aws_s3_bucket.file_storage.bucket
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-file-processor"
  })
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  count = var.enable_file_processing ? 1 : 0
  
  name = "${var.name_prefix}-lambda-file-processor"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# IAM Policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  count = var.enable_file_processing ? 1 : 0
  
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.file_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "fsx:DescribeFileSystems",
          "fsx:DescribeBackups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach basic execution role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.enable_file_processing ? 1 : 0
  
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Backup schedule using EventBridge (optional)
resource "aws_cloudwatch_event_rule" "backup_schedule" {
  count = var.enable_automated_backups ? 1 : 0
  
  name                = "${var.name_prefix}-fsx-backup-schedule"
  description         = "Automated backup schedule for FSx"
  schedule_expression = var.backup_schedule_expression
  
  tags = var.tags
}

# EventBridge target for backup Lambda
resource "aws_cloudwatch_event_target" "backup_target" {
  count = var.enable_automated_backups ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.backup_schedule[0].name
  target_id = "BackupTarget"
  arn       = aws_lambda_function.file_processor[0].arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_automated_backups ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_schedule[0].arn
}