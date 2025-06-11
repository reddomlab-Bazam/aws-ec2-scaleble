#!/bin/bash
# scripts/customer-setup/create-workspace.sh
# Script to create Terraform Cloud workspace for new customer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
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

# Usage function
usage() {
    echo "Usage: $0 <customer-code> <aws-region> [environment]"
    echo ""
    echo "Arguments:"
    echo "  customer-code   Short customer identifier (3-8 chars, alphanumeric)"
    echo "  aws-region      AWS region for deployment (default: me-central-1)"
    echo "  environment     Environment name (default: prod)"
    echo ""
    echo "Examples:"
    echo "  $0 alnoor me-central-1 prod"
    echo "  $0 emirates me-central-1 test"
    echo ""
    echo "Prerequisites:"
    echo "  - TFE_TOKEN environment variable set with Terraform Cloud API token"
    echo "  - jq installed for JSON processing"
    echo "  - curl installed for API calls"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [[ -z "$TFE_TOKEN" ]]; then
        log_error "TFE_TOKEN environment variable not set"
        log_info "Get your token from: https://app.terraform.io/app/settings/tokens"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq to continue."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl to continue."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Validate customer code
validate_customer_code() {
    local customer_code=$1
    
    if [[ ! $customer_code =~ ^[a-z0-9]{3,8}$ ]]; then
        log_error "Customer code must be 3-8 characters, lowercase alphanumeric only"
        exit 1
    fi
}

# Create Terraform Cloud workspace
create_workspace() {
    local customer_code=$1
    local aws_region=$2
    local environment=$3
    local workspace_name="${customer_code}-${environment}"
    local org_name="${TFC_ORGANIZATION:-your-healthcare-org}"
    
    log_info "Creating Terraform Cloud workspace: $workspace_name"
    
    # Workspace payload
    local workspace_payload=$(cat <<EOF
{
  "data": {
    "attributes": {
      "name": "$workspace_name",
      "description": "Cortex EMR infrastructure for $customer_code ($environment)",
      "execution-mode": "remote",
      "auto-apply": false,
      "queue-all-runs": false,
      "terraform-version": "1.6.0",
      "working-directory": "environments/template",
      "file-triggers-enabled": true,
      "trigger-prefixes": ["environments/template", "modules/"],
      "vcs-repo": {
        "identifier": "${GITHUB_REPO:-your-org/cortex-emr-internal-infrastructure}",
        "branch": "${GITHUB_BRANCH:-main}",
        "oauth-token-id": "$VCS_OAUTH_TOKEN"
      },
      "tags": [
        "customer:$customer_code",
        "environment:$environment",
        "region:$aws_region",
        "healthcare",
        "emr",
        "adhics-compliant"
      ]
    },
    "type": "workspaces"
  }
}
EOF
)
    
    # Create workspace
    local response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        --header "Content-Type: application/vnd.api+json" \
        --request POST \
        --data "$workspace_payload" \
        "https://app.terraform.io/api/v2/organizations/$org_name/workspaces")
    
    # Check if workspace was created successfully
    local workspace_id=$(echo "$response" | jq -r '.data.id // empty')
    
    if [[ -z "$workspace_id" ]]; then
        log_error "Failed to create workspace"
        echo "$response" | jq '.'
        exit 1
    fi
    
    log_success "Workspace created successfully: $workspace_name (ID: $workspace_id)"
    echo "$workspace_id" > "/tmp/${workspace_name}_workspace_id"
    
    return 0
}

# Configure workspace variables
configure_workspace_variables() {
    local customer_code=$1
    local aws_region=$2
    local environment=$3
    local workspace_name="${customer_code}-${environment}"
    local workspace_id=$(cat "/tmp/${workspace_name}_workspace_id")
    
    log_info "Configuring workspace variables..."
    
    # Define workspace variables
    declare -A workspace_vars=(
        ["customer_code"]="$customer_code"
        ["environment"]="$environment"
        ["aws_region"]="$aws_region"
        ["terraform_cloud_workspace"]="$workspace_name"
    )
    
    # Environment variables (sensitive)
    declare -A env_vars=(
        ["AWS_ACCESS_KEY_ID"]=""
        ["AWS_SECRET_ACCESS_KEY"]=""
        ["TF_VAR_vpn_shared_secret"]=""
        ["TF_VAR_entra_client_secret"]=""
    )
    
    # Create Terraform variables
    for var_name in "${!workspace_vars[@]}"; do
        local var_value="${workspace_vars[$var_name]}"
        
        local var_payload=$(cat <<EOF
{
  "data": {
    "type": "vars",
    "attributes": {
      "key": "$var_name",
      "value": "$var_value",
      "description": "Auto-generated variable for $var_name",
      "category": "terraform",
      "hcl": false,
      "sensitive": false
    }
  }
}
EOF
)
        
        curl -s \
            --header "Authorization: Bearer $TFE_TOKEN" \
            --header "Content-Type: application/vnd.api+json" \
            --request POST \
            --data "$var_payload" \
            "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars" > /dev/null
        
        log_info "Created variable: $var_name"
    done
    
    # Create environment variables (placeholders - customer will need to set these)
    for var_name in "${!env_vars[@]}"; do
        local var_payload=$(cat <<EOF
{
  "data": {
    "type": "vars",
    "attributes": {
      "key": "$var_name",
      "value": "PLEASE_SET_THIS_VALUE",
      "description": "Environment variable - customer must set this value",
      "category": "env",
      "hcl": false,
      "sensitive": true
    }
  }
}
EOF
)
        
        curl -s \
            --header "Authorization: Bearer $TFE_TOKEN" \
            --header "Content-Type: application/vnd.api+json" \
            --request POST \
            --data "$var_payload" \
            "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars" > /dev/null
        
        log_info "Created environment variable: $var_name (needs customer input)"
    done
    
    log_success "Workspace variables configured"
}

# Generate customer configuration template
generate_customer_config() {
    local customer_code=$1
    local aws_region=$2
    local environment=$3
    local config_file="customers/${customer_code}-${environment}.tfvars"
    
    log_info "Generating customer configuration template: $config_file"
    
    # Create customers directory if it doesn't exist
    mkdir -p "customers"
    
    # Copy template and customize
    cp "config/customers/customer-template.tfvars" "$config_file"
    
    # Replace template values
    sed -i.bak \
        -e "s/customer_code = \"alnoor\"/customer_code = \"$customer_code\"/" \
        -e "s/aws_region = \"me-central-1\"/aws_region = \"$aws_region\"/" \
        -e "s/environment = \"prod\"/environment = \"$environment\"/" \
        -e "s/terraform_cloud_workspace = \"alnoor-prod\"/terraform_cloud_workspace = \"${customer_code}-${environment}\"/" \
        -e "s/vpc_cidr = \"10.100.0.0\/16\"/vpc_cidr = \"10.$((100 + RANDOM % 155)).0.0\/16\"/" \
        "$config_file"
    
    # Remove backup file
    rm "${config_file}.bak"
    
    log_success "Customer configuration generated: $config_file"
    log_warning "Please review and customize the configuration file before deployment"
}

# Create deployment instructions
create_deployment_instructions() {
    local customer_code=$1
    local aws_region=$2
    local environment=$3
    local workspace_name="${customer_code}-${environment}"
    local instructions_file="customers/${customer_code}-${environment}-README.md"
    
    log_info "Creating deployment instructions: $instructions_file"
    
    cat > "$instructions_file" <<EOF
# Deployment Instructions for $customer_code ($environment)

## Workspace Information
- **Customer**: $customer_code
- **Environment**: $environment
- **AWS Region**: $aws_region
- **Terraform Cloud Workspace**: $workspace_name

## Pre-Deployment Checklist

### 1. Set Required Environment Variables in Terraform Cloud
Navigate to your workspace: https://app.terraform.io/app/your-org/$workspace_name/variables

Set these **environment variables**:
- \`AWS_ACCESS_KEY_ID\`: AWS access key for the customer account
- \`AWS_SECRET_ACCESS_KEY\`: AWS secret key for the customer account
- \`TF_VAR_vpn_shared_secret\`: Secure VPN shared secret
- \`TF_VAR_entra_client_secret\`: Azure AD application client secret

### 2. Customize Configuration File
Edit \`customers/${customer_code}-${environment}.tfvars\` and update:
- Customer information (name, domain, contact details)
- Network configuration (VPC CIDR, on-premises networks)
- FortiGate VPN settings (public IP, BGP ASN)
- Entra AD configuration (tenant ID, client ID, domain)
- Instance sizes and capacity based on requirements

### 3. Verify Prerequisites
- [ ] Customer's FortiGate firewall configured for VPN
- [ ] Azure AD application created and configured
- [ ] DNS delegation configured (if required)
- [ ] Customer AWS account prepared with appropriate permissions

## Deployment Process

### Phase 1: Planning (Week 1)
1. Review and finalize configuration file
2. Validate network connectivity requirements
3. Coordinate with customer IT team for VPN setup

### Phase 2: Development Deployment (Week 2)
1. Deploy to development environment first
2. Test VPN connectivity
3. Validate Entra AD integration
4. Perform application testing

### Phase 3: Production Deployment (Week 3)
1. Deploy to production environment
2. Migrate customer data (if applicable)
3. Perform user acceptance testing
4. Go-live and monitoring setup

## Quick Deployment Commands

\`\`\`bash
# Configure variables for this customer
./scripts/customer-setup/configure-variables.sh $customer_code $environment

# Deploy infrastructure
./scripts/customer-setup/deploy-customer.sh $customer_code $environment

# Monitor deployment
./scripts/utilities/health-check.sh $customer_code $environment
\`\`\`

## Post-Deployment Tasks
- [ ] DNS configuration
- [ ] User training and documentation
- [ ] Monitoring and alerting validation
- [ ] Backup testing
- [ ] Disaster recovery testing

## Support Contacts
- **Technical Support**: support@yourcompany.com
- **Project Manager**: [Name] - [email]
- **Customer Success**: [Name] - [email]

## Important Notes
- All infrastructure is deployed in UAE region ($aws_region) for data sovereignty
- ADHICS compliance features are enabled by default
- Auto-scaling is configured with conservative thresholds
- All sensitive data is encrypted at rest and in transit

Generated on: $(date)
EOF
    
    log_success "Deployment instructions created: $instructions_file"
}

# Main function
main() {
    # Check arguments
    if [[ $# -lt 2 ]] || [[ $# -gt 3 ]]; then
        usage
    fi
    
    local customer_code=$1
    local aws_region=${2:-"me-central-1"}
    local environment=${3:-"prod"}
    
    # Validate inputs
    validate_customer_code "$customer_code"
    
    # Check prerequisites
    check_prerequisites
    
    log_info "Setting up infrastructure for customer: $customer_code"
    log_info "Environment: $environment"
    log_info "AWS Region: $aws_region"
    
    # Create workspace and configure
    create_workspace "$customer_code" "$aws_region" "$environment"
    configure_workspace_variables "$customer_code" "$aws_region" "$environment"
    
    # Generate customer-specific files
    generate_customer_config "$customer_code" "$aws_region" "$environment"
    create_deployment_instructions "$customer_code" "$aws_region" "$environment"
    
    # Cleanup temporary files
    rm -f "/tmp/${customer_code}-${environment}_workspace_id"
    
    echo ""
    log_success "Customer setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Review and customize: customers/${customer_code}-${environment}.tfvars"
    echo "2. Set environment variables in Terraform Cloud workspace"
    echo "3. Run deployment: ./scripts/customer-setup/deploy-customer.sh $customer_code $environment"
    echo ""
    echo "Terraform Cloud workspace: https://app.terraform.io/app/your-org/${customer_code}-${environment}"
}

# Run main function
main "$@"

---

#!/bin/bash
# scripts/customer-setup/configure-variables.sh
# Script to configure Terraform Cloud variables for customer deployment

set -e

# Colors for output
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

# Usage function
usage() {
    echo "Usage: $0 <customer-code> [environment]"
    echo ""
    echo "Arguments:"
    echo "  customer-code   Customer identifier"
    echo "  environment     Environment name (default: prod)"
    echo ""
    echo "Examples:"
    echo "  $0 alnoor prod"
    echo "  $0 emirates test"
    exit 1
}

# Upload customer tfvars to Terraform Cloud
upload_customer_variables() {
    local customer_code=$1
    local environment=$2
    local workspace_name="${customer_code}-${environment}"
    local config_file="customers/${customer_code}-${environment}.tfvars"
    local org_name="${TFC_ORGANIZATION:-your-healthcare-org}"
    
    log_info "Uploading customer variables to Terraform Cloud..."
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        log_info "Run create-workspace.sh first to generate the template"
        exit 1
    fi
    
    # Get workspace ID
    local workspace_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/organizations/$org_name/workspaces/$workspace_name")
    
    local workspace_id=$(echo "$workspace_response" | jq -r '.data.id // empty')
    
    if [[ -z "$workspace_id" ]]; then
        log_error "Workspace not found: $workspace_name"
        exit 1
    fi
    
    # Parse tfvars file and create variables
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Clean up key and value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"//' | sed 's/"$//')
        
        # Skip if empty
        [[ -z $key ]] && continue
        [[ -z $value ]] && continue
        
        # Determine if variable is sensitive
        local sensitive="false"
        if [[ $key =~ (secret|password|token|key) ]]; then
            sensitive="true"
        fi
        
        # Create variable payload
        local var_payload=$(cat <<EOF
{
  "data": {
    "type": "vars",
    "attributes": {
      "key": "$key",
      "value": "$value",
      "description": "Customer configuration variable",
      "category": "terraform",
      "hcl": false,
      "sensitive": $sensitive
    }
  }
}
EOF
)
        
        # Check if variable exists
        local existing_var=$(curl -s \
            --header "Authorization: Bearer $TFE_TOKEN" \
            "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars" | \
            jq -r ".data[] | select(.attributes.key == \"$key\") | .id // empty")
        
        if [[ -n "$existing_var" ]]; then
            # Update existing variable
            curl -s \
                --header "Authorization: Bearer $TFE_TOKEN" \
                --header "Content-Type: application/vnd.api+json" \
                --request PATCH \
                --data "$var_payload" \
                "https://app.terraform.io/api/v2/vars/$existing_var" > /dev/null
            log_info "Updated variable: $key"
        else
            # Create new variable
            curl -s \
                --header "Authorization: Bearer $TFE_TOKEN" \
                --header "Content-Type: application/vnd.api+json" \
                --request POST \
                --data "$var_payload" \
                "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars" > /dev/null
            log_info "Created variable: $key"
        fi
        
    done < <(grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=' "$config_file")
    
    log_success "Customer variables uploaded successfully"
}

# Validate required environment variables
validate_environment_variables() {
    local customer_code=$1
    local environment=$2
    local workspace_name="${customer_code}-${environment}"
    local org_name="${TFC_ORGANIZATION:-your-healthcare-org}"
    
    log_info "Validating required environment variables..."
    
    # Get workspace ID
    local workspace_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/organizations/$org_name/workspaces/$workspace_name")
    
    local workspace_id=$(echo "$workspace_response" | jq -r '.data.id // empty')
    
    # Get all variables
    local vars_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/workspaces/$workspace_id/vars")
    
    # Check required environment variables
    local required_env_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "TF_VAR_vpn_shared_secret" "TF_VAR_entra_client_secret")
    local missing_vars=()
    
    for var_name in "${required_env_vars[@]}"; do
        local var_value=$(echo "$vars_response" | jq -r ".data[] | select(.attributes.key == \"$var_name\" and .attributes.category == \"env\") | .attributes.value // empty")
        
        if [[ -z "$var_value" ]] || [[ "$var_value" == "PLEASE_SET_THIS_VALUE" ]]; then
            missing_vars+=("$var_name")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_warning "The following environment variables need to be set in Terraform Cloud:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Set these at: https://app.terraform.io/app/$org_name/$workspace_name/variables"
        echo ""
        log_warning "Deployment will fail until these variables are set"
        return 1
    else
        log_success "All required environment variables are configured"
        return 0
    fi
}

# Main function
main() {
    if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
        usage
    fi
    
    local customer_code=$1
    local environment=${2:-"prod"}
    
    if [[ -z "$TFE_TOKEN" ]]; then
        log_error "TFE_TOKEN environment variable not set"
        exit 1
    fi
    
    log_info "Configuring variables for customer: $customer_code ($environment)"
    
    upload_customer_variables "$customer_code" "$environment"
    
    if validate_environment_variables "$customer_code" "$environment"; then
        log_success "Configuration completed successfully!"
        echo ""
        echo "Ready for deployment. Run:"
        echo "  ./scripts/customer-setup/deploy-customer.sh $customer_code $environment"
    else
        log_warning "Configuration completed, but environment variables need to be set"
        echo ""
        echo "After setting environment variables in Terraform Cloud, run:"
        echo "  ./scripts/customer-setup/deploy-customer.sh $customer_code $environment"
    fi
}

# Run main function
main "$@"

---

#!/bin/bash
# scripts/customer-setup/deploy-customer.sh
# Script to deploy customer infrastructure via Terraform Cloud

set -e

# Colors for output
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

usage() {
    echo "Usage: $0 <customer-code> [environment] [auto-apply]"
    echo ""
    echo "Arguments:"
    echo "  customer-code   Customer identifier"
    echo "  environment     Environment name (default: prod)"
    echo "  auto-apply      Auto-apply after plan (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 alnoor prod"
    echo "  $0 emirates test true"
    exit 1
}

# Trigger Terraform Cloud run
trigger_terraform_run() {
    local customer_code=$1
    local environment=$2
    local auto_apply=${3:-false}
    local workspace_name="${customer_code}-${environment}"
    local org_name="${TFC_ORGANIZATION:-your-healthcare-org}"
    
    log_info "Triggering Terraform run for $workspace_name..."
    
    # Get workspace ID
    local workspace_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/organizations/$org_name/workspaces/$workspace_name")
    
    local workspace_id=$(echo "$workspace_response" | jq -r '.data.id // empty')
    
    if [[ -z "$workspace_id" ]]; then
        log_error "Workspace not found: $workspace_name"
        exit 1
    fi
    
    # Create run payload
    local run_payload=$(cat <<EOF
{
  "data": {
    "attributes": {
      "message": "Deployment for customer $customer_code ($environment)",
      "auto-apply": $auto_apply,
      "is-destroy": false
    },
    "type": "runs",
    "relationships": {
      "workspace": {
        "data": {
          "type": "workspaces",
          "id": "$workspace_id"
        }
      }
    }
  }
}
EOF
)
    
    # Trigger run
    local run_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        --header "Content-Type: application/vnd.api+json" \
        --request POST \
        --data "$run_payload" \
        "https://app.terraform.io/api/v2/runs")
    
    local run_id=$(echo "$run_response" | jq -r '.data.id // empty')
    
    if [[ -z "$run_id" ]]; then
        log_error "Failed to trigger run"
        echo "$run_response" | jq '.'
        exit 1
    fi
    
    log_success "Terraform run triggered: $run_id"
    echo "Monitor at: https://app.terraform.io/app/$org_name/$workspace_name/runs/$run_id"
    
    return 0
}

# Monitor run status
monitor_run() {
    local run_id=$1
    local timeout=3600  # 1 hour timeout
    local start_time=$(date +%s)
    
    log_info "Monitoring run status..."
    
    while true; do
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt $timeout ]]; then
            log_warning "Monitoring timeout reached"
            break
        fi
        
        local run_response=$(curl -s \
            --header "Authorization: Bearer $TFE_TOKEN" \
            "https://app.terraform.io/api/v2/runs/$run_id")
        
        local status=$(echo "$run_response" | jq -r '.data.attributes.status // empty')
        local message=$(echo "$run_response" | jq -r '.data.attributes.message // empty')
        
        case $status in
            "planning")
                log_info "Status: Planning..."
                ;;
            "planned")
                log_success "Plan completed successfully"
                log_info "Review the plan and apply if approved"
                break
                ;;
            "applying")
                log_info "Status: Applying..."
                ;;
            "applied")
                log_success "Apply completed successfully!"
                break
                ;;
            "errored")
                log_error "Run failed with error"
                break
                ;;
            "canceled")
                log_warning "Run was canceled"
                break
                ;;
            *)
                log_info "Status: $status"
                ;;
        esac
        
        sleep 30
    done
}

# Get deployment outputs
get_deployment_outputs() {
    local customer_code=$1
    local environment=$2
    local workspace_name="${customer_code}-${environment}"
    local org_name="${TFC_ORGANIZATION:-your-healthcare-org}"
    
    log_info "Retrieving deployment outputs..."
    
    # Get workspace
    local workspace_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/organizations/$org_name/workspaces/$workspace_name")
    
    local workspace_id=$(echo "$workspace_response" | jq -r '.data.id // empty')
    
    # Get current state version
    local state_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/workspaces/$workspace_id/current-state-version")
    
    local state_version_id=$(echo "$state_response" | jq -r '.data.id // empty')
    
    if [[ -z "$state_version_id" ]]; then
        log_warning "No state version found - deployment may not be complete"
        return
    fi
    
    # Get outputs
    local outputs_response=$(curl -s \
        --header "Authorization: Bearer $TFE_TOKEN" \
        "https://app.terraform.io/api/v2/state-versions/$state_version_id/outputs")
    
    echo ""
    log_success "Deployment Outputs:"
    echo "$outputs_response" | jq -r '.data[] | "  \(.attributes.name): \(.attributes.value)"'
    echo ""
}

# Main function
main() {
    if [[ $# -lt 1 ]] || [[ $# -gt 3 ]]; then
        usage
    fi
    
    local customer_code=$1
    local environment=${2:-"prod"}
    local auto_apply=${3:-false}
    
    if [[ -z "$TFE_TOKEN" ]]; then
        log_error "TFE_TOKEN environment variable not set"
        exit 1
    fi
    
    log_info "Starting deployment for customer: $customer_code ($environment)"
    
    if [[ "$auto_apply" == "true" ]]; then
        log_warning "Auto-apply enabled - changes will be applied automatically"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment canceled"
            exit 0
        fi
    fi
    
    # Trigger deployment
    trigger_terraform_run "$customer_code" "$environment" "$auto_apply"
    
    # Monitor if auto-apply is enabled
    if [[ "$auto_apply" == "true" ]]; then
        local run_id=$(cat /tmp/last_run_id 2>/dev/null || echo "")
        if [[ -n "$run_id" ]]; then
            monitor_run "$run_id"
            get_deployment_outputs "$customer_code" "$environment"
        fi
    fi
    
    log_success "Deployment process completed!"
}

# Run main function
main "$@"