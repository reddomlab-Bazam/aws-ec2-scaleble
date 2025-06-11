# modules/compute/user-data/app-server-userdata.ps1

<powershell>
# Log all output
Start-Transcript -Path "C:\temp\userdata.log" -Force

try {
    Write-Output "Starting Cortex EMR Application Server configuration..."
    
    # Create temp directory
    New-Item -ItemType Directory -Path "C:\temp" -Force
    
    # Install required Windows features
    Write-Output "Installing Windows features..."
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All
    
    # Install .NET Framework 4.8
    Write-Output "Installing .NET Framework 4.8..."
    $url = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP48-Web.exe"
    $output = "C:\temp\NDP48-Web.exe"
    Invoke-WebRequest -Uri $url -OutFile $output
    Start-Process -FilePath $output -ArgumentList "/quiet" -Wait
    
    # Install Java 8 (required for Tomcat)
    Write-Output "Installing Java 8..."
    $javaUrl = "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=245479_4d5417147a92418ea8b615e228bb6935"
    $javaOutput = "C:\temp\jre-8u311-windows-x64.exe"
    Invoke-WebRequest -Uri $javaUrl -OutFile $javaOutput
    Start-Process -FilePath $javaOutput -ArgumentList "/s" -Wait
    
    # Download and install Tomcat 9
    Write-Output "Installing Apache Tomcat 9..."
    $tomcatUrl = "https://downloads.apache.org/tomcat/tomcat-9/v9.0.65/bin/apache-tomcat-9.0.65-windows-x64.zip"
    $tomcatZip = "C:\temp\tomcat.zip"
    Invoke-WebRequest -Uri $tomcatUrl -OutFile $tomcatZip
    Expand-Archive -Path $tomcatZip -DestinationPath "C:\tomcat" -Force
    
    # Configure Tomcat as Windows Service
    Write-Output "Configuring Tomcat service..."
    $tomcatPath = Get-ChildItem -Path "C:\tomcat" -Directory | Select-Object -First 1
    & "$($tomcatPath.FullName)\bin\service.bat" install
    
    # Set Tomcat service to start automatically
    Set-Service -Name "Tomcat9" -StartupType Automatic
    
    # Configure firewall for Tomcat
    Write-Output "Configuring firewall..."
    New-NetFirewallRule -DisplayName "Tomcat HTTP" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
    
    # Mount FSx file system
    Write-Output "Mounting FSx file system..."
    $fsx_dns = "${fsx_dns_name}"
    if ($fsx_dns -ne "") {
        $credential = New-Object System.Management.Automation.PSCredential("${domain_netbios_name}\${domain_admin_user}", (ConvertTo-SecureString "${domain_admin_password}" -AsPlainText -Force))
        New-PSDrive -Name "S" -PSProvider FileSystem -Root "\\$fsx_dns\share" -Credential $credential -Persist
        
        # Create application directories on shared drive
        New-Item -ItemType Directory -Path "S:\CortexEMR" -Force
        New-Item -ItemType Directory -Path "S:\CortexEMR\logs" -Force
        New-Item -ItemType Directory -Path "S:\CortexEMR\uploads" -Force
        New-Item -ItemType Directory -Path "S:\CortexEMR\backups" -Force
    }
    
    # Join domain
    Write-Output "Joining domain..."
    $domain = "${domain_name}"
    $user = "${domain_admin_user}"
    $password = "${domain_admin_password}"
    
    if ($domain -ne "" -and $user -ne "" -and $password -ne "") {
        $credential = New-Object System.Management.Automation.PSCredential("$domain\$user", (ConvertTo-SecureString $password -AsPlainText -Force))
        Add-Computer -DomainName $domain -Credential $credential -Restart -Force
    }
    
    # Install CloudWatch Agent
    Write-Output "Installing CloudWatch Agent..."
    $cwAgentUrl = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwAgentPath = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwAgentUrl -OutFile $cwAgentPath
    Start-Process msiexec.exe -Wait -ArgumentList "/i $cwAgentPath /quiet"
    
    # Configure CloudWatch Agent
    $config = @"
{
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "C:\\tomcat\\**\\logs\\*.log",
                        "log_group_name": "/aws/ec2/cortex-emr/tomcat",
                        "log_stream_name": "{instance_id}-tomcat.log"
                    }
                ]
            },
            "windows_events": {
                "collect_list": [
                    {
                        "event_name": "System",
                        "event_levels": ["ERROR", "CRITICAL"],
                        "log_group_name": "/aws/ec2/cortex-emr/system",
                        "log_stream_name": "{instance_id}-system"
                    }
                ]
            }
        }
    }
}
"@
    
    $config | Out-File -FilePath "C:\temp\cloudwatch-config.json" -Encoding ASCII
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:"C:\temp\cloudwatch-config.json" -s
    
    # Create health check endpoint
    Write-Output "Creating health check endpoint..."
    $healthCheckContent = @"
<%@ page language="java" contentType="text/plain; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*" %>
<%
    response.setContentType("text/plain");
    
    // Check database connectivity
    String dbUrl = "jdbc:mysql://${db_endpoint}:3306/${db_name}";
    String dbUser = "admin"; // This should be configured properly
    String dbPassword = ""; // This should be retrieved from AWS Secrets Manager
    
    try {
        Class.forName("com.mysql.cj.jdbc.Driver");
        Connection conn = DriverManager.getConnection(dbUrl, dbUser, dbPassword);
        conn.close();
        out.println("OK");
    } catch (Exception e) {
        response.setStatus(503);
        out.println("ERROR: " + e.getMessage());
    }
%>
"@
    
    $webappsPath = Get-ChildItem -Path "C:\tomcat\*\webapps" -Directory | Select-Object -First 1
    if ($webappsPath) {
        New-Item -ItemType Directory -Path "$($webappsPath.FullName)\ROOT" -Force
        $healthCheckContent | Out-File -FilePath "$($webappsPath.FullName)\ROOT\health.jsp" -Encoding UTF8
    }
    
    # Start Tomcat service
    Write-Output "Starting Tomcat service..."
    Start-Service -Name "Tomcat9"
    
    Write-Output "Cortex EMR Application Server configuration completed successfully!"
    
} catch {
    Write-Error "Error during configuration: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
} finally {
    Stop-Transcript
}
</powershell>

# modules/compute/user-data/integration-server-userdata.ps1

<powershell>
# Log all output
Start-Transcript -Path "C:\temp\userdata.log" -Force

try {
    Write-Output "Starting Cortex EMR Integration Server configuration..."
    
    # Create temp directory
    New-Item -ItemType Directory -Path "C:\temp" -Force
    
    # Install IIS and .NET Framework
    Write-Output "Installing Windows features..."
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-NetFxExtensibility45 -All
    
    # Install .NET Framework 4.8
    Write-Output "Installing .NET Framework 4.8..."
    $url = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP48-Web.exe"
    $output = "C:\temp\NDP48-Web.exe"
    Invoke-WebRequest -Uri $url -OutFile $output
    Start-Process -FilePath $output -ArgumentList "/quiet" -Wait
    
    # Configure firewall
    Write-Output "Configuring firewall..."
    New-NetFirewallRule -DisplayName "Integration HTTP" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
    New-NetFirewallRule -DisplayName "Integration HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
    New-NetFirewallRule -DisplayName "Integration Custom Range" -Direction Inbound -Protocol TCP -LocalPort 9000-9999 -Action Allow
    
    # Join domain
    Write-Output "Joining domain..."
    $domain = "${domain_name}"
    $user = "${domain_admin_user}"
    $password = "${domain_admin_password}"
    
    if ($domain -ne "" -and $user -ne "" -and $password -ne "") {
        $credential = New-Object System.Management.Automation.PSCredential("$domain\$user", (ConvertTo-SecureString $password -AsPlainText -Force))
        Add-Computer -DomainName $domain -Credential $credential -Restart -Force
    }
    
    # Install CloudWatch Agent
    Write-Output "Installing CloudWatch Agent..."
    $cwAgentUrl = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwAgentPath = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwAgentUrl -OutFile $cwAgentPath
    Start-Process msiexec.exe -Wait -ArgumentList "/i $cwAgentPath /quiet"
    
    # Configure integration services directories
    Write-Output "Setting up integration directories..."
    New-Item -ItemType Directory -Path "C:\IntegrationServices" -Force
    New-Item -ItemType Directory -Path "C:\IntegrationServices\AmanAl" -Force
    New-Item -ItemType Directory -Path "C:\IntegrationServices\Malaffi" -Force
    New-Item -ItemType Directory -Path "C:\IntegrationServices\InHouseRAD" -Force
    New-Item -ItemType Directory -Path "C:\IntegrationServices\Logs" -Force
    
    Write-Output "Integration Server configuration completed successfully!"
    
} catch {
    Write-Error "Error during configuration: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
} finally {
    Stop-Transcript
}
</powershell>

# modules/compute/user-data/bastion-userdata.ps1

<powershell>
# Log all output
Start-Transcript -Path "C:\temp\userdata.log" -Force

try {
    Write-Output "Starting Bastion Host configuration..."
    
    # Create temp directory
    New-Item -ItemType Directory -Path "C:\temp" -Force
    
    # Install Remote Desktop Services
    Write-Output "Configuring Remote Desktop..."
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    
    # Install admin tools
    Write-Output "Installing administrative tools..."
    Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server, RSAT-DHCP
    
    # Join domain
    Write-Output "Joining domain..."
    $domain = "${domain_name}"
    $user = "${domain_admin_user}"
    $password = "${domain_admin_password}"
    
    if ($domain -ne "" -and $user -ne "" -and $password -ne "") {
        $credential = New-Object System.Management.Automation.PSCredential("$domain\$user", (ConvertTo-SecureString $password -AsPlainText -Force))
        Add-Computer -DomainName $domain -Credential $credential -Restart -Force
    }
    
    # Install CloudWatch Agent
    Write-Output "Installing CloudWatch Agent..."
    $cwAgentUrl = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwAgentPath = "C:\temp\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwAgentUrl -OutFile $cwAgentPath
    Start-Process msiexec.exe -Wait -ArgumentList "/i $cwAgentPath /quiet"
    
    Write-Output "Bastion Host configuration completed successfully!"
    
} catch {
    Write-Error "Error during configuration: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
} finally {
    Stop-Transcript
}
</powershell>