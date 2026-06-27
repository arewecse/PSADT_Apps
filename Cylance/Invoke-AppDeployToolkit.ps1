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
    AppVendor = 'Microsoft'
    AppName = 'Microsoft Teams (Machine-Wide)'
    AppVersion = '1.0.0'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'Teams'; Description = 'Microsoft Teams (Classic)' },
        @{ Name = 'ms-teams'; Description = 'Microsoft Teams (New)' }
    )
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-06-26'
    AppScriptAuthor = 'EUC Team'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Microsoft Teams (Machine-Wide)'
    InstallTitle = 'Microsoft Teams Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

$appFiles = @{
    # Teams bootstrapper executable and optional offline MSIX package.
    Bootstrapper = Join-Path -Path $PSScriptRoot -ChildPath 'Files\teamsbootstrapper.exe'
    OfflineMsix = Join-Path -Path $PSScriptRoot -ChildPath 'Files\MSTeams-x64.msix'
}

function Get-UserProfilePaths
{
    [CmdletBinding()]
    param()

    $exclude = @('All Users', 'Default', 'Default User', 'defaultuser0', 'Public')
    Get-ChildItem -Path "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $exclude } |
        Select-Object -ExpandProperty FullName
}

function Remove-ClassicTeamsPerUserInstallations
{
    [CmdletBinding()]
    param()

    foreach ($procName in @('Teams', 'ms-teams', 'Update'))
    {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($profilePath in (Get-UserProfilePaths))
    {
        $teamsRoot = Join-Path -Path $profilePath -ChildPath 'AppData\Local\Microsoft\Teams'
        $updateExe = Join-Path -Path $teamsRoot -ChildPath 'Update.exe'
        if (Test-Path -LiteralPath $updateExe -PathType Leaf)
        {
            try
            {
                Start-ADTProcess -FilePath $updateExe -ArgumentList '--uninstall -s' -WindowStyle Hidden -SuccessExitCodes 0, 3010
            }
            catch
            {
                Write-ADTLogEntry -Message "Classic Teams uninstall invocation failed for profile [$profilePath]. Continuing. Error: $($_.Exception.Message)" -Severity 2
            }
        }

        if (Test-Path -LiteralPath $teamsRoot -PathType Container)
        {
            try
            {
                Remove-Item -LiteralPath $teamsRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch
            {
                Write-ADTLogEntry -Message "Classic Teams cleanup failed for [$teamsRoot]. Continuing. Error: $($_.Exception.Message)" -Severity 2
            }
        }
    }
}

function Get-UninstallRegistryEntries
{
    [CmdletBinding()]
    param()

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $uninstallRoots)
    {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }
}

function Remove-ClassicTeamsMachineWideInstaller
{
    [CmdletBinding()]
    param()

    $entries = Get-UninstallRegistryEntries | Where-Object {
        $_.DisplayName -eq 'Teams Machine-Wide Installer'
    }

    foreach ($entry in $entries)
    {
        if ([string]::IsNullOrWhiteSpace($entry.PSChildName))
        {
            continue
        }

        Write-ADTLogEntry -Message "Uninstalling legacy Teams Machine-Wide Installer [$($entry.PSChildName)]."
        Start-ADTProcess -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList "/x $($entry.PSChildName) /qn REBOOT=ReallySuppress" -WindowStyle Hidden -SuccessExitCodes 0, 1605, 1614, 3010
    }
}

function Install-NewTeamsMachineWide
{
    [CmdletBinding()]
    param()

    if (!(Test-Path -LiteralPath $appFiles.Bootstrapper -PathType Leaf))
    {
        throw "Required installer file is missing: $($appFiles.Bootstrapper)"
    }

    # Prefer online provisioning to ensure the newest Teams build is installed.
    try
    {
        Start-ADTProcess -FilePath $appFiles.Bootstrapper -ArgumentList '-p' -WindowStyle Hidden -SuccessExitCodes 0, 3010
        return
    }
    catch
    {
        # Fall back to offline MSIX only when online provisioning fails.
        if (!(Test-Path -LiteralPath $appFiles.OfflineMsix -PathType Leaf))
        {
            throw
        }

        Write-ADTLogEntry -Message "Online Teams provisioning failed. Falling back to offline MSIX at [$($appFiles.OfflineMsix)]. Error: $($_.Exception.Message)" -Severity 2
        $arguments = "-p -o `"$($appFiles.OfflineMsix)`""
        Start-ADTProcess -FilePath $appFiles.Bootstrapper -ArgumentList $arguments -WindowStyle Hidden -SuccessExitCodes 0, 3010
    }
}

function Uninstall-NewTeamsMachineWide
{
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $appFiles.Bootstrapper -PathType Leaf)
    {
        Start-ADTProcess -FilePath $appFiles.Bootstrapper -ArgumentList '-x -m' -WindowStyle Hidden -SuccessExitCodes 0, 3010
    }

    Get-AppxPackage -Name 'MSTeams' -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
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

    ## Show Welcome Message, ask the user to close Teams if running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Microsoft Teams Upgrade'
        Subtitle = 'Microsoft Teams is being installed machine-wide. Please save your work and close Teams within 5 minutes, or it will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
        $saiwParams.Add('BlockExecution', $true)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Installation tasks here>


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Microsoft guidance recommends removing classic per-user Teams before deploying new Teams machine-wide.
    Remove-ClassicTeamsPerUserInstallations
    Remove-ClassicTeamsMachineWideInstaller
    Install-NewTeamsMachineWide

    ## <Perform Installation tasks here>


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

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

    ## Show Welcome Message, ask the user to close Teams if running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Microsoft Teams Uninstall'
        Subtitle = 'Microsoft Teams is being uninstalled. Please save your work and close Teams within 5 minutes, or it will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
        $saiwParams.Add('BlockExecution', $true)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Uninstall-NewTeamsMachineWide
    Remove-ClassicTeamsPerUserInstallations
    Remove-ClassicTeamsMachineWideInstaller

    ## <Perform Uninstallation tasks here>


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>
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

    ## Show Welcome Message, ask the user to close Teams if running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Microsoft Teams Repair'
        Subtitle = 'Microsoft Teams is being repaired. Please save your work and close Teams within 5 minutes, or it will be closed automatically.'
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0)
    {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
        $saiwParams.Add('ForceCloseProcessesCountdown', 300)
        $saiwParams.Add('BlockExecution', $true)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Repair tasks here>


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Remove-ClassicTeamsPerUserInstallations
    Remove-ClassicTeamsMachineWideInstaller
    Install-NewTeamsMachineWide

    ## <Perform Repair tasks here>


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

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

