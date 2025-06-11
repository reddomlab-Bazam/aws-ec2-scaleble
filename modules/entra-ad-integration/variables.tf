# modules/entra-ad-integration/variables.tf

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "customer_code" {
  description = "Customer code for naming"
  type        = string
}

variable "entra_tenant_id" {
  description = "Azure AD (Entra ID) tenant ID"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.entra_tenant_id))
    error_message = "Entra tenant ID must be a valid GUID."
  }
}

variable "application_redirect_uri" {
  description = "Redirect URI for the EMR application"
  type        = string
  validation {
    condition     = can(regex("^https://", var.application_redirect_uri))
    error_message = "Redirect URI must start with https://."
  }
}

variable "allowed_user_groups" {
  description = "List of Entra AD groups allowed to access the EMR system"
  type        = list(string)
  default     = ["EMR-Users"]
}

variable "security_group_mappings" {
  description = "Mapping of Entra AD groups to EMR application roles"
  type = map(object({
    emr_role    = string
    permissions = list(string)
  }))
  default = {}
}

variable "log_retention_days" {
  description = "Log retention period for authentication logs"
  type        = number
  default     = 90
}

variable "alarm_actions" {
  description = "List of ARNs to notify when authentication alarms trigger"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/entra-ad-integration/outputs.tf

output "application_id" {
  description = "Azure AD application ID"
  value       = azuread_application.emr_app.application_id
}

output "service_principal_id" {
  description = "Azure AD service principal ID"
  value       = azuread_service_principal.emr_app.id
}

output "client_secret_arn" {
  description = "ARN of the AWS secret containing the client secret"
  value       = aws_secretsmanager_secret.entra_client_secret.arn
}

output "configuration_parameter_name" {
  description = "SSM parameter name containing Entra configuration"
  value       = aws_ssm_parameter.entra_config.name
}

output "setup_script_parameter_name" {
  description = "SSM parameter name containing Entra setup script"
  value       = aws_ssm_parameter.entra_setup_script.name
}

output "auth_log_group_name" {
  description = "CloudWatch log group name for authentication logs"
  value       = aws_cloudwatch_log_group.entra_auth_logs.name
}

output "emr_app_config" {
  description = "EMR application configuration for Entra AD"
  value       = local.emr_app_config
  sensitive   = true
}

output "app_roles" {
  description = "Available application roles"
  value       = local.app_role_mapping
}

# modules/entra-ad-integration/scripts/entra-setup.ps1

<powershell>
# Entra AD Integration Setup Script for EMR Application Servers
# This script configures the EMR application server for Azure AD authentication

param(
    [string]$CustomerCode = "${customer_code}",
    [string]$NamePrefix = "${name_prefix}",
    [string]$TenantId = "${tenant_id}",
    [string]$ClientId = "${client_id}",
    [string]$ConfigParameter = "${config_parameter}"
)

# Log all activities
Start-Transcript -Path "C:\temp\entra-setup.log" -Force

try {
    Write-Output "Starting Entra AD integration setup for customer: $CustomerCode"
    
    # Create directories
    New-Item -ItemType Directory -Path "C:\EMR\Config" -Force
    New-Item -ItemType Directory -Path "C:\EMR\Logs" -Force
    New-Item -ItemType Directory -Path "C:\temp" -Force
    
    # Install required PowerShell modules
    Write-Output "Installing required PowerShell modules..."
    
    # Install NuGet provider
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    
    # Install Azure modules
    Install-Module -Name Az.Accounts -Force -Scope AllUsers
    Install-Module -Name Az.KeyVault -Force -Scope AllUsers
    Install-Module -Name AzureAD -Force -Scope AllUsers
    
    # Install AWS PowerShell module for parameter access
    Install-Module -Name AWS.Tools.SimpleSystemsManagement -Force -Scope AllUsers
    Install-Module -Name AWS.Tools.SecretsManager -Force -Scope AllUsers
    
    Write-Output "PowerShell modules installed successfully"
    
    # Get Entra configuration from AWS Systems Manager
    Write-Output "Retrieving Entra configuration from AWS Systems Manager..."
    
    try {
        $EntraConfig = Get-SSMParameter -Name $ConfigParameter -WithDecryption $true | Select-Object -ExpandProperty Value | ConvertFrom-Json
        Write-Output "Configuration retrieved successfully"
    }
    catch {
        Write-Error "Failed to retrieve Entra configuration: $($_.Exception.Message)"
        throw
    }
    
    # Create EMR application configuration file
    Write-Output "Creating EMR application configuration..."
    
    $EmrConfig = @{
        Authentication = @{
            Provider = "EntraID"
            TenantId = $EntraConfig.tenant_id
            ClientId = $EntraConfig.client_id
            Authority = $EntraConfig.authority
            RedirectUri = $EntraConfig.redirect_uri
            Scope = $EntraConfig.scope
        }
        Authorization = @{
            AppRoles = $EntraConfig.app_roles
            GroupMappings = $EntraConfig.group_mappings
        }
        Logging = @{
            Level = "Information"
            Destination = "CloudWatch"
            LogGroup = "/aws/emr/$NamePrefix/entra-auth"
        }
        Session = @{
            Timeout = 28800  # 8 hours
            SlidingExpiration = $true
            RequireHttps = $true
        }
    }
    
    # Save configuration to file
    $ConfigJson = $EmrConfig | ConvertTo-Json -Depth 10
    $ConfigJson | Out-File -FilePath "C:\EMR\Config\entra-config.json" -Encoding UTF8
    
    Write-Output "EMR configuration file created"
    
    # Install and configure IIS with required features
    Write-Output "Configuring IIS for Entra AD authentication..."
    
    # Enable IIS features
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All
    
    # Configure SSL/TLS settings
    Write-Output "Configuring SSL/TLS settings..."
    
    # Disable weak protocols
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -Name "Enabled" -PropertyType DWORD -Value 0 -Force
    
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Name "Enabled" -PropertyType DWORD -Value 0 -Force
    
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "Enabled" -PropertyType DWORD -Value 0 -Force
    
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" -Name "Enabled" -PropertyType DWORD -Value 0 -Force
    
    # Enable TLS 1.2 and 1.3
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Name "Enabled" -PropertyType DWORD -Value 1 -Force
    
    # Install .NET Framework 4.8
    Write-Output "Installing .NET Framework 4.8..."
    $NetFrameworkUrl = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP48-Web.exe"
    $NetFrameworkPath = "C:\temp\NDP48-Web.exe"
    Invoke-WebRequest -Uri $NetFrameworkUrl -OutFile $NetFrameworkPath
    Start-Process -FilePath $NetFrameworkPath -ArgumentList "/quiet" -Wait
    
    # Install ASP.NET Core Hosting Bundle
    Write-Output "Installing ASP.NET Core Hosting Bundle..."
    $AspNetCoreUrl = "https://download.visualstudio.microsoft.com/download/pr/c634db6a-0e55-4e4c-8c72-156cc23d60ce/4dd54bc5ce4e71b7b6e17e0fde9b46be/dotnet-hosting-6.0.25-win.exe"
    $AspNetCorePath = "C:\temp\dotnet-hosting-win.exe"
    Invoke-WebRequest -Uri $AspNetCoreUrl -OutFile $AspNetCorePath
    Start-Process -FilePath $AspNetCorePath -ArgumentList "/quiet" -Wait
    
    # Configure Windows Event Logging for authentication events
    Write-Output "Configuring Windows Event Logging..."
    
    # Create custom event log for EMR authentication
    New-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -ErrorAction SilentlyContinue
    
    # Set up performance counters
    Write-Output "Setting up performance monitoring..."
    
    # Create performance counter categories for EMR
    $CounterPath = "EMR Authentication"
    
    # Install CloudWatch Agent
    Write-Output "Installing CloudWatch Agent..."
    $CloudWatchAgentUrl = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $CloudWatchAgentPath = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $CloudWatchAgentUrl -OutFile $CloudWatchAgentPath
    Start-Process msiexec.exe -Wait -ArgumentList "/i $CloudWatchAgentPath /quiet"
    
    # Configure CloudWatch Agent for authentication logging
    $CloudWatchConfig = @{
        agent = @{
            metrics_collection_interval = 60
        }
        logs = @{
            logs_collected = @{
                windows_events = @{
                    collect_list = @(
                        @{
                            event_name = "EMR-Authentication"
                            event_levels = @("INFORMATION", "WARNING", "ERROR", "CRITICAL")
                            log_group_name = "/aws/emr/$NamePrefix/entra-auth"
                            log_stream_name = "{instance_id}-entra-auth"
                        },
                        @{
                            event_name = "Security"
                            event_levels = @("ERROR", "CRITICAL")
                            log_group_name = "/aws/emr/$NamePrefix/security"
                            log_stream_name = "{instance_id}-security"
                        }
                    )
                }
                files = @{
                    collect_list = @(
                        @{
                            file_path = "C:\EMR\Logs\*.log"
                            log_group_name = "/aws/emr/$NamePrefix/application"
                            log_stream_name = "{instance_id}-application"
                        }
                    )
                }
            }
        }
        metrics = @{
            namespace = "EMR/Authentication"
            metrics_collected = @{
                cpu = @{
                    measurement = @("cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system")
                    metrics_collection_interval = 60
                }
                disk = @{
                    measurement = @("used_percent")
                    metrics_collection_interval = 60
                    resources = @("*")
                }
                mem = @{
                    measurement = @("mem_used_percent")
                    metrics_collection_interval = 60
                }
            }
        }
    }
    
    $CloudWatchConfigJson = $CloudWatchConfig | ConvertTo-Json -Depth 10
    $CloudWatchConfigJson | Out-File -FilePath "C:\temp\cloudwatch-config.json" -Encoding ASCII
    
    # Start CloudWatch Agent with configuration
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\temp\cloudwatch-config.json" -s
    
    Write-Output "CloudWatch Agent configured and started"
    
    # Configure firewall rules for HTTPS
    Write-Output "Configuring firewall rules..."
    New-NetFirewallRule -DisplayName "EMR HTTPS Inbound" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
    New-NetFirewallRule -DisplayName "EMR HTTP Inbound" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
    
    # Create startup script for EMR application
    Write-Output "Creating EMR startup configuration..."
    
    $StartupScript = @"
# EMR Application Startup Script
Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1000 -EntryType Information -Message "EMR Application Starting - Entra AD Integration Enabled"

# Load Entra configuration
`$EntraConfig = Get-Content "C:\EMR\Config\entra-config.json" | ConvertFrom-Json

# Validate configuration
if (-not `$EntraConfig.Authentication.TenantId) {
    Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1001 -EntryType Error -Message "Entra configuration missing TenantId"
    exit 1
}

Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1002 -EntryType Information -Message "EMR Application Started Successfully with Entra AD Integration"
"@
    
    $StartupScript | Out-File -FilePath "C:\EMR\Config\startup.ps1" -Encoding UTF8
    
    # Create scheduled task for startup
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\EMR\Config\startup.ps1"
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "EMR-Startup" -Action $Action -Trigger $Trigger -Principal $Principal
    
    # Test Entra AD connectivity
    Write-Output "Testing Entra AD connectivity..."
    
    try {
        $TestUri = "https://login.microsoftonline.com/$TenantId/v2.0/.well-known/openid_configuration"
        $Response = Invoke-RestMethod -Uri $TestUri -Method Get
        
        if ($Response.issuer) {
            Write-Output "Entra AD connectivity test successful"
            Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1003 -EntryType Information -Message "Entra AD connectivity verified"
        }
        else {
            throw "Invalid response from Entra AD endpoint"
        }
    }
    catch {
        Write-Error "Entra AD connectivity test failed: $($_.Exception.Message)"
        Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1004 -EntryType Error -Message "Entra AD connectivity test failed: $($_.Exception.Message)"
    }
    
    # Create health check endpoint
    Write-Output "Creating health check endpoint..."
    
    $HealthCheckContent = @"
<%@ Page Language="C#" %>
<%@ Import Namespace="System.DirectoryServices" %>
<%@ Import Namespace="System.Configuration" %>
<%
    Response.ContentType = "application/json";
    
    var status = new {
        status = "healthy",
        timestamp = DateTime.UtcNow,
        entra_ad = new {
            configured = true,
            tenant_id = "$TenantId",
            client_id = "$ClientId"
        },
        authentication = new {
            provider = "EntraID",
            ssl_enabled = Request.IsSecureConnection
        }
    };
    
    Response.Write(Newtonsoft.Json.JsonConvert.SerializeObject(status, Newtonsoft.Json.Formatting.Indented));
%>
"@
    
    # Ensure wwwroot directory exists
    $WebRoot = "C:\inetpub\wwwroot"
    if (-not (Test-Path $WebRoot)) {
        New-Item -ItemType Directory -Path $WebRoot -Force
    }
    
    $HealthCheckContent | Out-File -FilePath "$WebRoot\health.aspx" -Encoding UTF8
    
    # Final configuration validation
    Write-Output "Performing final configuration validation..."
    
    $ValidationResults = @{
        EntraConfigExists = Test-Path "C:\EMR\Config\entra-config.json"
        CloudWatchInstalled = Test-Path "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.exe"
        IISInstalled = (Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole).State -eq "Enabled"
        HealthCheckExists = Test-Path "$WebRoot\health.aspx"
        EventLogCreated = [System.Diagnostics.EventLog]::Exists("EMR-Authentication")
    }
    
    Write-Output "Validation Results:"
    $ValidationResults | ConvertTo-Json -Depth 2 | Write-Output
    
    # Log successful completion
    Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1005 -EntryType Information -Message "Entra AD integration setup completed successfully"
    
    Write-Output "Entra AD integration setup completed successfully!"
    
}
catch {
    Write-Error "Error during Entra AD setup: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    
    # Log error to event log if possible
    try {
        Write-EventLog -LogName "EMR-Authentication" -Source "EntraAuth" -EventID 1006 -EntryType Error -Message "Entra AD setup failed: $($_.Exception.Message)"
    }
    catch {
        # Event log might not be created yet
        Write-Output "Could not write to event log"
    }
    
    exit 1
}
finally {
    Stop-Transcript
}
</powershell>

# modules/entra-ad-integration/README.md

# Entra AD Integration Module

This module configures Azure Active Directory (Entra ID) integration for the Cortex EMR application, providing single sign-on (SSO) capabilities for internal staff access.

## Features

- **Azure AD Application Registration**: Automatically creates and configures Azure AD enterprise application
- **Role-Based Access Control**: Maps Azure AD groups to EMR application roles
- **Conditional Access**: Implements security policies for EMR access
- **Single Sign-On**: Seamless authentication for internal users
- **Security Monitoring**: CloudWatch logging and alerting for authentication events
- **Compliance**: Meets healthcare security requirements for user authentication

## Architecture

```
Internal Staff → Azure AD Authentication → FortiGate VPN → EMR Application
                                        ↓
                                   Role Mapping & Authorization
```

## Usage

```hcl
module "entra_ad_integration" {
  source = "./modules/entra-ad-integration"
  
  name_prefix   = "customer-prod"
  customer_code = "customer"
  
  entra_tenant_id     = "12345678-1234-1234-1234-123456789012"
  application_redirect_uri = "https://customer-emr.healthcare.local/auth/callback"
  
  allowed_user_groups = [
    "EMR-Administrators",
    "EMR-Doctors",
    "EMR-Nurses",
    "EMR-Staff"
  ]
  
  security_group_mappings = {
    "EMR-Administrators" = {
      emr_role    = "admin"
      permissions = ["read", "write", "admin", "audit"]
    }
    "EMR-Doctors" = {
      emr_role    = "physician"
      permissions = ["read", "write", "prescribe"]
    }
  }
  
  tags = {
    Environment = "prod"
    Customer    = "customer"
  }
}
```

## Security Group Mappings

The module supports the following built-in EMR roles:

| EMR Role | Description | Typical Permissions |
|----------|-------------|-------------------|
| `admin` | System Administrator | Full system access, user management, configuration |
| `physician` | Doctor/Physician | Patient records, prescriptions, clinical notes |
| `nurse` | Nurse | Patient care, vitals, medications administration |
| `staff` | Healthcare Staff | Appointments, billing, basic patient info |
| `pharmacist` | Pharmacist | Medication management, prescription fulfillment |
| `lab-tech` | Lab Technician | Lab results, specimen tracking |

## Configuration Requirements

### Azure AD Prerequisites

1. **Azure AD Tenant**: Must have appropriate permissions to create applications
2. **User Groups**: Azure AD groups must exist before deployment
3. **Admin Consent**: Application permissions require admin consent
4. **Conditional Access**: Requires Azure AD Premium licensing

### AWS Prerequisites

1. **AWS Secrets Manager**: For storing client secrets
2. **AWS Systems Manager**: For configuration parameters
3. **CloudWatch Logs**: For authentication logging
4. **IAM Permissions**: EC2 instances need SSM and Secrets Manager access

## Outputs

- `application_id`: Azure AD application ID for EMR configuration
- `client_secret_arn`: AWS secret ARN containing client secret
- `configuration_parameter_name`: SSM parameter with complete configuration
- `setup_script_parameter_name`: SSM parameter with PowerShell setup script

## Monitoring

The module creates CloudWatch monitoring for:

- **Authentication Failures**: Alerts on excessive failed login attempts
- **Authentication Logs**: Centralized logging of all auth events
- **Security Events**: Integration with AWS Security Hub
- **Performance Metrics**: Authentication response times and success rates

## Troubleshooting

### Common Issues

1. **Application Registration Fails**
   - Check Azure AD permissions
   - Verify tenant ID is correct
   - Ensure unique application name

2. **Group Assignment Fails**
   - Verify groups exist in Azure AD
   - Check group naming matches exactly
   - Confirm admin permissions for group assignment

3. **Authentication Not Working**
   - Verify redirect URI configuration
   - Check client secret in AWS Secrets Manager
   - Validate conditional access policies

### Debug Commands

```powershell
# Check EMR configuration
Get-Content "C:\EMR\Config\entra-config.json" | ConvertFrom-Json

# View authentication logs
Get-WinEvent -LogName "EMR-Authentication" -MaxEvents 50

# Test Azure AD connectivity
$TenantId = "your-tenant-id"
Invoke-RestMethod "https://login.microsoftonline.com/$TenantId/v2.0/.well-known/openid_configuration"
```

## Security Considerations

- **Client Secret Rotation**: Secrets are set to expire every 2 years
- **Conditional Access**: MFA and device compliance required
- **Audit Logging**: All authentication events logged to CloudWatch
- **Network Security**: Access only through FortiGate VPN tunnel
- **Session Management**: 8-hour session timeout with sliding expiration