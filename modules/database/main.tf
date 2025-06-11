# modules/database/main.tf

# Random password for database (use AWS Secrets Manager in production)
resource "random_password" "master_password" {
  length  = 16
  special = true
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.name_prefix}-db-master-password"
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-password"
  })
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password != "" ? var.master_password : random_password.master_password.result
  })
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-subnet-group"
  })
}

# RDS Parameter Group
resource "aws_db_parameter_group" "main" {
  family = "mysql8.0"
  name   = "${var.name_prefix}-db-params"
  
  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"
  }
  
  parameter {
    name  = "max_connections"
    value = "1000"
  }
  
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  
  parameter {
    name  = "long_query_time"
    value = "2"
  }
  
  parameter {
    name  = "general_log"
    value = "1"
  }
  
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-parameter-group"
  })
}

# RDS Option Group
resource "aws_db_option_group" "main" {
  name                     = "${var.name_prefix}-db-options"
  option_group_description = "Option group for ${var.name_prefix}"
  engine_name              = "mysql"
  major_engine_version     = "8.0"
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-option-group"
  })
}

# Enhanced Monitoring Role
resource "aws_iam_role" "enhanced_monitoring" {
  name = "${var.name_prefix}-rds-enhanced-monitoring"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-mysql"
  
  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = var.instance_class
  
  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = var.kms_key_id
  
  # Database configuration
  db_name  = var.db_name
  username = var.master_username
  password = var.master_password != "" ? var.master_password : random_password.master_password.result
  port     = 3306
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  
  # High Availability
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.availability_zone
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = false
  
  # Performance and monitoring
  parameter_group_name        = aws_db_parameter_group.main.name
  option_group_name          = aws_db_option_group.main.name
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  monitoring_interval        = 60
  monitoring_role_arn       = aws_iam_role.enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = ["error", "general", "slow_query"]
  
  # Security
  deletion_protection      = var.deletion_protection
  skip_final_snapshot     = !var.final_snapshot
  final_snapshot_identifier = var.final_snapshot ? "${var.name_prefix}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = true
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-mysql-database"
  })
  
  depends_on = [
    aws_db_subnet_group.main,
    aws_db_parameter_group.main,
    aws_db_option_group.main
  ]
}

# Read Replica for reporting (optional)
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0
  
  identifier = "${var.name_prefix}-mysql-replica"
  
  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.replica_instance_class
  
  # Override source settings if needed
  publicly_accessible = false
  auto_minor_version_upgrade = true
  
  # Performance Insights
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-mysql-read-replica"
    Type = "ReadReplica"
  })
}

# CloudWatch Log Groups for RDS logs
resource "aws_cloudwatch_log_group" "error" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/error"
  retention_in_days = 30
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "general" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/general"
  retention_in_days = 7
  
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "slow_query" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/slowquery"
  retention_in_days = 30
  
  tags = var.tags
}

# Automated snapshots using Lambda (optional enhancement)
resource "aws_db_snapshot" "manual_snapshot" {
  count = var.create_manual_snapshot ? 1 : 0
  
  db_instance_identifier = aws_db_instance.main.identifier
  db_snapshot_identifier = "${var.name_prefix}-manual-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-manual-snapshot"
    Type = "Manual"
  })
}

# CloudWatch Alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.name_prefix}-rds-connection-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds connection count"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "10000000000" # 10GB in bytes
  alarm_description   = "This metric monitors rds free storage space"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
  
  tags = var.tags
}

# Database subnet group output for reference
output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}