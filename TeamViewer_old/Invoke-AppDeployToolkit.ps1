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
    AppVendor                   = 'TeamViewer'
    AppName                     = 'TeamViewer Host'
    AppVersion                  = '15.73.5'
    AppArch                     = 'x64'
    AppLang                     = 'EN'
    AppRevision                 = '01'
    AppSuccessExitCodes         = @(0)
    AppRebootExitCodes          = @(1641, 3010)
    # TeamViewer processes that should be closed before installation
    # Note: TeamViewer_Service is a Windows service, not a process to close
    AppProcessesToClose         = @(
        @{ Name = 'TeamViewer'; Description = 'TeamViewer Application' }
    )
    AppScriptVersion            = '1.0.0'
    AppScriptDate               = '2026-01-06'
    AppScriptAuthor             = 'OT Support Team'
    RequireAdmin                = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName                 = 'TeamViewer Host'
    InstallTitle                = 'TeamViewer Host Installation'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters   = $PSBoundParameters
    DeployAppScriptVersion      = '4.1.7'
}

function Install-ADTDeployment {
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close TeamViewer if running
    ## Note: Not blocking execution to allow TeamViewer to auto-start if needed
    $saiwParams = @{
        CheckDiskSpace               = $true
        PersistPrompt                = $true
        ForceCloseProcessesCountdown = 300  # 5 minutes countdown before auto-closing
    }
    if ($adtSession.AppProcessesToClose.Count -gt 0) {
        $saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
    }
    Show-ADTInstallationWelcome @saiwParams

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Installation tasks here>

    ## Define path for TeamViewer installer
    $TeamViewerInstaller = "$($adtSession.DirFiles)\TeamViewer_Host_Setup_x64.exe"

    ## ============================================
    ## Stop TeamViewer service before uninstall
    ## ============================================
    Write-ADTLogEntry -Message "Stopping TeamViewer service if running..."
    Stop-Service -Name 'TeamViewer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    ## ============================================
    ## Check for existing TeamViewer installation
    ## ============================================
    Write-ADTLogEntry -Message "Checking for existing TeamViewer installation..."
    
    $ExistingTeamViewer = Get-ADTApplication -Name '*TeamViewer*' -ErrorAction SilentlyContinue
    
    if ($ExistingTeamViewer) {
        foreach ($app in $ExistingTeamViewer) {
            Write-ADTLogEntry -Message "Found existing TeamViewer installation: $($app.DisplayName) v$($app.DisplayVersion)"
            
            ## ============================================
            ## Uninstall existing TeamViewer
            ## ============================================
            Write-ADTLogEntry -Message "Removing existing TeamViewer installation..."
            Show-ADTInstallationProgress -StatusMessage "Removing existing TeamViewer..."
            
            ## Check if this is an MSI installation (UninstallString contains MsiExec)
            if ($app.UninstallString -match 'MsiExec') {
                Write-ADTLogEntry -Message "MSI-based installation detected. Using MSI uninstall..."
                
                ## Extract the product code from UninstallString
                if ($app.UninstallString -match '\{[A-F0-9\-]+\}') {
                    $ProductCode = $Matches[0]
                    Write-ADTLogEntry -Message "Found MSI Product Code: $ProductCode"
                    Start-ADTProcess -FilePath 'msiexec.exe' -ArgumentList "/x $ProductCode /qn /norestart" -IgnoreExitCodes '3010,1605'
                    Start-Sleep -Seconds 5
                }
            }
            else {
                ## For EXE-based installations, use the uninstall string
                if ($app.UninstallString) {
                    $UninstallCmd = $app.UninstallString -replace '"', ''
                    if (Test-Path -Path $UninstallCmd) {
                        Write-ADTLogEntry -Message "Running uninstaller from registry: $UninstallCmd"
                        Start-ADTProcess -FilePath $UninstallCmd -ArgumentList '/S'
                        Start-Sleep -Seconds 5
                    }
                }
            }
            
            Write-ADTLogEntry -Message "TeamViewer removal completed."
        }
    }
    else {
        Write-ADTLogEntry -Message "No existing TeamViewer installation detected. Proceeding with fresh install."
    }


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI installations.
    if ($adtSession.UseDefaultMsi) {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile) {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
        if ($adtSession.DefaultMspFiles) {
            $adtSession.DefaultMspFiles | Start-ADTMsiProcess -Action Patch
        }
    }

    ## <Perform Installation tasks here>

    ## Install TeamViewer Host
    Write-ADTLogEntry -Message "Installing TeamViewer Host..."
    Show-ADTInstallationProgress -StatusMessage "Installing TeamViewer Host $($adtSession.AppVersion)..."
    
    if (Test-Path -Path $TeamViewerInstaller) {
        Write-ADTLogEntry -Message "Running TeamViewer Host installer: $TeamViewerInstaller"
        ## Use /S for silent installation with settingsfile parameter to prevent company assignment dialog
        ## The custom installer from custom.teamviewer.com should contain the configuration
        Start-ADTProcess -FilePath $TeamViewerInstaller -ArgumentList '/S /norestart settingsfile=0' -IgnoreExitCodes '3010'
        Write-ADTLogEntry -Message "TeamViewer Host installation completed."
        
        ## Wait for TeamViewer service to initialize before applying settings
        Write-ADTLogEntry -Message "Waiting for TeamViewer service to initialize..."
        Start-Sleep -Seconds 10
    }
    else {
        Write-ADTLogEntry -Message "TeamViewer installer not found at: $TeamViewerInstaller" -Severity 3
        throw "TeamViewer installer not found. Cannot proceed with installation."
    }

    ## ============================================
    ## Apply TeamViewer Company Settings (Pre-Configuration)
    ## ============================================
    Write-ADTLogEntry -Message "Applying TeamViewer company settings..."
    try {
        # Import full company configuration to prevent assignment dialog
        $CompanyRegFile = "$($adtSession.DirSupportFiles)\TeamViewer_CompanySettings.reg"
        if (Test-Path -Path $CompanyRegFile) {
            Write-ADTLogEntry -Message "Importing TeamViewer company settings: $CompanyRegFile"
            Start-ADTProcess -FilePath 'reg.exe' -ArgumentList "import `"$CompanyRegFile`" /reg:64" -WindowStyle Hidden
            Write-ADTLogEntry -Message "TeamViewer company settings imported successfully."
        }
        else {
            Write-ADTLogEntry -Message "Company settings registry file not found at: $CompanyRegFile" -Severity 2
            Write-ADTLogEntry -Message "Installation will continue but may show company assignment dialog." -Severity 2
        }
    }
    catch {
        Write-ADTLogEntry -Message "Could not import company settings: $($_.Exception.Message)" -Severity 2
    }

    ## ============================================
    ## Prevent TeamViewer GUI from auto-starting
    ## ============================================
    Write-ADTLogEntry -Message "Disabling TeamViewer GUI auto-start..."
    try {
        # Import registry file to prevent GUI from auto-starting (service will still run for remote access)
        $RegFile = "$($adtSession.DirSupportFiles)\TeamViewer_DisableGUI.reg"
        if (Test-Path -Path $RegFile) {
            Start-ADTProcess -FilePath 'reg.exe' -ArgumentList "import `"$RegFile`" /reg:64" -WindowStyle Hidden
            Write-ADTLogEntry -Message "TeamViewer GUI auto-start disabled via registry import."
        }
        else {
            Write-ADTLogEntry -Message "Registry file not found, using PowerShell method..." -Severity 2
            # Fallback to PowerShell if reg file is missing
            # CORRECTED: Use native 64-bit registry path for 64-bit TeamViewer
            $RegPath = "HKLM:\SOFTWARE\TeamViewer\DefaultSettings"
            if (-not (Test-Path -Path $RegPath)) {
                New-Item -Path $RegPath -Force | Out-Null
            }
            Set-ItemProperty -Path $RegPath -Name "Autostart_GUI" -Value 0 -Type DWord -Force
            Write-ADTLogEntry -Message "TeamViewer GUI auto-start disabled via PowerShell."
        }
        
        # Also stop any currently running TeamViewer GUI instances
        Get-Process -Name "TeamViewer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-ADTLogEntry -Message "Stopped any running TeamViewer GUI instances."
    }
    catch {
        Write-ADTLogEntry -Message "Could not disable TeamViewer GUI auto-start: $($_.Exception.Message)" -Severity 2
    }


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Installation tasks here>

    ## Verify TeamViewer installation by checking registry
    Write-ADTLogEntry -Message "Verifying TeamViewer installation..."
    
    $InstalledTeamViewer = Get-ADTApplication -Name '*TeamViewer*' -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($InstalledTeamViewer) {
        Write-ADTLogEntry -Message "TeamViewer installation verified successfully. Version: $($InstalledTeamViewer.DisplayVersion)"
    }
    else {
        Write-ADTLogEntry -Message "Could not verify TeamViewer installation in registry." -Severity 2
    }

    ## Display a message at the end of the install.
    Show-ADTInstallationPrompt -Message "TeamViewer Host $($adtSession.AppVersion) has been installed successfully." -ButtonRightText 'OK' -Icon Information -NoWait
}

function Uninstall-ADTDeployment {
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Close TeamViewer if running before uninstall
    if ($adtSession.AppProcessesToClose.Count -gt 0) {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -ForceCloseProcessesCountdown 300
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Uninstallation tasks here>

    ## Stop TeamViewer service before uninstall
    Write-ADTLogEntry -Message "Stopping TeamViewer service if running..."
    Stop-Service -Name 'TeamViewer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI uninstallations.
    if ($adtSession.UseDefaultMsi) {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile) {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## <Perform Uninstallation tasks here>

    ## Remove TeamViewer
    Write-ADTLogEntry -Message "Removing TeamViewer..."
    Show-ADTInstallationProgress -StatusMessage "Removing TeamViewer..."
    
    $InstalledTeamViewer = Get-ADTApplication -Name '*TeamViewer*' -ErrorAction SilentlyContinue
    $RemovedSomething = $false
    
    if ($InstalledTeamViewer) {
        foreach ($app in $InstalledTeamViewer) {
            Write-ADTLogEntry -Message "Found TeamViewer to remove: $($app.DisplayName) v$($app.DisplayVersion)"
            
            ## Check if this is an MSI installation
            if ($app.UninstallString -match 'MsiExec') {
                Write-ADTLogEntry -Message "MSI-based installation detected. Using MSI uninstall..."
                
                ## Extract the product code from UninstallString
                if ($app.UninstallString -match '\{[A-F0-9\-]+\}') {
                    $ProductCode = $Matches[0]
                    Write-ADTLogEntry -Message "Found MSI Product Code: $ProductCode"
                    Start-ADTProcess -FilePath 'msiexec.exe' -ArgumentList "/x $ProductCode /qn /norestart" -IgnoreExitCodes '3010,1605'
                    $RemovedSomething = $true
                }
            }
            else {
                ## For EXE-based installations
                if ($app.UninstallString) {
                    $UninstallCmd = $app.UninstallString -replace '"', ''
                    if (Test-Path -Path $UninstallCmd) {
                        Write-ADTLogEntry -Message "Running uninstaller from registry: $UninstallCmd"
                        Start-ADTProcess -FilePath $UninstallCmd -ArgumentList '/S'
                        $RemovedSomething = $true
                    }
                }
                else {
                    Write-ADTLogEntry -Message "TeamViewer uninstaller not found." -Severity 2
                }
            }
        }
        
        ## Wait for uninstalls to complete
        Start-Sleep -Seconds 3
    }
    else {
        Write-ADTLogEntry -Message "TeamViewer was not found installed." -Severity 2
    }


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Uninstallation tasks here>

    ## Verify TeamViewer has been removed
    $RemainingTeamViewer = Get-ADTApplication -Name '*TeamViewer*' -ErrorAction SilentlyContinue
    
    if (-not $RemainingTeamViewer) {
        Write-ADTLogEntry -Message "TeamViewer has been successfully removed."
    }
    else {
        Write-ADTLogEntry -Message "TeamViewer may still be installed. Manual cleanup may be required." -Severity 2
    }

    ## Display a message at the end of the uninstall.
    Show-ADTInstallationPrompt -Message 'TeamViewer Host has been removed successfully.' -ButtonRightText 'OK' -Icon Information -NoWait
}

function Repair-ADTDeployment {
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Close TeamViewer if running before repair
    if ($adtSession.AppProcessesToClose.Count -gt 0) {
        Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -ForceCloseProcessesCountdown 300
    }

    ## Show Progress Message (with the default message).
    Show-ADTInstallationProgress

    ## <Perform Pre-Repair tasks here>

    ## Define path for TeamViewer installer
    $TeamViewerInstaller = "$($adtSession.DirFiles)\TeamViewer_Host_Setup_x64.exe"


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Handle Zero-Config MSI repairs.
    if ($adtSession.UseDefaultMsi) {
        $ExecuteDefaultMSISplat = @{ Action = $adtSession.DeploymentType; FilePath = $adtSession.DefaultMsiFile }
        if ($adtSession.DefaultMstFile) {
            $ExecuteDefaultMSISplat.Add('Transforms', $adtSession.DefaultMstFile)
        }
        Start-ADTMsiProcess @ExecuteDefaultMSISplat
    }

    ## <Perform Repair tasks here>

    ## Repair TeamViewer by reinstalling
    Write-ADTLogEntry -Message "Repairing TeamViewer..."
    Show-ADTInstallationProgress -StatusMessage "Repairing TeamViewer..."
    
    if (Test-Path -Path $TeamViewerInstaller) {
        Start-ADTProcess -FilePath $TeamViewerInstaller -ArgumentList '/S /norestart settingsfile=0' -IgnoreExitCodes '3010'
        Write-ADTLogEntry -Message "TeamViewer repair completed."
    }
    else {
        Write-ADTLogEntry -Message "TeamViewer installer not found at: $TeamViewerInstaller" -Severity 3
        throw "TeamViewer installer not found. Cannot proceed with repair."
    }


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    ## <Perform Post-Repair tasks here>

    ## Display a message at the end of the repair.
    Show-ADTInstallationPrompt -Message 'TeamViewer Host has been repaired successfully.' -ButtonRightText 'OK' -Icon Information -NoWait
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try {
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf) {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.7' } -Force
    }
    else {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.7' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch {
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try {
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process {
            if ($_.Name -match 'PSAppDeployToolkit\..+$') {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch {
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}