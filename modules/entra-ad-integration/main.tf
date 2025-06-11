# modules/entra-ad-integration/main.tf

# Create Azure AD Enterprise Application for EMR
resource "azuread_application" "emr_app" {
  display_name     = "${var.name_prefix}-emr-application"
  description      = "Cortex EMR application for ${var.customer_code}"
  sign_in_audience = "AzureADMyOrg"
  
  # Required resource access for Microsoft Graph
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
    
    resource_access {
      id   = "b4e74841-8e56-480b-be8b-910348b18b4c" # User.ReadBasic.All
      type = "Scope"
    }
    
    resource_access {
      id   = "5f8c59db-677d-42c8-9acd-3344d6a4e6a1" # Group.Read.All
      type = "Scope"
    }
  }
  
  # Web application configuration
  web {
    redirect_uris = [var.application_redirect_uri]
    
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }
  
  # API configuration
  api {
    mapped_claims_enabled          = true
    requested_access_token_version = 2
    
    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access EMR on behalf of the signed-in user."
      admin_consent_display_name = "Access EMR"
      enabled                    = true
      id                         = "emr.access"
      type                       = "User"
      user_consent_description   = "Allow the application to access EMR on your behalf."
      user_consent_display_name  = "Access EMR"
      value                      = "emr.access"
    }
  }
  
  # Application roles for different EMR user types
  app_role {
    allowed_member_types = ["User", "Application"]
    description         = "EMR Administrator with full system access"
    display_name        = "EMR Administrator"
    enabled             = true
    id                  = "admin"
    value               = "EMR.Admin"
  }
  
  app_role {
    allowed_member_types = ["User"]
    description         = "Physician with clinical access"
    display_name        = "Physician"
    enabled             = true
    id                  = "physician"
    value               = "EMR.Physician"
  }
  
  app_role {
    allowed_member_types = ["User"]
    description         = "Nurse with patient care access"
    display_name        = "Nurse"
    enabled             = true
    id                  = "nurse"
    value               = "EMR.Nurse"
  }
  
  app_role {
    allowed_member_types = ["User"]
    description         = "Healthcare staff with limited access"
    display_name        = "Healthcare Staff"
    enabled             = true
    id                  = "staff"
    value               = "EMR.Staff"
  }
  
  app_role {
    allowed_member_types = ["User"]
    description         = "Pharmacist with medication access"
    display_name        = "Pharmacist"
    enabled             = true
    id                  = "pharmacist"
    value               = "EMR.Pharmacist"
  }
  
  app_role {
    allowed_member_types = ["User"]
    description         = "Lab Technician with lab results access"
    display_name        = "Lab Technician"
    enabled             = true
    id                  = "lab-tech"
    value               = "EMR.LabTech"
  }
  
  tags = [
    "healthcare",
    "emr",
    "customer:${var.customer_code}",
    "managed-by-terraform"
  ]
}

# Create service principal for the application
resource "azuread_service_principal" "emr_app" {
  application_id               = azuread_application.emr_app.application_id
  app_role_assignment_required = true
  
  tags = [
    "healthcare",
    "emr",
    "customer:${var.customer_code}",
    "managed-by-terraform"
  ]
}

# Create application password/secret
resource "azuread_application_password" "emr_app_secret" {
  application_object_id = azuread_application.emr_app.object_id
  display_name         = "EMR Application Secret"
  
  # Rotate secret every 2 years
  end_date = timeadd(timestamp(), "17520h") # 2 years
}

# Store application secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "entra_client_secret" {
  name        = "${var.name_prefix}-entra-client-secret"
  description = "Entra ID client secret for EMR application"
  
  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-entra-secret"
    Purpose = "EntraAuthentication"
  })
}

resource "aws_secretsmanager_secret_version" "entra_client_secret" {
  secret_id = aws_secretsmanager_secret.entra_client_secret.id
  secret_string = jsonencode({
    client_id     = azuread_application.emr_app.application_id
    client_secret = azuread_application_password.emr_app_secret.value
    tenant_id     = var.entra_tenant_id
    redirect_uri  = var.application_redirect_uri
  })
}

# Get Entra ID groups for role assignment
data "azuread_groups" "emr_groups" {
  display_names = var.allowed_user_groups
}

# Assign groups to application roles
resource "azuread_app_role_assignment" "group_assignments" {
  for_each = var.security_group_mappings
  
  app_role_id         = lookup(local.app_role_mapping, each.value.emr_role, "staff")
  principal_object_id = data.azuread_groups.emr_groups.groups[index(var.allowed_user_groups, each.key)].object_id
  resource_object_id  = azuread_service_principal.emr_app.object_id
}

# Local mapping of EMR roles to Azure AD app role IDs
locals {
  app_role_mapping = {
    "admin"      = "admin"
    "physician"  = "physician"
    "nurse"      = "nurse"
    "staff"      = "staff"
    "pharmacist" = "pharmacist"
    "lab-tech"   = "lab-tech"
  }
}

# Create conditional access policy for EMR application
resource "azuread_conditional_access_policy" "emr_access_policy" {
  display_name = "${var.name_prefix} EMR Access Policy"
  state        = "enabled"
  
  conditions {
    applications {
      included_applications = [azuread_application.emr_app.application_id]
    }
    
    users {
      included_groups = [for group in data.azuread_groups.emr_groups.groups : group.object_id]
    }
    
    locations {
      included_locations = ["All"]
    }
    
    platforms {
      included_platforms = ["windows", "macOS", "linux"]
    }
    
    client_app_types = ["browser", "mobileAppsAndDesktopClients"]
  }
  
  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa", "compliantDevice"]
  }
  
  session_controls {
    sign_in_frequency                = 8  # 8 hours
    sign_in_frequency_period         = "hours"
    sign_in_frequency_authentication_type = "primaryAndSecondaryAuthentication"
  }
}

# Create EMR application configuration in AWS Systems Manager Parameter Store
resource "aws_ssm_parameter" "entra_config" {
  name  = "/${var.name_prefix}/entra-ad/config"
  type  = "SecureString"
  value = jsonencode({
    tenant_id       = var.entra_tenant_id
    client_id       = azuread_application.emr_app.application_id
    client_secret   = aws_secretsmanager_secret.entra_client_secret.arn
    redirect_uri    = var.application_redirect_uri
    authority       = "https://login.microsoftonline.com/${var.entra_tenant_id}"
    scope           = "openid profile User.Read Group.Read.All"
    app_roles       = local.app_role_mapping
    group_mappings  = var.security_group_mappings
  })
  
  description = "Entra ID configuration for EMR application"
  
  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-entra-config"
    Purpose = "EntraConfiguration"
  })
}

# Create user data script for EMR application servers with Entra AD integration
resource "aws_ssm_parameter" "entra_setup_script" {
  name  = "/${var.name_prefix}/scripts/entra-setup"
  type  = "String"
  value = templatefile("${path.module}/scripts/entra-setup.ps1", {
    customer_code     = var.customer_code
    name_prefix      = var.name_prefix
    tenant_id        = var.entra_tenant_id
    client_id        = azuread_application.emr_app.application_id
    config_parameter = aws_ssm_parameter.entra_config.name
  })
  
  description = "PowerShell script for configuring Entra AD integration on EMR servers"
  
  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-entra-setup-script"
    Purpose = "EntraSetup"
  })
}

# CloudWatch Log Group for Entra AD authentication logs
resource "aws_cloudwatch_log_group" "entra_auth_logs" {
  name              = "/aws/emr/${var.name_prefix}/entra-auth"
  retention_in_days = var.log_retention_days
  
  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-entra-auth-logs"
    Purpose = "Authentication"
  })
}

# CloudWatch metric filter for failed authentication attempts
resource "aws_cloudwatch_log_metric_filter" "failed_auth" {
  name           = "${var.name_prefix}-entra-failed-auth"
  log_group_name = aws_cloudwatch_log_group.entra_auth_logs.name
  pattern        = "[timestamp, level=\"ERROR\", component=\"EntraAuth\", event=\"LOGIN_FAILED\", user, ...]"
  
  metric_transformation {
    name      = "EntraAuthFailures"
    namespace = "EMR/Authentication"
    value     = "1"
  }
}

# CloudWatch alarm for excessive failed authentication attempts
resource "aws_cloudwatch_metric_alarm" "auth_failures" {
  alarm_name          = "${var.name_prefix}-entra-auth-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EntraAuthFailures"
  namespace           = "EMR/Authentication"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Multiple Entra authentication failures detected"
  alarm_actions       = var.alarm_actions
  
  tags = var.tags
}

# Output application information for EMR configuration
locals {
  emr_app_config = {
    tenant_id     = var.entra_tenant_id
    client_id     = azuread_application.emr_app.application_id
    redirect_uri  = var.application_redirect_uri
    authority_url = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"
    graph_url     = "https://graph.microsoft.com/v1.0"
    scopes        = "openid profile User.Read Group.Read.All"
  }
}