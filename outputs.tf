# outputs.tf - Infrastructure Outputs

output "application_url" {
  description = "URL to access the Cortex EMR application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "bastion_host_ip" {
  description = "Public IP of the bastion host (if created)"
  value       = var.create_bastion ? aws_instance.bastion[0].public_ip : "Not created"
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "auto_scaling_group_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.app.name
}

# Connection information
output "connection_info" {
  description = "Connection information for the deployment"
  value = {
    application_url = "http://${aws_lb.main.dns_name}"
    health_check    = "http://${aws_lb.main.dns_name}/health.aspx"
    bastion_rdp     = var.create_bastion ? "${aws_instance.bastion[0].public_ip}:3389" : "Not available"
  }
}

---

# terraform.tfvars - Configuration Values

# Basic Settings
aws_region   = "us-east-1"  # Change to your preferred region
environment  = "dev"
project_name = "cortex-emr"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# Database Settings
db_instance_class           = "db.t3.medium"    # Small for dev, use db.m5.large+ for prod
db_allocated_storage        = 100
db_max_allocated_storage    = 500
db_name                     = "cortex_emr"
db_username                 = "admin"
db_password                 = "ChangeMe123!"    # Change this to a secure password
db_backup_retention_period  = 7

# Application Server Settings
app_instance_type    = "t3.large"              # 2 vCPU, 8GB RAM
app_min_size         = 1
app_max_size         = 4
app_desired_capacity = 2

# Optional Components
create_bastion = true                           # Set to false if you don't need bastion host

---

# README.md - Deployment Instructions

# Simplified Cortex EMR Infrastructure

This is a simplified version of the Cortex EMR infrastructure deployment that focuses on core components without complex features like Entra AD integration or FortiGate VPN.

## Architecture

```
Internet Gateway
    ↓
Application Load Balancer (Public Subnets)
    ↓
Auto-Scaling Group (Private Subnets)
    ↓
RDS MySQL Database (Database Subnets)
```

## Components Included

- **VPC** with public, private, and database subnets
- **Application Load Balancer** for distributing traffic
- **Auto-Scaling Group** with Windows Server 2022 instances
- **RDS MySQL Database** with automated backups
- **CloudWatch Monitoring** with basic alarms
- **Optional Bastion Host** for management access

## Prerequisites

1. AWS CLI configured with appropriate permissions
2. Terraform 1.0+ installed
3. An AWS account with necessary permissions

## Quick Start

1. **Clone or create the files**:
   ```bash
   mkdir cortex-emr-simple
   cd cortex-emr-simple
   # Copy all the .tf files and user-data.ps1 into this directory
   ```

2. **Configure variables**:
   ```bash
   # Edit terraform.tfvars with your specific values
   # IMPORTANT: Change the db_password to something secure
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Access the application**:
   ```bash
   # Get the application URL
   terraform output application_url
   
   # Test health check
   curl $(terraform output -raw application_url)/health.aspx
   ```

## Configuration Options

### For Development Environment:
- Instance Type: `t3.medium` or `t3.large`
- Database: `db.t3.medium`
- Min Instances: 1
- Max Instances: 2

### For Production Environment:
- Instance Type: `m5.large` or `m5.xlarge`
- Database: `db.m5.large` or larger
- Min Instances: 2
- Max Instances: 6
- Enable Multi-AZ for database

## Security Features

- All servers in private subnets
- Database isolated in separate subnets
- Security groups with minimal required access
- EBS volumes encrypted
- Database encrypted at rest

## Monitoring

- CloudWatch metrics for CPU utilization
- Auto-scaling based on CPU thresholds
- CloudWatch agent installed on all instances
- Health check endpoint at `/health.aspx`

## Management

- Optional bastion host for RDP access
- Systems Manager (SSM) for remote management
- CloudWatch logs for troubleshooting

## Scaling

The infrastructure automatically scales based on CPU utilization:
- Scale up when CPU > 70% for 2 periods
- Scale down when CPU < 30% for 2 periods
- Cooldown period: 5 minutes

## Costs (Approximate)

### Development Environment (~$150-200/month):
- t3.large instances: ~$67/month each
- db.t3.medium: ~$44/month
- Load balancer: ~$22/month
- Data transfer and storage: ~$20/month

### Production Environment (~$400-600/month):
- m5.large instances: ~$88/month each
- db.m5.large: ~$176/month
- Load balancer: ~$22/month
- Data transfer and storage: ~$50/month

## Customization

To customize for your needs:

1. **Change instance sizes** in `terraform.tfvars`
2. **Modify database settings** for your requirements
3. **Update user-data.ps1** to install your specific applications
4. **Adjust auto-scaling thresholds** in the CloudWatch alarms

## Troubleshooting

1. **Check application health**: Visit `/health.aspx`
2. **View instance logs**: Use Systems Manager Session Manager
3. **Monitor metrics**: Check CloudWatch dashboards
4. **Database connectivity**: Verify security groups and network ACLs

## Support

This is a simplified deployment. For production use, consider:
- SSL/TLS certificates
- Custom domain names
- Enhanced monitoring and alerting
- Backup and disaster recovery procedures
- Security hardening
- Compliance requirements (HIPAA, etc.)

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```

**Warning**: This will delete all resources and data. Make sure to backup any important data first.