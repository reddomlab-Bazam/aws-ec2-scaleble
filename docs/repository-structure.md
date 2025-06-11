# Cortex EMR Internal Infrastructure - Repository Structure

## 📁 Repository Organization

```
cortex-emr-internal-infrastructure/
├── .github/
│   ├── workflows/
│   │   ├── terraform-plan.yml
│   │   ├── terraform-apply.yml
│   │   └── security-scan.yml
│   └── ISSUE_TEMPLATE/
│       └── deployment-request.md
├── docs/
│   ├── README.md
│   ├── deployment-guide.md
│   ├── customer-onboarding.md
│   └── troubleshooting.md
├── environments/
│   └── template/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── modules/
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── security/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── compute/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── user-data/
│   │   │   ├── app-server.ps1
│   │   │   ├── integration-server.ps1
│   │   │   └── bastion-server.ps1
│   │   └── README.md
│   ├── database/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── storage/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── monitoring/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── adhics-compliance/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── entra-ad-integration/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
├── scripts/
│   ├── customer-setup/
│   │   ├── create-workspace.sh
│   │   ├── configure-variables.sh
│   │   └── deploy-customer.sh
│   ├── terraform-cloud/
│   │   ├── workspace-template.json
│   │   └── variable-sets.json
│   └── utilities/
│       ├── health-check.sh
│       ├── backup.sh
│       └── troubleshoot.sh
├── config/
│   ├── terraform-cloud/
│   │   ├── workspace-settings.tf
│   │   └── variable-definitions.tf
│   └── customers/
│       ├── customer-template.tfvars
│       └── README.md
├── .gitignore
├── .terraform-version
├── README.md
└── LICENSE
```

## 🏗️ Architecture for Internal Access

### Network Flow
```
Internal Staff (Entra AD)
    ↓
FortiGate VPN Client
    ↓
FortiGate Firewall/VPN Gateway
    ↓
AWS Site-to-Site VPN
    ↓
Private Subnets (Internal ALB)
    ↓
Auto-Scaling Application Servers
    ↓
Private Database & Storage
```

### Key Changes for Internal Access
- **No Public Internet Access**: All resources in private subnets
- **Internal Load Balancer**: ALB only accessible via VPN
- **Entra AD Connect**: Azure AD integration for single sign-on
- **FortiGate VPN**: Secure tunnel for internal staff access
- **Private DNS**: Internal Route 53 hosted zone

## 📋 Customer Deployment Process

### 1. Repository Setup
```bash
# Clone template for new customer
git clone https://github.com/your-org/cortex-emr-internal-infrastructure.git
cd cortex-emr-internal-infrastructure

# Create customer-specific branch
git checkout -b customer-[customer-name]
```

### 2. Terraform Cloud Workspace Creation
```bash
# Run customer setup script
./scripts/customer-setup/create-workspace.sh [customer-name] [aws-region]

# Configure customer variables
./scripts/customer-setup/configure-variables.sh [customer-name]
```

### 3. Variable Configuration
```bash
# Copy template and customize
cp config/customers/customer-template.tfvars ./[customer-name].tfvars

# Edit customer-specific values
vi [customer-name].tfvars
```

### 4. Deployment
```bash
# Deploy infrastructure
./scripts/customer-setup/deploy-customer.sh [customer-name]
```

## 🔄 Reusable Components

### Customer-Agnostic Modules
- All infrastructure modules are completely reusable
- Customer-specific configuration only in variables
- Standardized naming conventions with customer prefix
- Consistent security and compliance across all deployments

### Variable-Driven Configuration
- Network ranges automatically calculated
- Resource sizing based on customer requirements
- Regional deployment options
- Feature toggles for optional components

This structure ensures each customer gets a production-ready, ADHICS-compliant infrastructure while maintaining consistency and reducing deployment time.