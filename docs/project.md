# Cortex EMR AWS Infrastructure - UAE Healthcare Deployment

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-blue.svg)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-UAE%20Region-orange.svg)](https://aws.amazon.com/)
[![ADHICS](https://img.shields.io/badge/ADHICS-Compliant-green.svg)](https://adhics.gov.ae/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A comprehensive Terraform infrastructure-as-code solution for deploying Cortex EMR (Electronic Medical Records) system on AWS UAE region with **ADHICS (Abu Dhabi Health Information and Cyber Security Standards)** compliance, enterprise-grade security, and healthcare-specific requirements.

## 🇦🇪 UAE Healthcare Compliance

This solution is specifically designed for healthcare organizations in the UAE and includes:

- **ADHICS Compliance**: Full compliance with Abu Dhabi Health Information and Cyber Security Standards
- **Data Sovereignty**: All data remains within UAE borders (me-central-1 region)
- **Healthcare Security**: Enhanced security controls for PHI (Protected Health Information)
- **UAE Regulatory Alignment**: Compliance with UAE healthcare regulations
- **Arabic Language Support**: Infrastructure naming and documentation aligned with UAE standards

## 🏗️ Architecture Overview

This solution deploys a highly available, secure, and scalable EMR infrastructure with:

- **Multi-AZ deployment** across two AWS accounts (Network and Application)
- **Auto-scaling application servers** with Application Load Balancer
- **RDS MySQL Multi-AZ** database with automated backups
- **Amazon FSx for Windows File Server** for shared storage
- **VPN connectivity** to on-premises Active Directory
- **Comprehensive monitoring** with CloudWatch dashboards and alarms
- **Security hardening** with encryption at rest and in transit

![Architecture Diagram](docs/architecture-diagram.png)

## 📋 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform 1.0+ installed
- Terraform Cloud account with workspaces configured
- GitHub repository with VCS integration
- Domain name for SSL certificate (production)

### 1. Clone Repository

```bash
git clone https://github.com/your-org/cortex-emr-terraform.git
cd cortex-emr-terraform
```

### 2. Configure Terraform Cloud

Create workspaces in Terraform Cloud:
- `cortex-emr-dev` for development environment
- `cortex-emr-prod` for production environment

### 3. Set Environment Variables

In Terraform Cloud workspaces, configure:

```bash
# AWS Credentials
AWS_ACCESS_KEY_ID=(sensitive)
AWS_SECRET_ACCESS_KEY=(sensitive)

# Terraform Variables
TF_VAR_domain_name="yourcompany.com"
TF_VAR_notification_email="it-team@yourcompany.com"
TF_VAR_vpn_customer_gateway_ip="your-public-ip"
TF_VAR_ad_admin_password=(sensitive)
TF_VAR_db_master_password=(sensitive)
```

### 4. Deploy Development Environment

```bash
git checkout develop
# Customize environments/dev/terraform.tfvars
git commit -am "Configure development environment"
git push origin develop
```

### 5. Deploy Production Environment

```bash
git checkout main
git merge develop
git push origin main
```

Monitor deployment progress in GitHub Actions and Terraform Cloud.

## 🗂️ Project Structure

```
├── environments/
│   ├── dev/                    # Development environment
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── outputs.tf
│   └── prod/                   # Production environment
│       ├── main.tf
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── outputs.tf
├── modules/
│   ├── networking/             # VPC, subnets, VPN
│   ├── security/               # Security groups, IAM, KMS
│   ├── compute/                # EC2, Auto Scaling, Load Balancers
│   ├── database/               # RDS MySQL with Multi-AZ
│   ├── storage/                # Amazon FSx, S3 buckets
│   └── monitoring/             # CloudWatch, alarms, dashboards
├── scripts/
│   ├── deploy.sh              # Deployment automation
│   ├── health-check.sh        # Health check script
│   └── backup.sh              # Manual backup script
├── .github/workflows/         # CI/CD pipelines
├── docs/                      # Documentation
└── README.md
```

## 💰 Cost Breakdown (UAE Region)

### Production Environment (~$850/month)

| Component | Instance Type | Monthly Cost (USD) |
|-----------|---------------|--------------------|
| Application Servers (2x) | m5.xlarge Reserved | $245 |
| Integration Server | m5.large Reserved | $122 |
| Database | db.m5.xlarge Multi-AZ | $397 |
| File System | FSx 3TB, 34 MBps | $295 |
| Load Balancers | ALB + NLB | $102 |
| ADHICS Compliance | Config, GuardDuty, WAF | $45 |
| Other Services | Route 53, S3, CloudTrail | $38 |

*Note: UAE region pricing may vary slightly from US regions. Costs include ADHICS compliance services.*

### Development Environment (~$220-320/month)

- Smaller instance types (t3.large, t3.medium)
- Single AZ deployment for cost optimization
- Reduced storage capacity and throughput
- Optional ADHICS compliance features for testing

## 🇦🇪 UAE-Specific Configuration

### Regional Settings
- **Primary Region**: me-central-1 (Middle East - UAE)
- **Availability Zones**: me-central-1a, me-central-1b
- **Data Residency**: All data remains within UAE borders
- **Backup Strategy**: No cross-region backups (ADHICS compliance)

### ADHICS Compliance Features
- **AWS Config**: Continuous compliance monitoring
- **GuardDuty**: Threat detection and incident response
- **Security Hub**: Centralized security dashboard
- **CloudTrail**: 7-year audit log retention
- **WAF**: Application layer protection
- **Encryption**: All data encrypted at rest and in transit

### Healthcare-Specific Configurations
```hcl
# UAE timezone considerations
db_backup_window = "03:00-04:00"      # 3 AM UAE time
db_maintenance_window = "fri:04:00-fri:05:00"  # Friday maintenance

# ADHICS compliance tags
tags = {
  Compliance = "ADHICS"
  DataSovereignty = "UAE"
  HealthcareCompliance = "Enabled"
  Environment = "Production"
}
```

### Current Configuration

| Server Type | Current | Recommended Upgrade |
|------------|---------|-------------------|
| Application Server | m5.xlarge (4 vCPU, 16GB) | m5.2xlarge (8 vCPU, 32GB) |
| Database | db.m5.xlarge (4 vCPU, 16GB) | db.m5.2xlarge (8 vCPU, 32GB) |
| Integration Server | m5.large (2 vCPU, 8GB) | m5.xlarge (4 vCPU, 16GB) |
| File System | FSx 3TB, 34 MBps | Scalable based on needs |

To match your application provider's exact specifications (8 vCPU, 32GB), update the instance types in `terraform.tfvars`:

```hcl
app_instance_type = "m5.2xlarge"
db_instance_class = "db.m5.2xlarge"
integration_instance_type = "m5.xlarge"
```

## 🛡️ Security Features

### Network Security
- **Private subnets** for all application components
- **VPN connectivity** to on-premises Active Directory
- **Security groups** with least privilege access
- **NACLs** for additional network layer security
- **VPC Flow Logs** for network monitoring

### Data Protection
- **Encryption at rest** for all storage (EBS, RDS, FSx, S3)
- **Encryption in transit** with SSL/TLS
- **KMS key management** with automatic rotation
- **Automated backups** with point-in-time recovery

### Access Control
- **IAM roles** with minimal required permissions
- **Active Directory integration** via AWS Directory Service
- **Multi-factor authentication** support
- **Audit logging** with CloudTrail

### Compliance
- **HIPAA-ready** architecture with BAA support
- **SOC 2 compliance** capabilities
- **Regular security scans** with Checkov and TFSec
- **Vulnerability management** with AWS Inspector

## 📊 Monitoring & Alerting

### CloudWatch Dashboard
- Application performance metrics
- Database performance and connections
- Auto Scaling Group status
- Load Balancer health checks
- Custom application metrics

### Automated Alerts
- High CPU/memory utilization
- Database connection errors
- Application errors and 5xx responses
- Failed login attempts
- VPN connection status
- Storage utilization thresholds

### Log Aggregation
- Application logs from Tomcat
- System logs from Windows servers
- Database logs from RDS
- VPC Flow Logs for network analysis

## 🚀 Deployment Commands

### Using Deployment Script

```bash
# Plan development environment
./scripts/deploy.sh dev plan

# Deploy development environment
./scripts/deploy.sh dev apply

# Check environment health
./scripts/health-check.sh dev

# Create manual backups
./scripts/backup.sh prod

# Get environment outputs
./scripts/deploy.sh prod output
```

### Direct Terraform Commands

```bash
cd environments/prod
terraform init
terraform plan
terraform apply
terraform output
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflows

1. **terraform.yml** - Main deployment pipeline
   - Format checking and validation
   - Security scanning with Checkov/TFSec
   - Automated plan/apply for each environment
   - Cost estimation with Infracost

2. **pr-validation.yml** - Pull request validation
   - Code formatting and validation
   - Security compliance checks
   - Cost impact analysis

3. **scheduled-checks.yml** - Regular maintenance
   - Infrastructure drift detection
   - Security compliance monitoring
   - Cost optimization recommendations

### Deployment Process

1. **Development**: Push to `develop` branch triggers dev deployment
2. **Production**: Merge to `main` branch triggers prod deployment
3. **Manual**: Use workflow dispatch for specific deployments
4. **Rollback**: Revert commits and redeploy previous version

## 🛠️ Management & Maintenance

### Daily Operations

```bash
# Check system health
./scripts/health-check.sh prod

# Monitor costs
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost

# Review CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM
```

### Weekly Tasks

```bash
# Create manual backup
./scripts/backup.sh prod

# Check for drift
terraform plan -detailed-exitcode

# Review security groups
aws ec2 describe-security-groups --group-names cortex-emr-*
```

### Scaling Operations

#### Scale Up Application Servers
```hcl
# In terraform.tfvars
app_desired_capacity = 4  # Increase from 2
app_max_size = 6          # Increase from 4
```

#### Upgrade Instance Types
```hcl
# In terraform.tfvars
app_instance_type = "m5.2xlarge"  # Upgrade from m5.xlarge
db_instance_class = "db.m5.2xlarge"  # Upgrade from db.m5.xlarge
```

## 🔍 Troubleshooting

### Common Issues

#### Application Not Accessible
```bash
# Check load balancer health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# Check security groups
aws ec2 describe-security-groups --group-ids $(terraform output -raw application_security_group_id)
```

#### Database Connection Issues
```bash
# Check database status
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw db_instance_identifier)

# Test connectivity
telnet $(terraform output -raw db_endpoint) 3306
```

#### File System Access Issues
```bash
# Check FSx status
aws fsx describe-file-systems --file-system-ids $(terraform output -raw fsx_id)

# From Windows: Test-ComputerSecureChannel -Verbose
```

### Useful Resources

- [Deployment Guide](docs/deployment.md) - Detailed deployment instructions
- [Security Guide](docs/security.md) - Security best practices
- [ADHICS Compliance Guide](docs/adhics-compliance.md) - UAE healthcare compliance
- [Architecture Documentation](docs/architecture.md) - Technical architecture details
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions
- [UAE Healthcare Regulations](https://www.doh.gov.ae/) - Official DoH guidelines

## 📞 Support

### Getting Help

1. **Documentation**: Check the `docs/` directory for detailed guides
2. **Issues**: Create GitHub issues for bugs or feature requests  
3. **Discussions**: Use GitHub Discussions for questions
4. **Emergency**: Contact system administrators directly

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Useful Links

- [Terraform Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS UAE Region Services](https://aws.amazon.com/about-aws/global-infrastructure/regions/)
- [ADHICS Framework](https://adhics.gov.ae/) - Official ADHICS documentation
- [UAE NCEMA Guidelines](https://www.ncema.gov.ae/) - National cybersecurity guidelines
- [DoH Abu Dhabi](https://www.doh.gov.ae/) - Department of Health regulations
- [HIPAA on AWS](https://aws.amazon.com/compliance/hipaa-compliance/)
- [Cortex EMR Documentation](https://cortex-emr.com/docs)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏷️ Version History

- **v1.0.0** - Initial release with basic EMR infrastructure
- **v1.1.0** - Added monitoring and alerting
- **v1.2.0** - Enhanced security and compliance features
- **v1.3.0** - CI/CD pipeline integration
- **v2.0.0** - Multi-environment support and cost optimization

---

**Built with ❤️ for healthcare technology**