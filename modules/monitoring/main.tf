# modules/monitoring/main.tf

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alerts-topic"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-dashboard"
  
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
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.load_balancer_arn_suffix],
            [".", "RequestCount", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Application Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = flatten([
            for asg_name in var.auto_scaling_group_names : [
              ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", asg_name],
              [".", "GroupInServiceInstances", ".", asg_name],
              [".", "GroupTotalInstances", ".", asg_name]
            ]
          ])
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Auto Scaling Group Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeStorageSpace", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "RDS Database Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/ec2/cortex-emr/tomcat' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Application Logs"
          view    = "table"
        }
      }
    ]
  })
}

# Application Load Balancer Alarms
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.name_prefix}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors ALB response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors ALB 5XX errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts" {
  alarm_name          = "${var.name_prefix}-alb-healthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors healthy hosts behind ALB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  
  tags = var.tags
}

# Auto Scaling Group Alarms
resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  count = length(var.auto_scaling_group_names)
  
  alarm_name          = "${var.name_prefix}-asg-${count.index}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 cpu utilization for ${var.auto_scaling_group_names[count.index]}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    AutoScalingGroupName = var.auto_scaling_group_names[count.index]
  }
  
  tags = var.tags
}

# Custom Application Metrics
resource "aws_cloudwatch_log_metric_filter" "application_errors" {
  name           = "${var.name_prefix}-application-errors"
  log_group_name = "/aws/ec2/cortex-emr/tomcat"
  pattern        = "[timestamp, request_id, ERROR, ...]"
  
  metric_transformation {
    name      = "ApplicationErrors"
    namespace = "CortexEMR/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "${var.name_prefix}-application-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApplicationErrors"
  namespace           = "CortexEMR/Application"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors application errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = var.tags
}

# Database Connection Pool Monitoring
resource "aws_cloudwatch_log_metric_filter" "db_connection_errors" {
  name           = "${var.name_prefix}-db-connection-errors"
  log_group_name = "/aws/ec2/cortex-emr/tomcat"
  pattern        = "[timestamp, request_id, level, logger, message=\"*Connection*refused*\" || message=\"*Connection*timeout*\"]"
  
  metric_transformation {
    name      = "DatabaseConnectionErrors"
    namespace = "CortexEMR/Database"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connection_errors" {
  alarm_name          = "${var.name_prefix}-db-connection-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnectionErrors"
  namespace           = "CortexEMR/Database"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors database connection errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = var.tags
}

# Disk Space Monitoring
resource "aws_cloudwatch_metric_alarm" "disk_space_utilization" {
  count = length(var.auto_scaling_group_names)
  
  alarm_name          = "${var.name_prefix}-disk-space-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors disk space utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    AutoScalingGroupName = var.auto_scaling_group_names[count.index]
    device               = "C:"
    fstype               = "NTFS"
  }
  
  tags = var.tags
}

# Memory Utilization Monitoring
resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  count = length(var.auto_scaling_group_names)
  
  alarm_name          = "${var.name_prefix}-memory-utilization-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This metric monitors memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    AutoScalingGroupName = var.auto_scaling_group_names[count.index]
  }
  
  tags = var.tags
}

# Integration Server Health Check
resource "aws_cloudwatch_log_metric_filter" "integration_health" {
  name           = "${var.name_prefix}-integration-health"
  log_group_name = "/aws/ec2/cortex-emr/integration"
  pattern        = "[timestamp, level=\"ERROR\", component=\"*Integration*\", ...]"
  
  metric_transformation {
    name      = "IntegrationErrors"
    namespace = "CortexEMR/Integration"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "integration_health" {
  alarm_name          = "${var.name_prefix}-integration-health"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IntegrationErrors"
  namespace           = "CortexEMR/Integration"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors integration service health"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = var.tags
}

# Composite Alarm for Overall System Health
resource "aws_cloudwatch_composite_alarm" "system_health" {
  alarm_name          = "${var.name_prefix}-system-health"
  alarm_description   = "Overall system health composite alarm"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.alb_healthy_hosts.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.application_errors.alarm_name})"
  
  tags = var.tags
}

# CloudWatch Insights Queries for troubleshooting
resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.name_prefix}-error-analysis"
  
  log_group_names = [
    "/aws/ec2/cortex-emr/tomcat",
    "/aws/ec2/cortex-emr/system",
    "/aws/ec2/cortex-emr/integration"
  ]
  
  query_string = <<EOT
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
EOT
}

resource "aws_cloudwatch_query_definition" "performance_analysis" {
  name = "${var.name_prefix}-performance-analysis"
  
  log_group_names = [
    "/aws/ec2/cortex-emr/tomcat"
  ]
  
  query_string = <<EOT
fields @timestamp, @message
| filter @message like /response_time/
| stats avg(response_time) by bin(5m)
| sort @timestamp desc
EOT
}

# EventBridge Rules for automated responses
resource "aws_cloudwatch_event_rule" "auto_scaling_events" {
  name        = "${var.name_prefix}-auto-scaling-events"
  description = "Capture Auto Scaling events"
  
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance Launch Successful", "EC2 Instance Terminate Successful"]
    detail = {
      AutoScalingGroupName = var.auto_scaling_group_names
    }
  })
  
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.auto_scaling_events.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alerts_policy" {
  arn = aws_sns_topic.alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}