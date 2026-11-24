<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'Palo Alto Networks'
    AppName = 'GlobalProtect'
    AppVersion = '6.3.3'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'PanGPA'; Description = 'GlobalProtect' }
    )
    AppScriptVersion = '2.0.0'
    AppScriptDate = '2026-11-20'
    AppScriptAuthor = 'EUC Team'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'GlobalProtect'
    InstallTitle = 'GlobalProtect Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

$appFiles = @{
    GlobalProtectMsi = Join-Path -Path $PSScriptRoot -ChildPath 'Files\GlobalProtect64.msi'
}

## Stratum Reservoir GlobalProtect portal configuration.
## The first portal is the default portal pre-configured by the MSI; all portals are added to
## the GlobalProtect "Manage Portals" list and the Connect Before Logon (CBL) portal list.
$globalProtectPortals = @(
    'US2.Connect.StratumReservoir.com',
    'NO.Connect.StratumReservoir.com'
)
$globalProtectDefaultPortal = $globalProtectPortals[0]

## PORTAL             : Pre-configures the default portal address.
## CONNECTBEFORELOGON : Enables pre-logon / Connect Before Logon (PLAP).
$globalProtectMsiArguments = "PORTAL=$globalProtectDefaultPortal CONNECTBEFORELOGON=1"

$globalProtectInstallDir = Join-Path -Path $env:ProgramFiles -ChildPath 'Palo Alto Networks\GlobalProtect'
$globalProtectRegRoot = 'HKEY_LOCAL_MACHINE\SOFTWARE\Palo Alto Networks\GlobalProtect'

function Test-RequiredInstallerFiles
{
    [CmdletBinding()]
    param()

    foreach ($requiredFile in @('GlobalProtectMsi'))
    {
        if (!(Test-Path -LiteralPath $appFiles[$requiredFile] -PathType Leaf))
        {
            throw "Required installer file is missing: $($appFiles[$requiredFile])"
        }
    }
}

function Stop-GlobalProtectService
{
    [CmdletBinding()]
    param()

    ## PanGPS is the GlobalProtect service. Stopping it first avoids locked files during MSI removal/upgrade.
    if (Get-Service -Name 'PanGPS' -ErrorAction Ignore)
    {
        Write-ADTLogEntry -Message 'Stopping the GlobalProtect service [PanGPS].'
        Stop-Service -Name 'PanGPS' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Uninstall-GlobalProtect
{
    [CmdletBinding()]
    param()

    ## Removes any installed GlobalProtect MSI (any version) using the product code registered on the device.
    $installedApps = Get-ADTApplication -Name 'GlobalProtect' -NameMatch 'Exact' -ApplicationType 'MSI'
    if (!$installedApps)
    {
        Write-ADTLogEntry -Message 'No existing GlobalProtect installation detected.'
        return
    }

    foreach ($installedApp in $installedApps)
    {
        Write-ADTLogEntry -Message "Removing GlobalProtect [$($installedApp.DisplayVersion)] with product code [$($installedApp.ProductCode)]."
    }
    Uninstall-ADTApplication -InstalledApplication $installedApps -IgnoreExitCodes 1605
}

function Install-GlobalProtect
{
    [CmdletBinding()]
    param()

    Start-ADTMsiProcess -Action Install -FilePath $appFiles.GlobalProtectMsi -AdditionalArgumentList $globalProtectMsiArguments
}

function Repair-GlobalProtect
{
    [CmdletBinding()]
    param()

    Start-ADTMsiProcess -Action Repair -FilePath $appFiles.GlobalProtectMsi
}

function Set-GlobalProtectConfiguration
{
    [CmdletBinding()]
    param()

    ## ============================================
    ## Machine-wide portal and pre-logon settings
    ## ============================================
    Write-ADTLogEntry -Message 'Applying GlobalProtect machine-wide portal and pre-logon settings.'

    ## PanSetup: default portal and pre-logon (required for Connect Before Logon).
    Set-ADTRegistryKey -Key "$globalProtectRegRoot\PanSetup" -Name 'Portal' -Value $globalProtectDefaultPortal -Type String
    Set-ADTRegistryKey -Key "$globalProtectRegRoot\PanSetup" -Name 'Prelogon' -Value 1 -Type DWord

    ## CBL: portals offered at the Windows sign-in screen, and always show the portal drop-down.
    for ($i = 0; $i -lt $globalProtectPortals.Count; $i++)
    {
        Set-ADTRegistryKey -Key "$globalProtectRegRoot\CBL" -Name "Portal$($i + 1)" -Value $globalProtectPortals[$i] -Type String
    }
    Set-ADTRegistryKey -Key "$globalProtectRegRoot\CBL" -Name 'AlwaysShowPortal' -Value 'yes' -Type String

    ## Machine-wide portal list (Settings and PanGPS paths, used by some GlobalProtect versions).
    foreach ($portal in $globalProtectPortals)
    {
        Set-ADTRegistryKey -Key "$globalProtectRegRoot\Settings\$portal" -Name 'Portal' -Value $portal -Type String
        Set-ADTRegistryKey -Key "$globalProtectRegRoot\PanGPS\$portal" -Name 'Portal' -Value $portal -Type String
    }

    ## Make the GlobalProtect Credential Provider the default sign-in option.
    Set-ADTRegistryKey -Key $globalProtectRegRoot -Name 'MakeGPCPDefault' -Value 'yes' -Type String

    ## ============================================
    ## Register PLAP (Pre-Logon Access Provider) so the GlobalProtect
    ## Connect button is available at the Windows sign-in screen.
    ## ============================================
    $panGpsPath = Join-Path -Path $globalProtectInstallDir -ChildPath 'PanGPS.exe'
    if (Test-Path -LiteralPath $panGpsPath -PathType Leaf)
    {
        Write-ADTLogEntry -Message 'Registering the GlobalProtect Pre-Logon Access Provider (PanGPS.exe -registerplap).'
        Start-ADTProcess -FilePath $panGpsPath -ArgumentList '-registerplap' -CreateNoWindow -IgnoreExitCodes '*'
    }
    else
    {
        Write-ADTLogEntry -Message "PanGPS.exe was not found at [$panGpsPath]. Manual PLAP registration may be required." -Severity 2
    }

    ## ============================================
    ## Per-user portal list ("Manage Portals" in the GlobalProtect GUI).
    ## GlobalProtect reads this from HKCU, so write it into every existing profile
    ## and the Default User profile (for new sign-ins). PSADT loads/unloads hives as needed.
    ## ============================================
    Write-ADTLogEntry -Message 'Adding GlobalProtect portals to all user profiles and the Default User profile.'
    Invoke-ADTAllUsersRegistryAction -ScriptBlock {
        foreach ($portal in $globalProtectPortals)
        {
            Set-ADTRegistryKey -Key "HKEY_CURRENT_USER\SOFTWARE\Palo Alto Networks\GlobalProtect\Settings\$portal" -Name 'Portal' -Value $portal -Type String -SID $_.SID
        }
    }

    Write-ADTLogEntry -Message 'GlobalProtect configuration completed. The Connect Before Logon button is available at the sign-in screen after the next restart.'
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, ask the user to close GlobalProtect if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'GlobalProtect Upgrade'
        Subtitle = 'GlobalProtect VPN is being upgraded. Your VPN connection will be disconnected briefly. Please save your work within 5 minutes, or GlobalProtect will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Installation tasks here>

    Test-RequiredInstallerFiles

    ## Remove any existing GlobalProtect version before installing (matches the previous package behaviour).
    Stop-GlobalProtectService
    Show-ADTInstallationProgress -StatusMessage 'Removing the existing GlobalProtect version...'
    Uninstall-GlobalProtect


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage "Installing GlobalProtect $($adtSession.AppVersion)..."
    Install-GlobalProtect

    ## Give the GlobalProtect service time to initialise before configuring it.
    Start-Sleep -Seconds 10

    ## <Perform Installation tasks here>


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Show-ADTInstallationProgress -StatusMessage 'Configuring GlobalProtect portals and Connect Before Logon...'
    Set-GlobalProtectConfiguration

    ## <Perform Post-Installation tasks here>

    ## No post-install prompt for managed deployment scenarios (SCCM/Intune).
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, ask the user to close GlobalProtect if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'GlobalProtect Uninstall'
        Subtitle = 'GlobalProtect VPN is being removed. Your VPN connection will be disconnected. Please save your work within 5 minutes, or GlobalProtect will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>

    Stop-GlobalProtectService


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Uninstall by registered product code so any installed GlobalProtect version is removed,
    ## not just the version shipped in this package.
    Uninstall-GlobalProtect

    ## <Perform Uninstallation tasks here>


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>

    if (Get-ADTApplication -Name 'GlobalProtect' -NameMatch 'Exact')
    {
        Write-ADTLogEntry -Message 'GlobalProtect is still registered as installed. Manual cleanup may be required.' -Severity 2
    }
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, ask the user to close GlobalProtect if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'GlobalProtect Repair'
        Subtitle = 'GlobalProtect VPN is being repaired. Your VPN connection will be disconnected briefly. Please save your work within 5 minutes, or GlobalProtect will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Repair tasks here>

    Test-RequiredInstallerFiles


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Repair-GlobalProtect

    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Re-apply portal and Connect Before Logon settings in case they were lost.
    Set-GlobalProtectConfiguration

    ## <Perform Post-Repair tasks here>
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}

