# Cortex EMR AWS Deployment Guide

## Prerequisites Checklist

### AWS Account Setup
- [ ] Two AWS accounts configured (Network and Application)
- [ ] AWS CLI installed and configured with appropriate permissions
- [ ] Route 53 hosted zone for your domain
- [ ] VPN connection to on-premises Active Directory (for production)

### Terraform Cloud Setup
- [ ] Terraform Cloud account created
- [ ] Organization created in Terraform Cloud
- [ ] Workspaces created for each environment
- [ ] API token generated and stored securely

### GitHub Repository Setup
- [ ] Repository created with this codebase
- [ ] Branch protection rules configured
- [ ] Required secrets configured in GitHub

### Domain and SSL
- [ ] Domain name registered and DNS configured
- [ ] SSL certificate requirements determined

## Required GitHub Secrets

Configure these secrets in your GitHub repository settings:

```
TF_API_TOKEN=your-terraform-cloud-api-token
INFRACOST_API_KEY=your-infracost-api-key (optional)
TEAMS_WEBHOOK_URL=your-teams-webhook-url (optional)
```

## Step-by-Step Deployment

### 1. Repository Setup

```bash
# Clone the repository
git clone https://github.com/your-org/cortex-emr-terraform.git
cd cortex-emr-terraform

# Create environment-specific branches
git checkout -b develop
git checkout -b main
```

### 2. Terraform Cloud Workspace Configuration

#### Development Workspace
```hcl
# In Terraform Cloud UI, create workspace: cortex-emr-dev
# Configure these environment variables:

# AWS Credentials
AWS_ACCESS_KEY_ID = (sensitive)
AWS_SECRET_ACCESS_KEY = (sensitive)

# Terraform Variables
TF_VAR_notification_email = "dev-team@yourcompany.com"
TF_VAR_domain_name = "dev.yourcompany.com"
TF_VAR_ad_admin_password = (sensitive)
TF_VAR_db_master_password = (sensitive)
TF_VAR_vpn_customer_gateway_ip = "your-public-ip"
```

#### Production Workspace
```hcl
# In Terraform Cloud UI, create workspace: cortex-emr-prod
# Configure these environment variables:

# AWS Credentials
AWS_ACCESS_KEY_ID = (sensitive)
AWS_SECRET_ACCESS_KEY = (sensitive)

# Terraform Variables
TF_VAR_notification_email = "it-team@yourcompany.com"
TF_VAR_domain_name = "yourcompany.com"
TF_VAR_ad_admin_password = (sensitive)
TF_VAR_db_master_password = (sensitive)
TF_VAR_vpn_customer_gateway_ip = "your-public-ip"
TF_VAR_on_premises_dns_ips = ["192.168.1.10", "192.168.1.11"]
```

### 3. Configuration Customization

#### Update terraform.tfvars files

**Development Environment:**
```bash
# Edit environments/dev/terraform.tfvars
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars

# Update with your specific values:
# - domain_name
# - notification_email
# - vpn_customer_gateway_ip
# - on_premises_dns_ips
```

**Production Environment:**
```bash
# Edit environments/prod/terraform.tfvars
cp environments/prod/terraform.tfvars.example environments/prod/terraform.tfvars

# Update with your specific values:
# - domain_name
# - notification_email
# - vpn_customer_gateway_ip
# - on_premises_dns_ips
# - ad_domain_name
# - Instance sizes (if needed)
```

### 4. Deploy Development Environment

```bash
# Push to develop branch to trigger deployment
git checkout develop
git add .
git commit -m "Initial development environment configuration"
git push origin develop
```

**Monitor Deployment:**
1. Check GitHub Actions workflow execution
2. Monitor Terraform Cloud workspace for plan/apply status
3. Verify resources in AWS Console

### 5. Test Development Environment

```bash
# Get deployment outputs
terraform output -raw load_balancer_dns_name
terraform output -raw bastion_host_public_ip

# Test application access
curl -I http://$(terraform output -raw load_balancer_dns_name)/health

# Test bastion host connectivity
ssh Administrator@$(terraform output -raw bastion_host_public_ip)
```

### 6. Deploy Production Environment

```bash
# Create pull request from develop to main
git checkout main
git merge develop
git push origin main
```

**Production Deployment Checklist:**
- [ ] Code review completed
- [ ] Security scan passed
- [ ] Cost estimate reviewed
- [ ] Deployment time scheduled
- [ ] Stakeholders notified
- [ ] Rollback plan prepared

### 7. Post-Deployment Verification

#### Infrastructure Verification
```bash
# Check all resources are healthy
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# Check RDS status
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw db_instance_identifier)

# Check FSx status
aws fsx describe-file-systems --file-system-ids $(terraform output -raw fsx_id)
```

#### Application Verification
1. **Load Balancer Health:** Access application via ALB DNS name
2. **Database Connectivity:** Verify application can connect to RDS
3. **File System Access:** Confirm FSx is mounted and accessible
4. **Active Directory:** Test domain join and authentication
5. **Monitoring:** Check CloudWatch dashboards and alarms

#### Security Verification
1. **Network Security:** Verify security groups and NACLs
2. **Encryption:** Confirm all data is encrypted at rest and in transit
3. **Access Controls:** Test IAM roles and permissions
4. **VPN Connectivity:** Verify on-premises access works

## Environment Management

### Updating Infrastructure

#### Development Updates
```bash
# Make changes to Terraform code
git checkout develop
# Edit files
git add .
git commit -m "Update infrastructure configuration"
git push origin develop
```

#### Production Updates
```bash
# Create feature branch
git checkout -b feature/update-infrastructure
# Make changes
git add .
git commit -m "Update production infrastructure"
git push origin feature/update-infrastructure

# Create pull request
# After review and approval, merge to main
```

### Scaling Operations

#### Scale Up Application Servers
```hcl
# Update environments/prod/terraform.tfvars
app_instance_type    = "m5.2xlarge"  # Upgrade from m5.xlarge
app_desired_capacity = 4             # Increase from 2
app_max_size         = 6             # Increase from 4
```

#### Scale Up Database
```hcl
# Update environments/prod/terraform.tfvars
db_instance_class        = "db.m5.2xlarge"  # Upgrade from db.m5.xlarge
db_max_allocated_storage = 2000             # Increase storage limit
```

### Backup and Recovery

#### Manual Backup Creation
```bash
# Create RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier $(terraform output -raw db_instance_identifier) \
  --db-snapshot-identifier cortex-emr-manual-$(date +%Y%m%d%H%M)

# Create FSx backup
aws fsx create-backup \
  --file-system-id $(terraform output -raw fsx_id) \
  --tags Key=Type,Value=Manual
```

#### Recovery Testing
```bash
# Test RDS point-in-time recovery
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier $(terraform output -raw db_instance_identifier) \
  --target-db-instance-identifier cortex-emr-test-restore \
  --restore-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)
```

## Monitoring and Maintenance

### Daily Checks
- [ ] Check CloudWatch dashboard for system health
- [ ] Review any CloudWatch alarms
- [ ] Monitor application logs for errors
- [ ] Verify backup completion
- [ ] Check storage utilization

### Weekly Checks
- [ ] Review cost reports
- [ ] Check for security updates
- [ ] Review access logs
- [ ] Test disaster recovery procedures
- [ ] Update documentation

### Monthly Checks
- [ ] Review and update security groups
- [ ] Analyze performance metrics
- [ ] Review and optimize costs
- [ ] Update instance types if needed
- [ ] Test full backup and restore

## Troubleshooting Common Issues

### Application Not Accessible
```bash
# Check load balancer health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# Check security groups
aws ec2 describe-security-groups --group-ids $(terraform output -raw application_security_group_id)

# Check application logs
aws logs get-log-events --log-group-name "/aws/ec2/cortex-emr/tomcat" --log-stream-name "latest"
```

### Database Connection Issues
```bash
# Check database status
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw db_instance_identifier)

# Check database logs
aws logs describe-log-streams --log-group-name "/aws/rds/instance/$(terraform output -raw db_instance_identifier)/error"

# Test connectivity from application server
# (Connect to bastion host, then to app server)
telnet $(terraform output -raw db_endpoint) 3306
```

### File System Access Issues
```bash
# Check FSx status
aws fsx describe-file-systems --file-system-ids $(terraform output -raw fsx_id)

# Check Active Directory connectivity
# From Windows server:
# Test-ComputerSecureChannel -Verbose
# Get-ADDomain
```

### Performance Issues
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw load_balancer_arn_suffix)
```

## Security Best Practices

### Regular Security Tasks
1. **Rotate Passwords:** Change RDS and AD passwords quarterly
2. **Update AMIs:** Use latest Windows Server AMIs monthly
3. **Security Patches:** Apply patches during maintenance windows
4. **Access Review:** Review IAM permissions and security groups quarterly
5. **Penetration Testing:** Conduct annual security assessments

### Compliance Monitoring
1. **Use AWS Config** for compliance monitoring
2. **Enable CloudTrail** for audit logging
3. **Regular vulnerability scans** using AWS Inspector
4. **Monitor with GuardDuty** for threat detection

## Cost Optimization

### Current Cost Estimate
- **Monthly Cost:** ~$824 USD
- **Annual Cost:** ~$9,888 USD (with reserved instances)

### Cost Optimization Strategies
1. **Reserved Instances:** Already included for production servers
2. **Right-sizing:** Monitor and adjust instance sizes
3. **Storage Optimization:** Use lifecycle policies for S3
4. **Schedule Development:** Turn off dev environment when not needed
5. **Monitor Usage:** Regular cost analysis and optimization

### Development Environment Scheduling
```bash
# Script to stop dev environment (save costs)
./scripts/stop-dev-environment.sh

# Script to start dev environment
./scripts/start-dev-environment.sh
```