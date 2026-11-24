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
    AppVendor = 'TeamViewer'
    AppName = 'TeamViewer Host'
    AppVersion = '15.83.7'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'TeamViewer'; Description = 'TeamViewer' }
    )
    AppScriptVersion = '2.0.0'
    AppScriptDate = '2026-11-20'
    AppScriptAuthor = 'EUC Team'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'TeamViewer Host'
    InstallTitle = 'TeamViewer Host Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

$appFiles = @{
    # Custom TeamViewer Host installer downloaded from https://custom.teamviewer.com/6e7w3xh
    # (Configuration ID 6e7w3xh). The Stratum Reservoir customisation is embedded in this EXE.
    Setup = Join-Path -Path $PSScriptRoot -ChildPath 'Files\TeamViewer_Host_Setup_x64.exe'
}

## TeamViewer custom module configuration ID (for reference/logging - embedded in the EXE above).
$teamViewerConfigId = '6e7w3xh'

## TeamViewer Management Console assignment ID (Design & Deploy > your Host module > Assignment ID).
## When set, the device is assigned to the Stratum Reservoir company after install via
## "TeamViewer.exe assignment --id <ID>". Leave empty to skip assignment.
$teamViewerAssignmentId = '0001CoABChA3805QzyAR75VT-SlwpNETEigIACAAAgAJACDS-j2j8YVc1GfanRYkd4kFvBvigAoJKWBcq-8VazB7GkBIIXo9VBmolDuZjV0jI4-WXVYMA64LhEn-x16rTEJdmmrRjiClr63DAFHdB8I7Ar_jUUMrhLjnIaIpzCgdYQiUIAEQ0rDsjwc='

$teamViewerInstallDir = Join-Path -Path $env:ProgramFiles -ChildPath 'TeamViewer'

## Identity values that the OLD TeamViewer package (15.73.5) copied onto every device by importing
## TeamViewer_CompanySettings.reg (a registry export from one configured PC). Devices carrying these values
## share a cloned TeamViewer identity / management state and must be reset and re-assigned.
$teamViewerClonedManagementId = '{b7113481-c353-42ea-bd40-6856e85ef3f6}'
$teamViewerClonedIntuneDeviceId = '{d4e066e4-52d7-49b6-935c-bc7b4c613548}'

function Test-RequiredInstallerFiles
{
    [CmdletBinding()]
    param()

    foreach ($requiredFile in @('Setup'))
    {
        if (!(Test-Path -LiteralPath $appFiles[$requiredFile] -PathType Leaf))
        {
            throw "Required installer file is missing: $($appFiles[$requiredFile])"
        }
    }
}

function Test-TeamViewerClonedIdentity
{
    [CmdletBinding()]
    param()

    ## True when this device still carries the identity imported by the old package.
    $managementId = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer\DeviceManagementV2' -Name 'ManagementId' -ErrorAction SilentlyContinue
    $intuneDeviceId = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer' -Name 'IntuneDeviceId' -ErrorAction SilentlyContinue
    return ([string]$managementId -eq $teamViewerClonedManagementId) -or ([string]$intuneDeviceId -eq $teamViewerClonedIntuneDeviceId)
}

function Reset-TeamViewerIdentity
{
    [CmdletBinding()]
    param()

    ## Remove every TeamViewer install and its machine settings so the next install generates a fresh,
    ## unique identity for this device, which is then assigned to the company by Set-TeamViewerConfiguration.
    Write-ADTLogEntry -Message 'Cloned TeamViewer identity from the old package detected. Removing TeamViewer and its settings for a clean reinstall.' -Severity 2
    Stop-Service -Name 'TeamViewer' -Force -ErrorAction SilentlyContinue
    Remove-TeamViewer
    Get-Process -Name 'TeamViewer*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer' -Recurse -ErrorAction SilentlyContinue
    Remove-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\TeamViewer' -Recurse -ErrorAction SilentlyContinue
}

function Test-UpgradeableTeamViewerHost
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [PSADT.Types.InstalledApplication]$InstalledApplication
    )

    ## A TeamViewer install can be upgraded in place by the new Host EXE only when it is:
    ##   - 64-bit (not under WOW6432Node / Program Files (x86))
    ##   - EXE-based (TeamViewer does not support mixing MSI and EXE installs)
    ##   - the Host module (not the TeamViewer full client)
    $is64Bit = $InstalledApplication.Is64BitApplication -and [string]$InstalledApplication.InstallLocation -notlike '*Program Files (x86)*'
    $isExe = !$InstalledApplication.WindowsInstaller
    $isHost = [string]$InstalledApplication.DisplayName -match 'Host'
    if (!$isHost)
    {
        $isHostModule = Get-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer' -Name 'IsHostModule' -ErrorAction SilentlyContinue
        $isHost = $isHostModule -eq 1
    }
    return ($is64Bit -and $isExe -and $isHost)
}

function Remove-TeamViewer
{
    [CmdletBinding()]
    param
    (
        ## During install: only remove installs that cannot be upgraded in place (32-bit, MSI-based, or the
        ## full client). 64-bit EXE Host installs of any older version are upgraded in place, which keeps the
        ## TeamViewer ID, device history and company assignment.
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]$IncompatibleOnly
    )

    $installedApps = Get-ADTApplication -Name 'TeamViewer' -NameMatch 'Contains'
    if ($IncompatibleOnly)
    {
        foreach ($installedApp in $installedApps)
        {
            if (Test-UpgradeableTeamViewerHost -InstalledApplication $installedApp)
            {
                Write-ADTLogEntry -Message "[$($installedApp.DisplayName)] version [$($installedApp.DisplayVersion)] is a 64-bit Host install and will be upgraded in place."
            }
        }
        $installedApps = $installedApps | Where-Object { !(Test-UpgradeableTeamViewerHost -InstalledApplication $_) }
    }

    if (!$installedApps)
    {
        Write-ADTLogEntry -Message "No $(if ($IncompatibleOnly) { 'incompatible ' })TeamViewer installation found to remove."
        return
    }

    foreach ($installedApp in $installedApps)
    {
        Write-ADTLogEntry -Message "Removing [$($installedApp.DisplayName)] version [$($installedApp.DisplayVersion)] (64-bit: $($installedApp.Is64BitApplication), MSI: $($installedApp.WindowsInstaller))."
        if ($installedApp.WindowsInstaller)
        {
            Uninstall-ADTApplication -InstalledApplication $installedApp -IgnoreExitCodes 1605
        }
        else
        {
            ## TeamViewer EXE uninstaller (uninstall.exe). /S = silent. Wait for child processes because the
            ## uninstaller re-launches itself from %TEMP% and returns before removal completes.
            Uninstall-ADTApplication -InstalledApplication $installedApp -ArgumentList '/S' -WaitForChildProcesses
        }
    }

    ## Give the uninstaller time to release files and the TeamViewer service before installing.
    Start-Sleep -Seconds 5
}

function Install-TeamViewer
{
    [CmdletBinding()]
    param()

    Write-ADTLogEntry -Message "Installing TeamViewer Host $($adtSession.AppVersion) (custom configuration [$teamViewerConfigId])."

    ## Do not wait for child processes here: the installer starts the TeamViewer service/GUI, which never exit.
    Start-ADTProcess -FilePath $appFiles.Setup -ArgumentList '/S' -WindowStyle Hidden

    ## The NSIS installer can return before registration finishes. Wait up to 3 minutes for the new version
    ## to be registered, and fail the deployment (so SCCM reports it) if the upgrade did not take.
    $targetVersion = [version]$adtSession.AppVersion
    $deadline = [System.DateTime]::Now.AddMinutes(3)
    do
    {
        $installed = Get-ADTApplication -Name 'TeamViewer' -NameMatch 'Contains' | Where-Object { Test-UpgradeableTeamViewerHost -InstalledApplication $_ } | Select-Object -First 1
        $installedVersion = $null
        if ($installed -and [string]$installed.DisplayVersion -match '^\s*(\d+)\.(\d+)\.(\d+)')
        {
            $installedVersion = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
        if ($installedVersion -and $installedVersion -ge $targetVersion)
        {
            Write-ADTLogEntry -Message "TeamViewer Host [$($installed.DisplayVersion)] is installed."
            return
        }
        Start-Sleep -Seconds 5
    }
    while ([System.DateTime]::Now -lt $deadline)

    throw "TeamViewer Host $($adtSession.AppVersion) was not registered after install (found: [$($installed.DisplayVersion)])."
}

function Set-TeamViewerConfiguration
{
    [CmdletBinding()]
    param()

    ## Prevent the TeamViewer GUI from starting at sign-in. The TeamViewer service keeps running for remote access.
    ## Note: the 64-bit Host uses HKLM\SOFTWARE\TeamViewer (not WOW6432Node).
    Write-ADTLogEntry -Message 'Disabling TeamViewer GUI auto-start.'
    Set-ADTRegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\TeamViewer\DefaultSettings' -Name 'Autostart_GUI' -Value 0 -Type DWord

    ## Assign the device to the Stratum Reservoir company (Management Console) when an assignment ID is configured.
    $teamViewerExe = Join-Path -Path $teamViewerInstallDir -ChildPath 'TeamViewer.exe'
    if ([string]::IsNullOrWhiteSpace($teamViewerAssignmentId))
    {
        Write-ADTLogEntry -Message 'No TeamViewer assignment ID configured; skipping company assignment.' -Severity 2
    }
    elseif (!(Test-Path -LiteralPath $teamViewerExe -PathType Leaf))
    {
        Write-ADTLogEntry -Message "TeamViewer.exe was not found at [$teamViewerExe]; cannot run company assignment." -Severity 2
    }
    else
    {
        ## Give the TeamViewer service time to start before assigning.
        Start-Sleep -Seconds 30
        Write-ADTLogEntry -Message 'Assigning the device to the TeamViewer company account.'
        Start-ADTProcess -FilePath $teamViewerExe -ArgumentList "assignment --id $teamViewerAssignmentId --device-alias=$env:COMPUTERNAME --retries=3 --timeout=120" -CreateNoWindow -IgnoreExitCodes '*'
    }

    ## Close any TeamViewer GUI the installer may have started.
    Get-Process -Name 'TeamViewer' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
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

    ## Show Welcome Message, ask the user to close TeamViewer if it is running, and only force closure after the countdown expires.
    ## No BlockExecution: the TeamViewer service can relaunch the GUI, which would repeatedly show the "blocked" dialog.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'TeamViewer Upgrade'
        Subtitle = 'TeamViewer is being upgraded. Any active TeamViewer session will be disconnected. Please save your work within 5 minutes, or TeamViewer will be closed automatically.'
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

    if (Test-TeamViewerClonedIdentity)
    {
        ## Device was deployed with the old package (cloned identity): full reset, then clean install + assignment.
        Reset-TeamViewerIdentity
    }
    else
    {
        ## Remove installs that cannot be upgraded in place (32-bit, MSI-based, or full client).
        ## Older 64-bit Host installs are upgraded in place by the new installer.
        Remove-TeamViewer -IncompatibleOnly
    }


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage "Installing TeamViewer Host $($adtSession.AppVersion)..."
    Install-TeamViewer

    ## <Perform Installation tasks here>


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Set-TeamViewerConfiguration

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

    ## Show Welcome Message, ask the user to close TeamViewer if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'TeamViewer Uninstall'
        Subtitle = 'TeamViewer is being removed. Any active TeamViewer session will be disconnected. Please save your work within 5 minutes, or TeamViewer will be closed automatically.'
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


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Remove all TeamViewer installations (32-bit and 64-bit, EXE or MSI).
    Remove-TeamViewer

    ## <Perform Uninstallation tasks here>


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>

    if (Get-ADTApplication -Name 'TeamViewer' -NameMatch 'Contains')
    {
        Write-ADTLogEntry -Message 'TeamViewer is still registered as installed. Manual cleanup may be required.' -Severity 2
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

    ## Show Welcome Message, ask the user to close TeamViewer if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'TeamViewer Repair'
        Subtitle = 'TeamViewer is being repaired. Any active TeamViewer session will be disconnected. Please save your work within 5 minutes, or TeamViewer will be closed automatically.'
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

    ## Repair by reinstalling over the existing installation.
    Install-TeamViewer

    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Set-TeamViewerConfiguration

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

