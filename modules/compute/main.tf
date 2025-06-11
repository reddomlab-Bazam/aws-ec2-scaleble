# modules/compute/main.tf

# User Data Script for Application Servers
locals {
  app_user_data = base64encode(templatefile("${path.module}/user-data/app-server-userdata.ps1", {
    domain_name           = var.domain_name
    domain_netbios_name   = var.domain_netbios_name
    domain_admin_user     = var.domain_admin_user
    domain_admin_password = var.domain_admin_password
    fsx_dns_name          = var.fsx_dns_name
    db_endpoint           = var.db_endpoint
    db_name               = var.db_name
  }))
  
  integration_user_data = base64encode(templatefile("${path.module}/user-data/integration-server-userdata.ps1", {
    domain_name           = var.domain_name
    domain_netbios_name   = var.domain_netbios_name
    domain_admin_user     = var.domain_admin_user
    domain_admin_password = var.domain_admin_password
  }))
  
  bastion_user_data = base64encode(templatefile("${path.module}/user-data/bastion-userdata.ps1", {
    domain_name           = var.domain_name
    domain_netbios_name   = var.domain_netbios_name
    domain_admin_user     = var.domain_admin_user
    domain_admin_password = var.domain_admin_password
  }))
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection = false
  
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-access-logs"
    enabled = true
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb"
  })
}

# S3 Bucket for ALB Access Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.name_prefix}-alb-logs-${random_string.bucket_suffix.result}"
  force_destroy = true
  
  tags = var.tags
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  
  rule {
    id     = "log_retention"
    status = "Enabled"
    
    expiration {
      days = 90
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

# Random string for bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Target Group for Application Servers
resource "aws_lb_target_group" "app" {
  name     = "${var.name_prefix}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
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
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-target-group"
  })
}

# ALB Listener for HTTPS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  
  tags = var.tags
}

# ALB Listener for HTTP (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
  
  tags = var.tags
}

# Launch Template for Application Servers
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name_prefix}-app-"
  image_id      = var.windows_ami_id
  instance_type = var.app_instance_type
  
  vpc_security_group_ids = [var.application_security_group_id]
  
  iam_instance_profile {
    name = var.instance_profile_name
  }
  
  user_data = local.app_user_data
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 200
      volume_type = "gp3"
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
      Name = "${var.name_prefix}-app-server"
      Type = "Application"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-app-server-volume"
    })
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-launch-template"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for Application Servers
resource "aws_autoscaling_group" "app" {
  name                = "${var.name_prefix}-app-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.app_min_size
  max_size         = var.app_max_size
  desired_capacity = var.app_desired_capacity
  
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  
  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app-asg"
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
  
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name_prefix}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name_prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.scale_up_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.scale_down_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  
  tags = var.tags
}

# Integration Server
resource "aws_instance" "integration" {
  ami                    = var.windows_ami_id
  instance_type          = var.integration_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.integration_security_group_id]
  iam_instance_profile   = var.instance_profile_name
  user_data              = local.integration_user_data
  
  root_block_device {
    volume_size = 300
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_id
  }
  
  monitoring = true
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-integration-server"
    Type = "Integration"
  })
}

# Network Load Balancer for Integration Server
resource "aws_lb" "integration" {
  name               = "${var.name_prefix}-integration-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids
  
  enable_deletion_protection = false
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-integration-nlb"
  })
}

# Target Group for Integration Server
resource "aws_lb_target_group" "integration" {
  name     = "${var.name_prefix}-integration-tg"
  port     = 8080
  protocol = "TCP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-integration-target-group"
  })
}

# Attach Integration Server to Target Group
resource "aws_lb_target_group_attachment" "integration" {
  target_group_arn = aws_lb_target_group.integration.arn
  target_id        = aws_instance.integration.id
  port             = 8080
}

# NLB Listener for Integration
resource "aws_lb_listener" "integration" {
  load_balancer_arn = aws_lb.integration.arn
  port              = "8080"
  protocol          = "TCP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.integration.arn
  }
  
  tags = var.tags
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami                         = var.windows_ami_id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_security_group_id]
  iam_instance_profile        = var.instance_profile_name
  user_data                   = local.bastion_user_data
  associate_public_ip_address = true
  
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_id
  }
  
  monitoring = true
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-host"
    Type = "Bastion"
  })
}

# Data sources
data "aws_elb_service_account" "main" {}