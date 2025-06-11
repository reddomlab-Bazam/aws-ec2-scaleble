# Cortex EMR Security Best Practices Guide

## Overview

This guide outlines security best practices for the Cortex EMR AWS deployment, covering network security, data protection, access controls, and compliance requirements for healthcare environments.

## Network Security

### VPC Security Architecture

#### Network Segmentation
```
Internet Gateway
    ↓
Public Subnets (Load Balancers, Bastion)
    ↓
Private Subnets (Application Servers)
    ↓
Database Subnets (RDS, Isolated)
    ↓
On-Premises (VPN Connection)
```

#### Security Groups Configuration

**Application Load Balancer Security Group:**
- Inbound: HTTPS (443) and HTTP (80) from Internet
- Outbound: HTTP (8080) to Application Servers

**Application Server Security Group:**
- Inbound: HTTP (8080) from ALB only
- Inbound: RDP (3389) from on-premises only
- Inbound: Active Directory ports from VPC and on-premises
- Outbound: All traffic (for updates and external integrations)

**Database Security Group:**
- Inbound: MySQL (3306) from Application Servers only
- No direct internet access
- Outbound: None (database should not initiate connections)

**File Server Security Group:**
- Inbound: SMB/CIFS (445) from Application Servers only
- Inbound: NetBIOS (139) from Application Servers only
- No direct internet access

### Network Access Controls (NACLs)

```hcl
# Example NACL rules for database subnet
resource "aws_network_acl_rule" "database_ingress_mysql" {
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 3306
  to_port        = 3306
}

resource "aws_network_acl_rule" "database_egress_mysql_response" {
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 1024
  to_port        = 65535
}
```

### VPN Security

#### Site-to-Site VPN Configuration
- **Encryption:** AES-256
- **Authentication:** Pre-shared keys (PSK)
- **Perfect Forward Secrecy (PFS):** Enabled
- **Dead Peer Detection (DPD):** Enabled

#### VPN Monitoring
```bash
# Monitor VPN connection status
aws ec2 describe-vpn-connections --vpn-connection-ids $(terraform output -raw vpn_connection_id)

# Check VPN tunnel status
aws logs filter-log-events --log-group-name "/aws/vpn" --start-time $(date -d '1 hour ago' +%s)000
```

## Data Protection

### Encryption at Rest

#### RDS Encryption
- **Database Encryption:** AES-256 using AWS KMS
- **Backup Encryption:** Automatic with database encryption
- **Snapshot Encryption:** Enabled for all snapshots

#### EBS Encryption
- **Volume Encryption:** All EBS volumes encrypted with KMS
- **AMI Encryption:** Golden AMIs created with encryption enabled
- **Snapshot Encryption:** All snapshots encrypted

#### FSx Encryption
- **Data Encryption:** Files encrypted at rest using KMS
- **Backup Encryption:** Automatic backup encryption
- **Transit Encryption:** SMB encryption enabled

### Encryption in Transit

#### Application Layer
- **HTTPS/TLS 1.2+:** All web traffic encrypted
- **Database Connections:** SSL/TLS for MySQL connections
- **File System:** SMB 3.0 encryption for FSx access

#### Network Layer
- **VPN Encryption:** IPSec tunnels for on-premises connectivity
- **Internal Traffic:** Consider using AWS Certificate Manager for internal services

### Key Management

#### KMS Key Policies
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable Root Access",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow Service Access",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "rds.amazonaws.com",
          "ec2.amazonaws.com",
          "fsx.amazonaws.com"
        ]
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:CreateGrant"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Key Rotation
- **Automatic Rotation:** Enabled for all KMS keys
- **Rotation Period:** Annual rotation recommended
- **Manual Rotation:** Available for emergency situations

## Access Control and Identity Management

### IAM Best Practices

#### Principle of Least Privilege
```hcl
# Example IAM policy for EC2 instances
data "aws_iam_policy_document" "ec2_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream"
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/ec2/cortex-emr/*"
    ]
  }
}
```

#### Role-Based Access Control
```hcl
# Application Server Role
resource "aws_iam_role" "application_server" {
  name = "${var.name_prefix}-application-server-role"
  
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

# Database Access Role (separate from application role)
resource "aws_iam_role" "database_admin" {
  name = "${var.name_prefix}-database-admin-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/database-admin"
          ]
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId": "unique-external-id"
          }
        }
      }
    ]
  })
}
```

### Active Directory Integration

#### Security Best Practices
1. **Service Accounts:** Use dedicated service accounts for AWS integration
2. **Password Policy:** Enforce strong password policies
3. **Account Lockout:** Configure account lockout policies
4. **Group Policy:** Use GPOs for security configuration
5. **Audit Logging:** Enable comprehensive AD audit logging

#### AD Connector Configuration
```hcl
resource "aws_directory_service_directory" "main" {
  name     = var.ad_domain_name
  password = var.ad_admin_password
  type     = "ADConnector"
  size     = "Small"
  
  connect_settings {
    customer_dns_ips  = var.on_premises_dns_ips
    customer_username = var.ad_service_account
    subnet_ids        = var.private_subnet_ids
    vpc_id            = var.vpc_id
  }
  
  # Enable logging
  tags = {
    LogLevel = "INFO"
  }
}
```

### Multi-Factor Authentication (MFA)

#### AWS Console Access
- **Require MFA:** For all privileged accounts
- **Hardware Tokens:** Recommended for production access
- **Virtual MFA:** Acceptable for development environments

#### Application Access
- **SAML Integration:** Use AD FS or similar for SSO
- **Application-Level MFA:** Implement within Cortex EMR
- **API Access:** Use temporary credentials with MFA

## Compliance and Auditing

### HIPAA Compliance

#### Business Associate Agreement (BAA)
- **AWS BAA:** Execute BAA with AWS for HIPAA compliance
- **Third-Party Services:** Ensure all services have appropriate BAAs

#### HIPAA Security Rule Requirements
1. **Access Control:** Implement unique user identification
2. **Audit Controls:** Log all access to PHI
3. **Integrity:** Protect PHI from improper alteration
4. **Person or Entity Authentication:** Verify user identity
5. **Transmission Security:** Protect PHI during transmission

#### HIPAA Implementation Checklist
- [ ] Execute AWS Business Associate Agreement
- [ ] Enable CloudTrail for all AWS API calls
- [ ] Configure VPC Flow Logs for network monitoring
- [ ] Implement comprehensive logging within applications
- [ ] Regular access reviews and user deprovisioning
- [ ] Encrypt all PHI at rest and in transit
- [ ] Implement backup and disaster recovery procedures
- [ ] Conduct regular security risk assessments

### Audit Logging

#### CloudTrail Configuration
```hcl
resource "aws_cloudtrail" "main" {
  name           = "${var.name_prefix}-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.bucket
  
  # Enable logging for all regions
  is_multi_region_trail = true
  
  # Enable log file validation
  enable_log_file_validation = true
  
  # Include global service events
  include_global_service_events = true
  
  # KMS encryption
  kms_key_id = aws_kms_key.cloudtrail.arn
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.data.arn}/*"]
    }
    
    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.data.arn]
    }
  }
}
```

#### Application Logging
```powershell
# Configure IIS logging for web applications
Set-WebConfigurationProperty -Filter "system.webServer/httpLogging" -Name "enabled" -Value $true
Set-WebConfigurationProperty -Filter "system.webServer/httpLogging" -Name "logFormat" -Value "W3C"

# Configure Windows Event Logging
New-EventLog -LogName "CortexEMR" -Source "CortexEMRApp"
Write-EventLog -LogName "CortexEMR" -Source "CortexEMRApp" -EntryType Information -EventId 1000 -Message "Application started"
```

### Regular Security Assessments

#### Automated Security Scanning
```yaml
# Security scanning workflow
name: Security Scan
on:
  schedule:
    - cron: '0 2 * * 0' # Weekly on Sunday at 2 AM
    
jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          framework: terraform
          output_format: sarif
          
      - name: Upload to Security Hub
        run: |
          aws securityhub batch-import-findings --findings file://checkov-results.sarif
```

#### Vulnerability Management
1. **OS Patching:** Monthly Windows Server updates
2. **Application Updates:** Regular Cortex EMR updates
3. **Dependency Scanning:** Monitor third-party libraries
4. **Container Scanning:** If using containers

## Incident Response

### Security Incident Response Plan

#### Detection and Analysis
1. **Automated Alerts:** CloudWatch alarms for suspicious activity
2. **Log Analysis:** Use CloudWatch Insights for investigation
3. **Threat Intelligence:** Integrate with AWS GuardDuty

#### Containment and Eradication
1. **Isolate Affected Systems:** Security group modifications
2. **Preserve Evidence:** Create EBS snapshots
3. **Remove Threats:** Patch vulnerabilities, remove malware

#### Recovery and Lessons Learned
1. **Restore Services:** From clean backups if necessary
2. **Monitor for Reoccurrence:** Enhanced monitoring
3. **Update Procedures:** Improve security controls

### Emergency Procedures

#### Security Group Lockdown
```bash
#!/bin/bash
# Emergency script to lock down application access

# Remove internet access from application servers
aws ec2 revoke-security-group-ingress \
  --group-id $APP_SECURITY_GROUP_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SECURITY_GROUP_ID

# Block all outbound traffic from application servers
aws ec2 revoke-security-group-egress \
  --group-id $APP_SECURITY_GROUP_ID \
  --protocol all \
  --cidr 0.0.0.0/0
```

#### Database Access Revocation
```bash
#!/bin/bash
# Emergency script to revoke database access

# Create new security group with no rules
NEW_SG=$(aws ec2 create-security-group \
  --group-name emergency-db-lockdown \
  --description "Emergency database lockdown" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Apply to RDS instance
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE_ID \
  --vpc-security-group-ids $NEW_SG \
  --apply-immediately
```

## Security Monitoring and Alerting

### CloudWatch Security Metrics

#### Failed Login Attempts
```hcl
resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "${var.name_prefix}-failed-logins"
  log_group_name = "/aws/ec2/cortex-emr/security"
  pattern        = "[timestamp, event_type=\"FAILED_LOGIN\", username, source_ip, ...]"
  
  metric_transformation {
    name      = "FailedLoginAttempts"
    namespace = "CortexEMR/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_logins_alarm" {
  alarm_name          = "${var.name_prefix}-failed-logins"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedLoginAttempts"
  namespace           = "CortexEMR/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Multiple failed login attempts detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```

#### Privilege Escalation Detection
```hcl
resource "aws_cloudwatch_log_metric_filter" "privilege_escalation" {
  name           = "${var.name_prefix}-privilege-escalation"
  log_group_name = "/aws/cloudtrail"
  pattern        = "{ ($.eventName = AttachUserPolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = PutRolePolicy) }"
  
  metric_transformation {
    name      = "PrivilegeEscalation"
    namespace = "CortexEMR/Security"
    value     = "1"
  }
}
```

### Security Dashboard

#### Custom Security Metrics
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["CortexEMR/Security", "FailedLoginAttempts"],
          [".", "PrivilegeEscalation"],
          [".", "UnauthorizedAPICall"],
          ["AWS/GuardDuty", "FindingCount"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "us-east-1",
        "title": "Security Metrics",
        "period": 300
      }
    }
  ]
}
```

## Data Loss Prevention (DLP)

### Data Classification
1. **PHI (Protected Health Information):** Highest protection level
2. **PII (Personally Identifiable Information):** High protection level
3. **Business Data:** Medium protection level
4. **Public Data:** Standard protection level

### Data Handling Procedures
1. **Data Encryption:** All sensitive data encrypted
2. **Data Masking:** Mask PHI in non-production environments
3. **Data Retention:** Implement retention policies per regulations
4. **Data Disposal:** Secure deletion procedures

### S3 Bucket Security
```hcl
resource "aws_s3_bucket_policy" "data_protection" {
  bucket = aws_s3_bucket.data.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "RequireSSEKMS"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.data.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}
```

This security guide provides comprehensive protection for your Cortex EMR deployment while maintaining compliance with healthcare regulations.