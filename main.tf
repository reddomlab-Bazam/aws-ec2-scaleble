# main.tf - Simplified Cortex EMR Infrastructure with Existing Infrastructure Integration

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Cortex-EMR"
      ManagedBy   = "Terraform"
      Compliance  = "ADHICS"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get existing VPC if specified
data "aws_vpc" "existing" {
  count = var.use_existing_infrastructure ? 1 : 0
  id    = var.existing_vpc_id
}

# Get existing VPN Gateway if specified
data "aws_vpn_gateway" "existing" {
  count = var.use_existing_infrastructure && var.existing_vpn_gateway_id != "" ? 1 : 0
  id    = var.existing_vpn_gateway_id
}

# Get existing Route 53 zone if specified
data "aws_route53_zone" "existing" {
  count   = var.use_existing_infrastructure && var.existing_route53_zone_id != "" ? 1 : 0
  zone_id = var.existing_route53_zone_id
}

# Local values
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  
  # Use existing VPC or create new one
  vpc_id = var.use_existing_infrastructure ? data.aws_vpc.existing[0].id : aws_vpc.main[0].id
  vpc_cidr = var.use_existing_infrastructure ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
  
  # Route 53 configuration
  route53_zone_id = var.use_existing_infrastructure && var.existing_route53_zone_id != "" ? data.aws_route53_zone.existing[0].zone_id : aws_route53_zone.main[0].zone_id
  domain_name = var.use_existing_infrastructure && var.existing_route53_domain != "" ? var.existing_route53_domain : "cortex-emr.local"
}

# VPC (only create if not using existing)
resource "aws_vpc" "main" {
  count = var.use_existing_infrastructure ? 0 : 1
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Internet Gateway (only create if not using existing and internet access allowed)
resource "aws_internet_gateway" "main" {
  count = var.use_existing_infrastructure ? 0 : (var.allow_internet_access ? 1 : 0)
  
  vpc_id = local.vpc_id
  
  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2
  
  vpc_id                  = local.vpc_id
  cidr_block              = var.subnet_planning.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = var.allow_internet_access
  
  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
    Tier = "LoadBalancer"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 2
  
  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_planning.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
  
  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
    Tier = "Application"
  }
}

# Database Subnets
resource "aws_subnet" "database" {
  count = 2
  
  vpc_id            = local.vpc_id
  cidr_block        = var.subnet_planning.database_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
  
  tags = {
    Name = "${local.name_prefix}-db-subnet-${count.index + 1}"
    Type = "Database"
    Tier = "Data"
  }
}

# NAT Gateway (only if internet access allowed and not using existing infrastructure)
resource "aws_eip" "nat" {
  count = var.use_existing_infrastructure ? 0 : (var.allow_internet_access ? 1 : 0)
  
  domain = "vpc"
  
  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.use_existing_infrastructure ? 0 : (var.allow_internet_access ? 1 : 0)
  
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  
  tags = {
    Name = "${local.name_prefix}-nat-gateway"
  }
  
  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  
  # Route to internet gateway if internet access allowed
  dynamic "route" {
    for_each = var.allow_internet_access && !var.use_existing_infrastructure ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.main[0].id
    }
  }
  
  # Route to existing VPN gateway for on-premises access
  dynamic "route" {
    for_each = var.use_existing_infrastructure && var.existing_vpn_gateway_id != "" ? [1] : []
    content {
      cidr_block = var.fortigate_tunnel_info.on_premises_cidr
      gateway_id = data.aws_vpn_gateway.existing[0].id
    }
  }
  
  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = local.vpc_id
  
  # Route to NAT gateway if internet access allowed
  dynamic "route" {
    for_each = var.allow_internet_access && !var.use_existing_infrastructure ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }
  
  # Route to existing VPN gateway for on-premises access (primary route)
  dynamic "route" {
    for_each = var.use_existing_infrastructure && var.existing_vpn_gateway_id != "" ? [1] : []
    content {
      cidr_block = var.fortigate_tunnel_info.on_premises_cidr
      gateway_id = data.aws_vpn_gateway.existing[0].id
    }
  }
  
  # If not allowing internet access, route all traffic through VPN
  dynamic "route" {
    for_each = !var.allow_internet_access && var.use_existing_infrastructure && var.existing_vpn_gateway_id != "" ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = data.aws_vpn_gateway.existing[0].id
    }
  }
  
  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = 2
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = 2
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = local.vpc_id
  description = "Security group for Application Load Balancer"
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.fortigate_tunnel_info.on_premises_cidr]
    description = "HTTP from on-premises via FortiGate"
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.fortigate_tunnel_info.on_premises_cidr]
    description = "HTTPS from on-premises via FortiGate"
  }
  
  # Allow internet access only if explicitly configured
  dynamic "ingress" {
    for_each = var.allow_internet_access ? [1] : []
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTP from internet"
    }
  }
  
  dynamic "ingress" {
    for_each = var.allow_internet_access ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS from internet"
    }
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${local.name_prefix}-alb-sg"
    Compliance = "ADHICS"
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name_prefix}-app-"
  vpc_id      = local.vpc_id
  description = "Security group for application servers"
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from load balancer"
  }
  
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.fortigate_tunnel_info.on_premises_cidr]
    description = "RDP from on-premises via FortiGate"
  }
  
  ingress {
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = [var.fortigate_tunnel_info.on_premises_cidr]
    description = "WinRM from on-premises via FortiGate"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${local.name_prefix}-app-sg"
    Compliance = "ADHICS"
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-db-"
  vpc_id      = local.vpc_id
  description = "Security group for RDS database"
  
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "MySQL from application servers"
  }
  
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.fortigate_tunnel_info.on_premises_cidr]
    description = "MySQL from on-premises via FortiGate (admin access)"
  }
  
  tags = {
    Name = "${local.name_prefix}-db-sg"
    Compliance = "ADHICS"
  }
}

# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id
  
  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
    Compliance = "ADHICS"
  }
}

# RDS Database with ADHICS compliance features
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"
  
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = var.db_instance_class
  
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true  # ADHICS requirement
  
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false  # ADHICS requirement
  
  multi_az = var.environment == "prod" ? true : false
  
  backup_retention_period = var.db_backup_retention_period
  backup_window          = var.db_backup_window
  maintenance_window     = var.db_maintenance_window
  copy_tags_to_snapshot  = true
  
  # ADHICS compliance features
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
  
  # Enable enhanced monitoring for ADHICS
  monitoring_interval = var.environment == "prod" ? 60 : 0
  monitoring_role_arn = var.environment == "prod" ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  
  # Enable performance insights for ADHICS
  performance_insights_enabled = var.environment == "prod" ? true : false
  
  tags = {
    Name = "${local.name_prefix}-mysql-database"
    Compliance = "ADHICS"
    DataClassification = "HealthcareData"
  }
}

# Enhanced monitoring role for RDS (ADHICS requirement for production)
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.environment == "prod" ? 1 : 0
  
  name = "${local.name_prefix}-rds-enhanced-monitoring"
  
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
  
  tags = {
    Compliance = "ADHICS"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.environment == "prod" ? 1 : 0
  
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = true  # Internal ALB for FortiGate access
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  
  enable_deletion_protection = var.environment == "prod" ? true : false
  
  # ADHICS compliance - access logging
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-access-logs"
    enabled = true
  }
  
  tags = {
    Name = "${local.name_prefix}-alb"
    Compliance = "ADHICS"
  }
}

# S3 bucket for ALB logs (ADHICS requirement)
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name_prefix}-alb-logs-${random_string.bucket_suffix.result}"
  force_destroy = var.environment != "prod"
  
  tags = {
    Name = "${local.name_prefix}-alb-logs"
    Compliance = "ADHICS"
    Purpose = "AuditLogging"
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

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  
  rule {
    id     = "adhics_log_retention"
    status = "Enabled"
    
    # ADHICS requires 7 years retention for audit logs
    expiration {
      days = var.environment == "prod" ? 2555 : 90  # 7 years for prod, 90 days for dev
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Route 53 Record (in existing hosted zone)
resource "aws_route53_record" "cortex_emr" {
  count = var.use_existing_infrastructure && var.existing_route53_zone_id != "" ? 1 : 0
  
  zone_id = local.route53_zone_id
  name    = "cortex-emr-${var.environment}.${local.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Route 53 zone (only create if not using existing)
resource "aws_route53_zone" "main" {
  count = var.use_existing_infrastructure ? 0 : 1
  
  name = "cortex-emr.local"
  
  vpc {
    vpc_id = local.vpc_id
  }
  
  tags = {
    Name = "${local.name_prefix}-private-zone"
    Compliance = "ADHICS"
  }
}

# Route 53 record for new zone
resource "aws_route53_record" "cortex_emr_new" {
  count = var.use_existing_infrastructure ? 0 : 1
  
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "cortex-emr-${var.environment}.cortex-emr.local"
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Target Group
resource "aws_lb_target_group" "app" {
  name     = "${local.name_prefix}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
  
  tags = {
    Name = "${local.name_prefix}-app-target-group"
  }
}

# ALB Listener
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# IAM Instance Profile
resource "aws_iam_role" "app_role" {
  name = "${local.name_prefix}-app-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app_role.name
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-"
  image_id      = data.aws_ami.windows_2022.id
  instance_type = var.app_instance_type
  
  vpc_security_group_ids = [aws_security_group.app.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }
  
  user_data = base64encode(templatefile("${path.module}/user-data.ps1", {
    db_endpoint = aws_db_instance.main.endpoint
    db_name     = aws_db_instance.main.db_name
    db_username = aws_db_instance.main.username
    db_password = var.db_password
  }))
  
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
    }
  }
  
  monitoring {
    enabled = true
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-app-server"
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-app-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
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
  
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app-asg"
    propagate_at_launch = false
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.name_prefix}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.name_prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# Bastion Host (optional - for management access)
resource "aws_instance" "bastion" {
  count = var.create_bastion ? 1 : 0
  
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  iam_instance_profile        = aws_iam_instance_profile.app_profile.name
  associate_public_ip_address = true
  
  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }
  
  tags = {
    Name = "${local.name_prefix}-bastion"
  }
}

resource "aws_security_group" "bastion" {
  count = var.create_bastion ? 1 : 0
  
  name_prefix = "${local.name_prefix}-bastion-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for bastion host"
  
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this to your IP range
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}