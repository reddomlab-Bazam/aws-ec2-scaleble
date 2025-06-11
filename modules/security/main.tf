# modules/security/main.tf

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for Application Load Balancer"
  
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Application Server Security Group
resource "aws_security_group" "application" {
  name_prefix = "${var.name_prefix}-app-"
  vpc_id      = var.vpc_id
  description = "Security group for Cortex EMR application servers"
  
  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  ingress {
    description = "RDP from on-premises"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  ingress {
    description = "WinRM from on-premises"
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  ingress {
    description = "SMB/CIFS for file sharing"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  ingress {
    description = "NetBIOS Session Service"
    from_port   = 139
    to_port     = 139
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  ingress {
    description = "Active Directory - LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "Active Directory - LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "Active Directory - Kerberos"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "Active Directory - Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-application-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Integration Server Security Group
resource "aws_security_group" "integration" {
  name_prefix = "${var.name_prefix}-integration-"
  vpc_id      = var.vpc_id
  description = "Security group for integration servers"
  
  ingress {
    description     = "HTTP from Application servers"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description = "HTTPS from Application servers"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description = "RDP from on-premises"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  ingress {
    description = "Custom integration ports"
    from_port   = 9000
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-integration-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Database Security Group
resource "aws_security_group" "database" {
  name_prefix = "${var.name_prefix}-db-"
  vpc_id      = var.vpc_id
  description = "Security group for RDS MySQL database"
  
  ingress {
    description     = "MySQL from Application servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description     = "MySQL from Integration servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.integration.id]
  }
  
  ingress {
    description = "MySQL from on-premises (admin access)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-database-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# File Server Security Group (Amazon FSx)
resource "aws_security_group" "file_server" {
  name_prefix = "${var.name_prefix}-fsx-"
  vpc_id      = var.vpc_id
  description = "Security group for Amazon FSx file server"
  
  ingress {
    description     = "SMB/CIFS from Application servers"
    from_port       = 445
    to_port         = 445
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description     = "NetBIOS from Application servers"
    from_port       = 139
    to_port         = 139
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }
  
  ingress {
    description = "SMB/CIFS from on-premises"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  ingress {
    description = "RPC Endpoint Mapper"
    from_port   = 135
    to_port     = 135
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  ingress {
    description = "Dynamic RPC"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, var.on_premises_cidr]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-file-server-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${var.name_prefix}-bastion-"
  vpc_id      = var.vpc_id
  description = "Security group for bastion host"
  
  ingress {
    description = "RDP from on-premises"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }
  
  egress {
    description = "RDP to private subnets"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "DNS outbound"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "DNS UDP outbound"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.name_prefix}-ec2-role"
  
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
  
  tags = var.tags
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
  
  tags = var.tags
}

# IAM Policy for EC2 instances
resource "aws_iam_role_policy" "ec2_policy" {
  name = "${var.name_prefix}-ec2-policy"
  role = aws_iam_role.ec2_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "fsx:DescribeFileSystems",
          "fsx:ClientWrite"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.name_prefix} encryption"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key for EC2 and RDS"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "rds.amazonaws.com"]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-kms-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}