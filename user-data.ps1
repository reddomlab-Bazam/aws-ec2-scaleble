# user-data.ps1 - Simple Windows Server Setup for Cortex EMR

<powershell>
# Log all output
Start-Transcript -Path "C:\temp\userdata.log" -Force

try {
    Write-Output "Starting Cortex EMR Application Server setup..."
    
    # Create temp directory
    New-Item -ItemType Directory -Path "C:\temp" -Force
    New-Item -ItemType Directory -Path "C:\CortexEMR" -Force
    
    # Install IIS
    Write-Output "Installing IIS..."
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-CommonHttpFeatures -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpErrors -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpLogging -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-Security -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestFiltering -All
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45 -All
    
    # Install .NET Framework 4.8
    Write-Output "Installing .NET Framework 4.8..."
    $url = "https://download.microsoft.com/download/6/E/4/6E48E8AB-DC00-419E-9704-06DD46E5F81D/NDP48-Web.exe"
    $output = "C:\temp\NDP48-Web.exe"
    Invoke-WebRequest -Uri $url -OutFile $output
    Start-Process -FilePath $output -ArgumentList "/quiet" -Wait
    
    # Configure firewall
    Write-Output "Configuring firewall..."
    New-NetFirewallRule -DisplayName "Cortex EMR HTTP" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
    New-NetFirewallRule -DisplayName "HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
    New-NetFirewallRule -DisplayName "HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
    
    # Create database connection string
    $dbConnectionString = "Server=${db_endpoint};Database=${db_name};Uid=${db_username};Pwd=${db_password};"
    
    # Create simple web.config for database connection
    $webConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <connectionStrings>
    <add name="CortexEMR" connectionString="$dbConnectionString" providerName="System.Data.SqlClient" />
  </connectionStrings>
  <system.web>
    <compilation targetFramework="4.8" />
    <httpRuntime targetFramework="4.8" />
  </system.web>
</configuration>
"@
    
    $webConfig | Out-File -FilePath "C:\inetpub\wwwroot\web.config" -Encoding UTF8
    
    # Create a simple health check page
    $healthCheck = @"
<%@ Page Language="C#" %>
<%
    Response.ContentType = "text/plain";
    try 
    {
        // Test database connection
        string connectionString = System.Configuration.ConfigurationManager.ConnectionStrings["CortexEMR"].ConnectionString;
        using (var connection = new System.Data.SqlClient.SqlConnection(connectionString))
        {
            connection.Open();
            Response.Write("OK - Database Connected");
        }
    }
    catch (Exception ex)
    {
        Response.StatusCode = 503;
        Response.Write("ERROR: " + ex.Message);
    }
%>
"@
    
    $healthCheck | Out-File -FilePath "C:\inetpub\wwwroot\health.aspx" -Encoding UTF8
    
    # Create default page
    $defaultPage = @"
<!DOCTYPE html>
<html>
<head>
    <title>Cortex EMR</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #007acc; color: white; padding: 20px; }
        .content { padding: 20px; }
        .status { background-color: #e7f3ff; padding: 10px; margin: 10px 0; border-left: 4px solid #007acc; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Cortex EMR System</h1>
    </div>
    <div class="content">
        <div class="status">
            <strong>Status:</strong> Server is running<br>
            <strong>Database:</strong> ${db_endpoint}<br>
            <strong>Server Time:</strong> <%= DateTime.Now.ToString() %>
        </div>
        <h3>System Information</h3>
        <p>This is a simplified Cortex EMR deployment.</p>
        <p><a href="/health.aspx">Health Check</a></p>
    </div>
</body>
</html>
"@
    
    $defaultPage | Out-File -FilePath "C:\inetpub\wwwroot\default.aspx" -Encoding UTF8
    
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
        "namespace": "CortexEMR",
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
    
    # Restart IIS to apply all changes
    Write-Output "Restarting IIS..."
    iisreset
    
    Write-Output "Cortex EMR Application Server setup completed successfully!"
    
} catch {
    Write-Error "Error during setup: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
} finally {
    Stop-Transcript
}
</powershell>