#This script configures the Pull server LCM and DSC webdownload service
#This script is called by baseprep.ps1 during the automated workflow

###########################
###     CREATE GUID     ###
###  [guid]::NewGuid()  ###
###########################


. "C:\cloud-automation\secrets.ps1"

configuration Assert_DSCService 
{ 
   param  
   ( 
      [string[]]$NodeName, 
      [ValidateNotNullOrEmpty()] 
      [string] $certificateThumbPrint
   ) 
   Import-DscResource -ModuleName rsCloudServersOpenStack
   Import-DscResource -ModuleName rsCloudLoadBalancers
   Import-DscResource -ModuleName rsScheduledTask
   Import-DscResource -ModuleName msPSDesiredStateConfiguration
   Import-DscResource -ModuleName rsPlatform
   Import-DscResource -ModuleName rsGit
   Import-DscResource -ModuleName rsClientMofs
   Import-DSCResource -ModuleName msWebAdministration
   Import-DSCResource -ModuleName PowerShellAccessControl
   Import-DSCResource -ModuleName msNetworking
   
   Node $NodeName
   { 
      WindowsFeature IIS
      {
         Ensure = "Present"
         Name = "Web-Server"
      }
      WindowsFeature InetMgr
      {
         Ensure = "Present"
         Name = "Web-Mgmt-Tools"
      }
      WindowsFeature DSCServiceFeature 
      { 
         Ensure = "Present" 
         Name   = "DSC-Service"             
      } 
      xDscWebService MSWPullServer 
      { 
         Ensure                  = "Present" 
         EndpointName            = "MSWPullServer" 
         Port                    =  8080 
         PhysicalPath            = "$env:SystemDrive\inetpub\wwwroot\MSWPullServer"  
         CertificateThumbPrint   =  $certificateThumbPrint        
         ModulePath              = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules" 
         ConfigurationPath       = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Configuration"             
         State                   = "Started" 
         DependsOn               = "[WindowsFeature]DSCServiceFeature"                      
      } 
      xDscWebService PSDSCComplianceServer 
      { 
         Ensure                  = "Present" 
         EndpointName            = "MSWComplianceServer" 
         Port                    =  9080
         PhysicalPath            = "$env:SystemDrive\inetpub\wwwroot\MSWComplianceServer" 
         CertificateThumbPrint   = $certificateThumbPrint 
         State                   = "Started" 
         IsComplianceServer      = $true
         DependsOn               = @("[WindowsFeature]DSCServiceFeature","[xDSCWebService]MSWPullServer")
      }
      rsGit rsConfigs
      {
         name = "rsConfigs"
         Source = ("git@github.com:", $($d.gCA),  $($($d.mR), ".git" -join '') -join '/')
         Destination = $($d.wD)
         Ensure = "Present"
         Branch = "master"
         Logging = $false
      }
      File rsPlatformDir
      {
         SourcePath = $($d.wD, $d.mR, "rsPlatform" -join '\')
         DestinationPath = "C:\Program Files\WindowsPowerShell\Modules\rsPlatform"
         Type = "Directory"
         Recurse = $true
         Ensure = "Present"
      }
      rsPlatform Modules
      {
         Ensure          = "Present"
      }
      #### Environment section commented out for template, please edit this section for your own environment builds

      rsCloudServersOpenStack ORDwebfarm
      {
         Ensure                 = "Present"
         minNumberOfDevices     = 2
         maxNumberOfDevices     = 9
         namingConvention       = "MSWFarm"
         image                  = "Windows Server 2012"
         nflavor                = "performance1-4"
         dataCenter             = "ORD"
         role                   = "webFarm"
         pullServerName         = "PULLServer"
         environmentGuid        = "b488f98f-23b8-42d4-83a5-17bc25f2da02"
         BuildTimeOut           = 30
         EnvironmentName        = "ORDwebfarm"
      }
      rsCloudServersOpenStack ORDDevfarm
      {
         Ensure                 = "Absent"
         minNumberOfDevices     = 1
         maxNumberOfDevices     = 9
         namingConvention       = "MSWDevFarm"
         image                  = "Windows Server 2012"
         nflavor                = "performance1-4"
         dataCenter             = "ORD"
         role                   = "webFarm"
         pullServerName         = "PULLServer"
         environmentGuid        = "b812d8fc-3f66-4f02-ab83-badb7949a062"
         BuildTimeOut           = 30
         EnvironmentName        = "ORDDevfarm"
      }
      rsCloudLoadBalancers prod_ORDlb
      {
         loadBalancerName       = "ORDlb"
         port                   = 80
         protocol               = "HTTP"
         nodes                  = @("b812d8fc-3f66-4f02-ab83-badb7949a062")
         dataCenter             = "ORD"
         attemptsBeforeDeactivation = 3
         delay                  = 10
         path                   = "/"
         hostHeader             = "windevops.local"
         statusRegex            = "^[234][0-9][0-9]$"
         timeout                = 10
         type                   = "HTTP"
         algorithm              = "ROUND_ROBIN"
      }
      rsClientMofs CheckMofs
      {
         Name = "CheckMofs"
         Ensure = "Present"
         Logging = $true
      }
      rsSSHKnownHosts git_ssh
      {
         path = "C:\Program Files (x86)\Git\.ssh"
         gitIps = @("github.com,192.30.252.129", "192.30.252.128", "192.30.252.130", "192.30.252.131")
         gitRsa = "AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
      }
      rsGitSSHKey pullserver_sshkey
      {
         installedPath = "C:\Program Files (x86)\Git\.ssh"
         hostedPath = "C:\inetpub\wwwroot"
      }
      rsGit GitDeployHub
      {
         name = "GitDeployHub"
         Source =  $("https://github.com", $($d.gMO), ("gitdeployhub.git" -join '') -join '/')
         Destination = "C:\inetpub\wwwroot\"
         Ensure = "Present"
         Branch = "master"
      }
      xWebAppPool GitDeployHub
      { 
         Name   = "GitDeployHub" 
         Ensure = "Present" 
         State  = "Started" 
      }
      xWebSite GitDeployHub
      { 
         Name   = "GitDeployHub" 
         ApplicationPool = "GitDeployHub"
         Ensure = "Present" 
         State = "Started" 
         PhysicalPath = "$env:SystemDrive\inetpub\wwwroot\gitdeployhub\web\" 
         BindingInfo = @(
              @(MSFT_xWebBindingInformation 
                  {
                  IPAddress = "*" 
                  Port = 9110
                  Protocol = "HTTP"
                  }
            );
          )
         DependsOn = @("[xWebAppPool]GitDeployHub") 
      }
      cAccessControlEntry ModifyGitDeployHub {
         Ensure = "Present"
         Path = "$env:SystemDrive\inetpub\wwwroot\gitdeployhub\"
         AceType = "AccessAllowed"
         ObjectType = "Directory"
         AccessMask = ([System.Security.AccessControl.FileSystemRights]::Modify)
         Principal = "IIS AppPool\GitDeployHub"
         DependsOn = "[rsGit]GitDeployHub"
      }
      rsWebHook DDI_rsConfigs 
      {
         Name = "DDI_rsConfigs"
         Repo = "DDI_rsConfigs"
         Port = "9110"
         Ensure = "Present"
         Logging = $true
         
      }
      xFirewall Firewall 
      { 
         Name                  = "GitDeployHub" 
         DisplayName           = "Allow Port 9110 for GitDeployHub" 
         Ensure                = "Present" 
         Access                = "Allow" 
         State                 = "Enabled" 
         Profile               = ("Any") 
         Direction             = "InBound" 
         LocalPort             = ("9110")          
         Protocol              = "TCP" 
      }
      rsScheduledTask VerifyTask
      {
         ExecutablePath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
         Params = $($d.wD, $d.prov, "Verify.ps1" -join '\')
         Name = "Verify"
         IntervalModifier = "Minute"
         Ensure = "Present"
         Interval = "30"
      }
      cAccessControlEntry ReadExecuteVerify 
      {
         Ensure = "Present"
         Path = "C:\Windows\System32\Tasks\Verify"
         AceType = "AccessAllowed"
         ObjectType = "File"
         AccessMask = ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
         Principal = "IIS AppPool\GitDeployHub"
         DependsOn = "[rsScheduledTask]VerifyTask"
      }
   } 
   
}
$nodename = $Env:COMPUTERNAME
taskkill /F /IM WmiPrvSE.exe
$cN = "CN=" + $nodename
Remove-Item -Path "C:\Windows\Temp\Assert_DSCService" -Force -Recurse -ErrorAction SilentlyContinue
if(!(Get-ChildItem Cert:\LocalMachine\My\ | where {$_.Subject -eq $cN}) -or !(Get-ChildItem Cert:\LocalMachine\Root\ | where {$_.Subject -eq $cN})) {
   Get-ChildItem Cert:\LocalMachine\My\ | where {$_.Subject -eq $cN} | Remove-Item
   Get-ChildItem Cert:\LocalMachine\Root\ | where {$_.Subject -eq $cN} | Remove-Item
   powershell.exe $($d.wD, $d.prov, "makecert.exe" -join '\') -r -pe -n $cN, -ss my "C:\inetpub\wwwroot\PullServer.cert.pfx", -sr localmachine
   powershell.exe certutil -addstore -f Root, "C:\inetpub\wwwroot\PullServer.cert.pfx"
}
$ConfigData = @{
    AllNodes = @(
        @{
            PSDscAllowPlainTextPassword = $true
         }
chdir C:\Windows\Temp
Assert_DSCService -ConfigurationData $configData -Node $nodename -certificateThumbPrint (Get-ChildItem Cert:\LocalMachine\My\ | where {$_.Subject -eq $cN}).Thumbprint
Start-DscConfiguration -Path Assert_DSCService -Wait -Verbose -Force