# Cortex EMR AWS Infrastructure with Terraform

This repository contains Terraform configurations for deploying the Cortex EMR system on AWS with security and scalability best practices.

## Architecture Overview

- **Multi-AZ deployment** across two AWS accounts (Network and Application)
- **Auto-scaling** application servers with load balancing
- **RDS MySQL Multi-AZ** for high availability
- **Amazon FSx for Windows File Server** for shared storage
- **VPC with private subnets** for security
- **Active Directory integration** via AWS Directory Service
- **Comprehensive monitoring** with CloudWatch

## Repository Structure

```
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── modules/
│   ├── networking/
│   ├── compute/
│   ├── database/
│   ├── storage/
│   ├── security/
│   └── monitoring/
├── scripts/
│   ├── user-data/
│   └── setup/
└── docs/
    ├── architecture.md
    └── deployment.md
```

## Key Features

### Security
- Private subnets for all application components
- VPN connectivity to on-premises Active Directory
- Security groups with least privilege access
- IAM roles with minimal required permissions
- Encrypted storage and data in transit
- Regular automated backups

### Scalability
- Auto Scaling Groups for application servers
- Application and Network Load Balancers
- Reserved Instances for cost optimization
- CloudWatch monitoring and alarms
- Automated scaling policies

### High Availability
- Multi-AZ RDS deployment
- Auto Scaling across multiple AZs
- Automated failover capabilities
- Regular backup and disaster recovery

## Prerequisites

1. **AWS Accounts**: Two AWS accounts (Network and Application)
2. **Terraform Cloud**: Account setup with VCS integration
3. **GitHub**: Repository for version control
4. **AWS CLI**: Configured with appropriate permissions
5. **Domain**: For DNS and certificate management

## Environment Configuration

### Production Environment
- **Application Servers**: m5.xlarge (4 vCPU, 16 GB RAM) - upgradeable to m5.2xlarge (8 vCPU, 32 GB)
- **Database**: RDS MySQL db.m5.xlarge Multi-AZ
- **Integration Server**: m5.large (2 vCPU, 8 GB RAM) - upgradeable to m5.xlarge
- **File Server**: Amazon FSx for Windows (3 TB, 34 MBps throughput)

### Development/Test Environment  
- **Test Server**: t3.2xlarge (8 vCPU, 32 GB RAM)
- **Database**: Single AZ RDS for cost optimization
- **Reduced instance sizes** for cost efficiency

## Deployment Steps

### 1. Initial Setup
```bash
# Clone repository
git clone <repository-url>
cd cortex-emr-terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables
Update `terraform.tfvars` for each environment with your specific values:

```hcl
# AWS Configuration
aws_region = "me-central-1"
environment = "prod"

# Networking
vpc_cidr = "10.0.0.0/16"
availability_zones = ["me-central-1a", "me-central-1b"]

# Domain and DNS
domain_name = "yourdomain.com"
subdomain = "emr"

# Active Directory
ad_domain_name = "corp.yourdomain.com"
ad_domain_netbios = "CORP"
```

### 3. Deploy Infrastructure
```bash
# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

## Cost Optimization

The estimated monthly cost is approximately **$824 USD** for the complete production environment, including:

- Reserved Instances for production servers (significant savings)
- Right-sized instances based on actual requirements
- Multi-AZ deployment for high availability
- Automated backup and monitoring

## Monitoring and Maintenance

### CloudWatch Monitoring
- EC2 instance metrics (CPU, memory, disk)
- RDS database performance metrics
- Application Load Balancer health checks
- Custom application metrics

### Automated Backups
- RDS automated backups with point-in-time recovery
- FSx automated daily backups
- EC2 AMI snapshots for golden images

### Security Monitoring
- CloudTrail for API activity logging
- VPC Flow Logs for network monitoring
- AWS Config for compliance monitoring

## Support and Documentation

- **Architecture Documentation**: See `docs/architecture.md`
- **Deployment Guide**: See `docs/deployment.md`
- **Troubleshooting**: Contact system administrators
- **Updates**: Use GitHub workflow for infrastructure changes

## Instance Type Recommendations

Based on your application provider specifications, consider these instance upgrades:

| Component | Current | Recommended | Reason |
|-----------|---------|-------------|---------|
| App Server | t3.xlarge | m5.2xlarge | Match 8 vCPU, 32 GB requirement |
| Database | db.m5.xlarge | db.m5.2xlarge | Match 8 vCPU, 32 GB requirement |
| Integration | t3.xlarge | m5.xlarge | Adequate for 4 vCPU, 16 GB |

## Next Steps

1. **Review and customize** the Terraform configurations
2. **Set up Terraform Cloud** workspace with GitHub integration
3. **Configure AWS accounts** and permissions
4. **Deploy development environment** first for testing
5. **Deploy production environment** after validation
6. **Set up monitoring and alerting**
7. **Configure backup and disaster recovery procedures**