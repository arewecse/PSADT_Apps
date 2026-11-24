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
    AppName = 'Visual Studio Community 2026'
    AppVersion = '18.11.2'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(
        @{ Name = 'devenv'; Description = 'Visual Studio' }
    )
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-11-24'
    AppScriptAuthor = 'EUC Team'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Visual Studio Community 2026'
    InstallTitle = 'Visual Studio Community 2026 Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

$appFiles = @{
    # Visual Studio Community 2026 bootstrapper from Microsoft. It downloads the product from Microsoft during the install.
    Setup = Join-Path -Path $PSScriptRoot -ChildPath 'Files\vs_community.exe'
}

## Workloads delivered by this package. Keep this list in sync with RequiredWorkloads in DetectionScripts\Detect-VisualStudioCommunity-*.ps1.
$vsWorkloads = @(
    'Microsoft.VisualStudio.Workload.ManagedDesktop'    # .NET desktop development
    'Microsoft.VisualStudio.Workload.NetWeb'            # ASP.NET and web development
)

## --includeRecommended adds each workload's recommended components, the same as ticking the workload in the Visual Studio Installer.
$vsWorkloadArguments = (($vsWorkloads | ForEach-Object { "--add $_" }) -join ' ') + ' --includeRecommended'

## --norestart stops the Visual Studio Installer from restarting the device by itself; a required restart is reported as exit code 3010 instead.
$vsSilentArguments = '--quiet --norestart'

$vsProductId = 'Microsoft.VisualStudio.Product.Community'

## Visual Studio 2026 is major version 18.
$vsVersionRange = '[18.0,19.0)'

$vsInstallerDir = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio\Installer'
$vsInstallerExe = Join-Path -Path $vsInstallerDir -ChildPath 'setup.exe'
$vsWhereExe = Join-Path -Path $vsInstallerDir -ChildPath 'vswhere.exe'

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

function Get-VisualStudioInstallPath
{
    [CmdletBinding()]
    param
    (
        ## Only return instances that already have every workload in $vsWorkloads.
        [System.Management.Automation.SwitchParameter]$RequireWorkloads
    )

    ## vswhere.exe ships with the Visual Studio Installer, so when it is missing there is no Visual Studio instance to find.
    if (!(Test-Path -LiteralPath $vsWhereExe -PathType Leaf))
    {
        return
    }

    ## -all also returns instances that are waiting on a restart or whose setup did not finish, so they can still be updated or removed.
    $vsWhereArguments = @('-all', '-products', $vsProductId, '-version', $vsVersionRange, '-property', 'installationPath', '-nologo')
    if ($RequireWorkloads)
    {
        $vsWhereArguments += '-requires'
        $vsWhereArguments += $vsWorkloads
    }

    $installPaths = & $vsWhereExe @vsWhereArguments
    if ($LASTEXITCODE -ne 0)
    {
        throw "vswhere.exe failed with exit code [$LASTEXITCODE]."
    }

    $installPaths | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().TrimEnd('\') }
}

function Install-VisualStudio
{
    [CmdletBinding()]
    param()

    $installPaths = @(Get-VisualStudioInstallPath)
    if (!$installPaths)
    {
        Write-ADTLogEntry -Message "No existing Visual Studio Community 2026 installation detected. Installing with workloads [$($vsWorkloads -join ', ')]."
        Start-ADTProcess -FilePath $appFiles.Setup -ArgumentList "$vsWorkloadArguments $vsSilentArguments --wait" -WindowStyle Hidden
        return
    }

    foreach ($installPath in $installPaths)
    {
        ## An update only services what is already installed and cannot add components, so update first and then add the workloads.
        Write-ADTLogEntry -Message "Updating the existing Visual Studio Community 2026 installation at [$installPath]."
        Start-ADTProcess -FilePath $appFiles.Setup -ArgumentList "update --installPath `"$installPath`" $vsSilentArguments --wait" -WindowStyle Hidden

        Write-ADTLogEntry -Message "Adding workloads [$($vsWorkloads -join ', ')] to [$installPath]."
        Start-ADTProcess -FilePath $appFiles.Setup -ArgumentList "modify --installPath `"$installPath`" $vsWorkloadArguments $vsSilentArguments --wait" -WindowStyle Hidden
    }
}

function Uninstall-VisualStudio
{
    [CmdletBinding()]
    param()

    $installPaths = @(Get-VisualStudioInstallPath)
    if (!$installPaths)
    {
        Write-ADTLogEntry -Message 'Visual Studio Community 2026 is not installed; nothing to uninstall.' -Severity 2
        return
    }

    if (!(Test-Path -LiteralPath $vsInstallerExe -PathType Leaf))
    {
        throw "The Visual Studio Installer was not found at [$vsInstallerExe]."
    }

    foreach ($installPath in $installPaths)
    {
        ## The installed setup.exe does not support --wait (bootstrapper only), so wait for any child processes it starts instead.
        Write-ADTLogEntry -Message "Uninstalling Visual Studio Community 2026 from [$installPath]."
        Start-ADTProcess -FilePath $vsInstallerExe -ArgumentList "uninstall --installPath `"$installPath`" $vsSilentArguments" -WaitForChildProcesses -WindowStyle Hidden
    }
}

function Repair-VisualStudio
{
    [CmdletBinding()]
    param()

    $installPaths = @(Get-VisualStudioInstallPath)
    if (!$installPaths)
    {
        Write-ADTLogEntry -Message 'Visual Studio Community 2026 is not installed; installing it instead of repairing.' -Severity 2
        Install-VisualStudio
        return
    }

    foreach ($installPath in $installPaths)
    {
        Write-ADTLogEntry -Message "Repairing Visual Studio Community 2026 at [$installPath]."
        Start-ADTProcess -FilePath $appFiles.Setup -ArgumentList "repair --installPath `"$installPath`" $vsSilentArguments --wait" -WindowStyle Hidden
    }
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

    ## Show Welcome Message, ask the user to close Visual Studio if it is running, and only force closure after the countdown expires.
    ## BlockExecution is deliberately not used: the Visual Studio Installer starts devenv.exe itself to finish configuring the product.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Visual Studio Community 2026 Upgrade'
        Subtitle = 'Visual Studio Community 2026 is being upgraded. Please save your work and close Visual Studio within 5 minutes, or it will be closed automatically.'
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


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Installing Visual Studio Community 2026. The components are downloaded during the installation, so this can take a while...'
    Install-VisualStudio

    ## <Perform Installation tasks here>


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## Confirm the workloads are really present rather than relying on the installer exit code alone.
    if (!(Get-VisualStudioInstallPath -RequireWorkloads))
    {
        throw "Visual Studio Community 2026 with workloads [$($vsWorkloads -join ', ')] was not found after the installation. Review the dd_*.log files in [$env:TEMP]."
    }

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

    ## Show Welcome Message, ask the user to close Visual Studio if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Visual Studio Community 2026 Uninstall'
        Subtitle = 'Visual Studio Community 2026 is being uninstalled. Please save your work and close Visual Studio within 5 minutes, or it will be closed automatically.'
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

    ## Only Visual Studio Community 2026 is removed. The shared Visual Studio Installer is left in place because
    ## other Visual Studio products on the device (Build Tools, SQL Server Management Studio, ...) depend on it.
    Uninstall-VisualStudio

    ## <Perform Uninstallation tasks here>


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>

    if (Get-VisualStudioInstallPath)
    {
        Write-ADTLogEntry -Message 'Visual Studio Community 2026 is still registered as installed. Manual cleanup may be required.' -Severity 2
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

    ## Show Welcome Message, ask the user to close Visual Studio if it is running, and only force closure after the countdown expires.
    $saiwParams = @{
        CheckDiskSpace = $true
        PersistPrompt = $true
        Title = 'Visual Studio Community 2026 Repair'
        Subtitle = 'Visual Studio Community 2026 is being repaired. Please save your work and close Visual Studio within 5 minutes, or it will be closed automatically.'
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

    Show-ADTInstallationProgress -StatusMessage 'Repairing Visual Studio Community 2026. This can take a while...'
    Repair-VisualStudio

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

