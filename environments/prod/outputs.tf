# environments/prod/outputs.tf

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.load_balancer_dns_name
}

output "application_url" {
  description = "URL to access the Cortex EMR application"
  value       = "https://${aws_route53_record.emr.fqdn}"
}

output "bastion_host_public_ip" {
  description = "Public IP address of the bastion host"
  value       = module.compute.bastion_host_public_ip
}

output "db_endpoint" {
  description = "RDS database endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = module.database.db_instance_identifier
}

output "fsx_dns_name" {
  description = "FSx file system DNS name"
  value       = module.storage.fsx_dns_name
}

output "fsx_id" {
  description = "FSx file system ID"
  value       = module.storage.fsx_id
}

output "integration_server_private_ip" {
  description = "Private IP of the integration server"
  value       = module.compute.integration_server_private_ip
}

output "integration_nlb_dns_name" {
  description = "DNS name of the Integration Network Load Balancer"
  value       = module.compute.integration_nlb_dns_name
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = module.monitoring.sns_topic_arn
}

output "kms_key_id" {
  description = "KMS key ID for encryption"
  value       = module.security.kms_key_id
}

output "target_group_arn" {
  description = "Application Load Balancer target group ARN"
  value       = module.compute.target_group_arn
}

output "auto_scaling_group_names" {
  description = "Auto Scaling Group names"
  value       = module.compute.auto_scaling_group_names
}

output "vpn_connection_id" {
  description = "VPN connection ID"
  value       = module.networking.vpn_connection_id
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "ssl_certificate_arn" {
  description = "SSL certificate ARN"
  value       = aws_acm_certificate.main.arn
}

output "s3_bucket_name" {
  description = "S3 storage bucket name"
  value       = module.storage.s3_bucket_name
}

# Connection information for administrators
output "connection_info" {
  description = "Connection information for system administration"
  value = {
    application_url    = "https://${aws_route53_record.emr.fqdn}"
    bastion_rdp       = "${module.compute.bastion_host_public_ip}:3389"
    dashboard_url     = module.monitoring.dashboard_url
    vpn_status        = "Check AWS Console for VPN connection status"
  }
  sensitive = false
}

# Database connection information (sensitive)
output "database_connection" {
  description = "Database connection information"
  value = {
    endpoint = module.database.db_endpoint
    port     = module.database.db_port
    database = module.database.db_name
    username = module.database.db_username
  }
  sensitive = true
}

# environments/dev/outputs.tf

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.load_balancer_dns_name
}

output "application_url" {
  description = "URL to access the Cortex EMR application"
  value       = "http://${module.compute.load_balancer_dns_name}"
}

output "bastion_host_public_ip" {
  description = "Public IP address of the bastion host"
  value       = module.compute.bastion_host_public_ip
}

output "db_endpoint" {
  description = "RDS database endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = module.database.db_instance_identifier
}

output "fsx_dns_name" {
  description = "FSx file system DNS name"
  value       = var.enable_active_directory ? module.storage.fsx_dns_name : "Not configured (AD disabled)"
}

output "integration_server_private_ip" {
  description = "Private IP of the integration server"
  value       = module.compute.integration_server_private_ip
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}

output "target_group_arn" {
  description = "Application Load Balancer target group ARN"
  value       = module.compute.target_group_arn
}

# Development specific outputs
output "cost_estimate" {
  description = "Estimated monthly cost for development environment"
  value       = "Approximately $200-300 USD/month"
}

output "dev_notes" {
  description = "Important notes for development environment"
  value = {
    single_az_deployment = "Database and FSx are deployed in single AZ for cost savings"
    smaller_instances    = "Using smaller instance types for cost optimization"
    active_directory     = var.enable_active_directory ? "Enabled" : "Disabled (SimpleAD used when enabled)"
    ssl_certificate      = var.enable_ssl ? "Enabled" : "Disabled (HTTP only)"
    backup_retention     = "7 days (reduced from production 30 days)"
  }
}

---

# scripts/deploy.sh
#!/bin/bash

# Cortex EMR Deployment Script
# Usage: ./scripts/deploy.sh [environment] [action]
# Example: ./scripts/deploy.sh dev plan
#          ./scripts/deploy.sh prod apply

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENTS=("dev" "prod")
ACTIONS=("plan" "apply" "destroy" "output" "refresh")

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 <environment> <action>"
    echo ""
    echo "Environments: ${ENVIRONMENTS[*]}"
    echo "Actions: ${ACTIONS[*]}"
    echo ""
    echo "Examples:"
    echo "  $0 dev plan     - Plan development environment"
    echo "  $0 prod apply   - Apply production environment"
    echo "  $0 dev output   - Show development outputs"
    exit 1
}

validate_environment() {
    local env=$1
    for valid_env in "${ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    return 1
}

validate_action() {
    local action=$1
    for valid_action in "${ACTIONS[@]}"; do
        if [[ "$action" == "$valid_action" ]]; then
            return 0
        fi
    done
    return 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed or not in PATH"
        exit 1
    fi
    
    # Check if aws cli is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check if in correct directory
    if [[ ! -d "environments" ]]; then
        log_error "Please run this script from the project root directory"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

terraform_init() {
    local env=$1
    log_info "Initializing Terraform for $env environment..."
    
    cd "environments/$env"
    terraform init
    cd - > /dev/null
    
    log_success "Terraform initialized for $env"
}

terraform_plan() {
    local env=$1
    log_info "Planning Terraform deployment for $env environment..."
    
    cd "environments/$env"
    terraform plan -detailed-exitcode
    local exit_code=$?
    cd - > /dev/null
    
    case $exit_code in
        0)
            log_success "No changes required for $env"
            ;;
        1)
            log_error "Terraform plan failed for $env"
            exit 1
            ;;
        2)
            log_warning "Changes detected for $env environment"
            ;;
    esac
    
    return $exit_code
}

terraform_apply() {
    local env=$1
    log_info "Applying Terraform configuration for $env environment..."
    
    if [[ "$env" == "prod" ]]; then
        log_warning "You are about to apply changes to PRODUCTION environment!"
        read -p "Type 'yes' to continue: " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    cd "environments/$env"
    terraform apply -auto-approve
    cd - > /dev/null
    
    log_success "Terraform apply completed for $env"
}

terraform_destroy() {
    local env=$1
    log_warning "You are about to DESTROY the $env environment!"
    log_warning "This action cannot be undone!"
    
    read -p "Type 'DESTROY' to confirm: " confirm
    if [[ "$confirm" != "DESTROY" ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    cd "environments/$env"
    terraform destroy -auto-approve
    cd - > /dev/null
    
    log_success "Environment $env destroyed"
}

terraform_output() {
    local env=$1
    log_info "Getting outputs for $env environment..."
    
    cd "environments/$env"
    terraform output
    cd - > /dev/null
}

terraform_refresh() {
    local env=$1
    log_info "Refreshing Terraform state for $env environment..."
    
    cd "environments/$env"
    terraform refresh
    cd - > /dev/null
    
    log_success "State refreshed for $env"
}

show_connection_info() {
    local env=$1
    log_info "Connection information for $env environment:"
    
    cd "environments/$env"
    echo ""
    echo "Application URL: $(terraform output -raw application_url 2>/dev/null || echo 'Not available')"
    echo "Bastion Host IP: $(terraform output -raw bastion_host_public_ip 2>/dev/null || echo 'Not available')"
    echo "Dashboard URL: $(terraform output -raw dashboard_url 2>/dev/null || echo 'Not available')"
    cd - > /dev/null
}

# Main script
main() {
    if [[ $# -ne 2 ]]; then
        usage
    fi
    
    local environment=$1
    local action=$2
    
    if ! validate_environment "$environment"; then
        log_error "Invalid environment: $environment"
        usage
    fi
    
    if ! validate_action "$action"; then
        log_error "Invalid action: $action"
        usage
    fi
    
    check_prerequisites
    terraform_init "$environment"
    
    case $action in
        plan)
            terraform_plan "$environment"
            ;;
        apply)
            terraform_plan "$environment"
            terraform_apply "$environment"
            show_connection_info "$environment"
            ;;
        destroy)
            terraform_destroy "$environment"
            ;;
        output)
            terraform_output "$environment"
            show_connection_info "$environment"
            ;;
        refresh)
            terraform_refresh "$environment"
            ;;
    esac
}

# Run main function
main "$@"

---

# scripts/health-check.sh
#!/bin/bash

# Cortex EMR Health Check Script
# Usage: ./scripts/health-check.sh [environment]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_load_balancer() {
    local env=$1
    log_info "Checking Application Load Balancer health..."
    
    cd "environments/$env"
    local alb_dns=$(terraform output -raw load_balancer_dns_name 2>/dev/null)
    local target_group_arn=$(terraform output -raw target_group_arn 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$alb_dns" ]]; then
        # Check ALB endpoint
        if curl -s -o /dev/null -w "%{http_code}" "http://$alb_dns/health" | grep -q "200"; then
            log_success "Load Balancer health check passed"
        else
            log_warning "Load Balancer health check failed"
        fi
        
        # Check target health
        if [[ -n "$target_group_arn" ]]; then
            local healthy_targets=$(aws elbv2 describe-target-health --target-group-arn "$target_group_arn" --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' --output text | wc -l)
            log_info "Healthy targets: $healthy_targets"
        fi
    else
        log_error "Could not retrieve Load Balancer DNS name"
    fi
}

check_database() {
    local env=$1
    log_info "Checking RDS database status..."
    
    cd "environments/$env"
    local db_identifier=$(terraform output -raw db_instance_identifier 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$db_identifier" ]]; then
        local db_status=$(aws rds describe-db-instances --db-instance-identifier "$db_identifier" --query 'DBInstances[0].DBInstanceStatus' --output text)
        
        if [[ "$db_status" == "available" ]]; then
            log_success "Database is available"
        else
            log_warning "Database status: $db_status"
        fi
    else
        log_error "Could not retrieve database identifier"
    fi
}

check_file_system() {
    local env=$1
    log_info "Checking FSx file system status..."
    
    cd "environments/$env"
    local fsx_id=$(terraform output -raw fsx_id 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$fsx_id" && "$fsx_id" != "Not configured"* ]]; then
        local fsx_status=$(aws fsx describe-file-systems --file-system-ids "$fsx_id" --query 'FileSystems[0].Lifecycle' --output text)
        
        if [[ "$fsx_status" == "AVAILABLE" ]]; then
            log_success "FSx file system is available"
        else
            log_warning "FSx file system status: $fsx_status"
        fi
    else
        log_info "FSx file system not configured or not available"
    fi
}

check_auto_scaling() {
    local env=$1
    log_info "Checking Auto Scaling Groups..."
    
    cd "environments/$env"
    local asg_names=$(terraform output -json auto_scaling_group_names 2>/dev/null | jq -r '.[]' 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$asg_names" ]]; then
        for asg_name in $asg_names; do
            local asg_info=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[?LifecycleState==`InService`]|length([0])]' --output text)
            local desired=$(echo "$asg_info" | cut -f1)
            local healthy=$(echo "$asg_info" | cut -f2)
            
            if [[ "$desired" == "$healthy" ]]; then
                log_success "ASG $asg_name: $healthy/$desired instances healthy"
            else
                log_warning "ASG $asg_name: $healthy/$desired instances healthy"
            fi
        done
    else
        log_warning "Could not retrieve Auto Scaling Group information"
    fi
}

check_cloudwatch_alarms() {
    local env=$1
    log_info "Checking CloudWatch alarms..."
    
    local alarm_count=$(aws cloudwatch describe-alarms --alarm-name-prefix "cortex-emr-$env" --state-value ALARM --query 'MetricAlarms | length(@)')
    
    if [[ "$alarm_count" == "0" ]]; then
        log_success "No active alarms"
    else
        log_warning "$alarm_count active alarms found"
        aws cloudwatch describe-alarms --alarm-name-prefix "cortex-emr-$env" --state-value ALARM --query 'MetricAlarms[*].[AlarmName,StateReason]' --output table
    fi
}

check_vpn_connection() {
    local env=$1
    log_info "Checking VPN connection..."
    
    cd "environments/$env"
    local vpn_id=$(terraform output -raw vpn_connection_id 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$vpn_id" ]]; then
        local vpn_state=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_id" --query 'VpnConnections[0].State' --output text)
        local tunnel1_state=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_id" --query 'VpnConnections[0].VgwTelemetry[0].Status' --output text)
        local tunnel2_state=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_id" --query 'VpnConnections[0].VgwTelemetry[1].Status' --output text)
        
        log_info "VPN connection state: $vpn_state"
        log_info "Tunnel 1 state: $tunnel1_state"
        log_info "Tunnel 2 state: $tunnel2_state"
        
        if [[ "$tunnel1_state" == "UP" || "$tunnel2_state" == "UP" ]]; then
            log_success "At least one VPN tunnel is up"
        else
            log_warning "No VPN tunnels are up"
        fi
    else
        log_info "VPN connection not configured"
    fi
}

main() {
    local environment=${1:-"dev"}
    
    if [[ ! -d "environments/$environment" ]]; then
        log_error "Environment '$environment' does not exist"
        exit 1
    fi
    
    log_info "Running health check for $environment environment..."
    echo ""
    
    check_load_balancer "$environment"
    check_database "$environment"
    check_file_system "$environment"
    check_auto_scaling "$environment"
    check_cloudwatch_alarms "$environment"
    check_vpn_connection "$environment"
    
    echo ""
    log_info "Health check completed for $environment environment"
}

main "$@"

---

# scripts/backup.sh
#!/bin/bash

# Cortex EMR Backup Script
# Creates manual snapshots and backups of critical resources

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

create_rds_snapshot() {
    local env=$1
    local timestamp=$(date +%Y%m%d%H%M)
    
    cd "environments/$env"
    local db_identifier=$(terraform output -raw db_instance_identifier 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$db_identifier" ]]; then
        local snapshot_id="cortex-emr-$env-manual-$timestamp"
        
        log_info "Creating RDS snapshot: $snapshot_id"
        aws rds create-db-snapshot \
            --db-instance-identifier "$db_identifier" \
            --db-snapshot-identifier "$snapshot_id" \
            --tags Key=Environment,Value="$env" Key=Type,Value=Manual Key=CreatedBy,Value=Script
        
        log_success "RDS snapshot creation initiated: $snapshot_id"
    fi
}

create_fsx_backup() {
    local env=$1
    local timestamp=$(date +%Y%m%d%H%M)
    
    cd "environments/$env"
    local fsx_id=$(terraform output -raw fsx_id 2>/dev/null)
    cd - > /dev/null
    
    if [[ -n "$fsx_id" && "$fsx_id" != "Not configured"* ]]; then
        log_info "Creating FSx backup for file system: $fsx_id"
        aws fsx create-backup \
            --file-system-id "$fsx_id" \
            --tags Key=Environment,Value="$env" Key=Type,Value=Manual Key=CreatedBy,Value=Script
        
        log_success "FSx backup creation initiated"
    fi
}

create_ebs_snapshots() {
    local env=$1
    local timestamp=$(date +%Y%m%d%H%M)
    
    log_info "Creating EBS snapshots for $env environment"
    
    # Find all EBS volumes with the environment tag
    local volume_ids=$(aws ec2 describe-volumes \
        --filters "Name=tag:Environment,Values=$env" \
        --query 'Volumes[*].VolumeId' \
        --output text)
    
    for volume_id in $volume_ids; do
        log_info "Creating snapshot for volume: $volume_id"
        aws ec2 create-snapshot \
            --volume-id "$volume_id" \
            --description "Manual snapshot for cortex-emr-$env-$timestamp" \
            --tag-specifications "ResourceType=snapshot,Tags=[{Key=Environment,Value=$env},{Key=Type,Value=Manual},{Key=CreatedBy,Value=Script}]"
    done
    
    log_success "EBS snapshot creation initiated for all volumes"
}

main() {
    local environment=${1:-"prod"}
    
    if [[ ! -d "environments/$environment" ]]; then
        echo "Environment '$environment' does not exist"
        exit 1
    fi
    
    log_info "Creating manual backups for $environment environment..."
    
    create_rds_snapshot "$environment"
    create_fsx_backup "$environment"
    create_ebs_snapshots "$environment"
    
    log_success "All backup operations initiated for $environment environment"
    log_info "Check AWS Console to monitor backup progress"
}

main "$@"