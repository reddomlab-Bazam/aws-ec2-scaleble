# modules/compute/auto-scaling-enhanced.tf
# Enhanced Auto-Scaling with Multiple Strategies

# Mixed Instance Types Auto Scaling Group for Intelligent Scaling
resource "aws_autoscaling_group" "app_mixed_instance" {
  name                = "${var.name_prefix}-app-mixed-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.app_min_size
  max_size         = var.app_max_size
  desired_capacity = var.app_desired_capacity
  
  # Enable instance refresh for zero-downtime deployments
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 300
      checkpoint_delay      = 600
      checkpoint_percentages = [20, 50, 100]
    }
    triggers = ["tag"]
  }
  
  # Mixed instance policy for intelligent scaling
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app_mixed.id
        version           = "$Latest"
      }
      
      # Override with different instance types for progressive scaling
      override {
        instance_type     = "m5.large"      # 2 vCPU, 8 GB
        weighted_capacity = "1"
      }
      
      override {
        instance_type     = "m5.xlarge"     # 4 vCPU, 16 GB
        weighted_capacity = "2"
      }
      
      override {
        instance_type     = "m5.2xlarge"    # 8 vCPU, 32 GB
        weighted_capacity = "4"
      }
      
      override {
        instance_type     = "m5.4xlarge"    # 16 vCPU, 64 GB
        weighted_capacity = "8"
      }
    }
    
    instances_distribution {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 100
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }
  
  # Predictive scaling for proactive resource management
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances"
  ]
  
  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app-mixed-asg"
    propagate_at_launch = false
  }
  
  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Enhanced Launch Template with Multiple Instance Type Support
resource "aws_launch_template" "app_mixed" {
  name_prefix   = "${var.name_prefix}-app-mixed-"
  image_id      = var.windows_ami_id
  
  vpc_security_group_ids = [var.application_security_group_id]
  
  iam_instance_profile {
    name = var.instance_profile_name
  }
  
  user_data = local.app_user_data
  
  # Dynamic EBS configuration based on instance type
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 200
      volume_type = "gp3"
      iops        = 3000
      throughput  = 125
      encrypted   = true
      kms_key_id  = var.kms_key_id
    }
  }
  
  monitoring {
    enabled = true
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-app-server-mixed"
      Type = "Application"
      ScalingType = "Mixed"
    })
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Target Tracking Scaling Policies for Responsive Scaling
resource "aws_autoscaling_policy" "target_tracking_cpu" {
  name                   = "${var.name_prefix}-target-tracking-cpu"
  autoscaling_group_name = aws_autoscaling_group.app_mixed_instance.name
  policy_type           = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
    scale_out_cooldown = 300
    scale_in_cooldown  = 300
  }
}

resource "aws_autoscaling_policy" "target_tracking_memory" {
  name                   = "${var.name_prefix}-target-tracking-memory"
  autoscaling_group_name = aws_autoscaling_group.app_mixed_instance.name
  policy_type           = "TargetTrackingScaling"
  
  target_tracking_configuration {
    customized_metric_specification {
      metric_name = "MemoryUtilization"
      namespace   = "CWAgent"
      statistic   = "Average"
      
      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.app_mixed_instance.name
      }
    }
    target_value = 80.0
    scale_out_cooldown = 300
    scale_in_cooldown  = 600
  }
}

# Predictive Scaling Policy
resource "aws_autoscaling_policy" "predictive_scaling" {
  name                   = "${var.name_prefix}-predictive-scaling"
  autoscaling_group_name = aws_autoscaling_group.app_mixed_instance.name
  policy_type           = "PredictiveScaling"
  
  predictive_scaling_configuration {
    metric_specification {
      target_value = 70
      predefined_metric_pair_specification {
        predefined_metric_type = "ASGCPUUtilization"
      }
    }
    mode                         = "ForecastAndScale"
    scheduling_buffer_time       = 300
    max_capacity_breach_behavior = "HonorMaxCapacity"
    max_capacity_buffer          = 10
  }
}

# Application Load Balancer with Session Stickiness
resource "aws_lb_target_group" "app_sticky" {
  name     = "${var.name_prefix}-app-sticky-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  # Session stickiness to prevent session interruption
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  # Connection draining for graceful instance removal
  deregistration_delay = 300
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-sticky-target-group"
  })
}

# Enhanced CloudWatch Alarms for Multi-Metric Scaling
resource "aws_cloudwatch_metric_alarm" "cpu_memory_composite" {
  alarm_name          = "${var.name_prefix}-cpu-memory-composite"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "1"
  alarm_description   = "Composite alarm for CPU and Memory utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up_large.arn]
  
  composite_alarm {
    alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.cpu_high.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.memory_high.alarm_name})"
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.name_prefix}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "Memory utilization is too high"
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_mixed_instance.name
  }
  
  tags = var.tags
}

# Step Scaling Policies for Aggressive Scaling
resource "aws_autoscaling_policy" "scale_up_large" {
  name                   = "${var.name_prefix}-scale-up-large"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_mixed_instance.name
  
  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 50
  }
  
  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 50
    metric_interval_upper_bound = 85
  }
  
  step_adjustment {
    scaling_adjustment          = 3
    metric_interval_lower_bound = 85
  }
}

# Warm Pool for Faster Scaling
resource "aws_autoscaling_warm_pool" "app_warm_pool" {
  autoscaling_group_name = aws_autoscaling_group.app_mixed_instance.name
  pool_state            = "Stopped"
  min_size              = 1
  max_group_prepared_capacity = 5
  
  instance_reuse_policy {
    reuse_on_scale_in = true
  }
}

# RDS Read Replica for Database Scaling
resource "aws_db_instance" "read_replica_scaling" {
  count = var.enable_read_replica ? 1 : 0
  
  identifier = "${var.name_prefix}-mysql-read-replica"
  
  replicate_source_db = var.primary_db_identifier
  instance_class      = var.read_replica_instance_class
  
  # Auto scaling storage
  allocated_storage     = 100
  max_allocated_storage = 1000
  
  # Performance Insights
  performance_insights_enabled = true
  monitoring_interval = 60
  
  # Multi-AZ for read replica high availability
  multi_az = false
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-read-replica"
    Type = "ReadReplica"
    Purpose = "Scaling"
  })
}

# Application-Level Session Management
resource "aws_elasticache_replication_group" "session_store" {
  count = var.enable_session_store ? 1 : 0
  
  replication_group_id         = "${var.name_prefix}-sessions"
  description                  = "Redis cluster for session management"
  
  port               = 6379
  parameter_group_name = "default.redis7"
  node_type          = "cache.t3.micro"
  num_cache_clusters = 2
  
  # Multi-AZ for high availability
  multi_az_enabled = true
  
  # Automatic failover
  automatic_failover_enabled = true
  
  # Backup configuration
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  
  # Security
  subnet_group_name  = aws_elasticache_subnet_group.session_store[0].name
  security_group_ids = [aws_security_group.redis[0].id]
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-session-store"
    Purpose = "SessionManagement"
  })
}

resource "aws_elasticache_subnet_group" "session_store" {
  count = var.enable_session_store ? 1 : 0
  
  name       = "${var.name_prefix}-session-store-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  count = var.enable_session_store ? 1 : 0
  
  name_prefix = "${var.name_prefix}-redis-"
  vpc_id      = var.vpc_id
  description = "Security group for Redis session store"
  
  ingress {
    description     = "Redis from application servers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.application_security_group_id]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Custom CloudWatch Metrics for Application Performance
resource "aws_cloudwatch_log_metric_filter" "response_time" {
  name           = "${var.name_prefix}-response-time"
  log_group_name = "/aws/ec2/cortex-emr/tomcat"
  pattern        = "[timestamp, request_id, method, url, response_time_ms, status_code]"
  
  metric_transformation {
    name      = "AverageResponseTime"
    namespace = "CortexEMR/Performance"
    value     = "$response_time_ms"
    unit      = "Milliseconds"
  }
}

resource "aws_cloudwatch_metric_alarm" "response_time_alarm" {
  alarm_name          = "${var.name_prefix}-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AverageResponseTime"
  namespace           = "CortexEMR/Performance"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000"  # 2 seconds
  alarm_description   = "Application response time is too high"
  alarm_actions       = [aws_autoscaling_policy.scale_up_large.arn]
  
  tags = var.tags
}

# Database Connection Pool Scaling
resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  alarm_name          = "${var.name_prefix}-db-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"  # 80% of max connections
  alarm_description   = "Database connections are high, may need read replica"
  
  dimensions = {
    DBInstanceIdentifier = var.primary_db_identifier
  }
  
  tags = var.tags
}

# Auto Scaling Notifications
resource "aws_autoscaling_notification" "scaling_notifications" {
  group_names = [aws_autoscaling_group.app_mixed_instance.name]
  
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  
  topic_arn = var.notification_topic_arn
}