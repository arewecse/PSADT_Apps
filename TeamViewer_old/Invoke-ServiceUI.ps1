<#
.SYNOPSIS
This is a helper script to launch Invoke-AppDeployToolkit.exe via ServiceUI to force the process to become visible when deployed by Intune, or other deployment systems that run in session 0.
.DESCRIPTION
This will launch the toolkit silently if the chosen process (explorer.exe by default) is not running. If it is running, then it will launch the toolkit interactively, and use ServiceUI to do so if the current process is non-interactive.
An alternate ProcessName can be specified if you only want the toolkit to be visible when a specific application is running.
Download MDT here: https://www.microsoft.com/en-us/download/details.aspx?id=54259
There are x86 and x64 builds of ServiceUI available in MDT under 'Microsoft Deployment Toolkit\Templates\Distribution\Tools'. Rename these to ServiceUI_x86.exe and ServiceUI_x64.exe and place them with this script in the root of the toolkit next to Invoke-AppDeployToolkit.exe.
.PARAMETER ProcessName
Specifies the name of the process check for to trigger the interactive installation. Default value is 'explorer'. Multiple values can be supplied such as 'app1','app2'. The .exe extension must be omitted.
.PARAMETER DeploymentType
Specifies the type of deployment. Valid values are 'Install', 'Uninstall', or 'Repair'. Default value is 'Install'.
.PARAMETER AllowRebootPassThru
Passthru of switch to Invoke-AppDeployToolkit.exe, will instruct the toolkit to not to mask a 3010 return code with a 0.
.PARAMETER TerminalServerMode
Passthru of switch to Invoke-AppDeployToolkit.exe to enable terminal server mode.
.PARAMETER DisableLogging
Passthru of switch to Invoke-AppDeployToolkit.exe to disable logging.
.EXAMPLE
.\Invoke-ServiceUI.ps1 -ProcessName 'TeamViewer' -DeploymentType 'Install' -AllowRebootPassThru
Invoking the script from the command line.
.EXAMPLE
%SystemRoot%\System32\WindowsPowerShell\v1.0\PowerShell.exe -ExecutionPolicy Bypass -NoProfile -File Invoke-ServiceUI.ps1 -DeploymentType Install -AllowRebootPassThru
An example command line to use in Intune.
#>
param (
    ## TeamViewer processes that need to be closed for installation
    ## Only show interactive UI if these processes are running
    [string[]]$ProcessName = @('TeamViewer', 'TeamViewer_Service'),
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]$DeploymentType = 'Install',
    [switch]$AllowRebootPassThru,
    [switch]$TerminalServerMode,
    [switch]$DisableLogging
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Push-Location $PSScriptRoot

$Architecture = if (($env:PROCESSOR_ARCHITECTURE -match 64) -or ($env:PROCESSOR_ARCHITEW6432 -match 64)) {
    'x64'
}
else {
    'x86'
}

## Check if TeamViewer is running - only show interactive UI if it is
$TeamViewerRunning = [bool](Get-Process -Name $ProcessName -ErrorAction Ignore)

## Also check if a user is logged in (explorer.exe running)
$UserLoggedIn = [bool](Get-Process -Name 'explorer' -ErrorAction Ignore)

## Only use interactive mode if BOTH: user is logged in AND TeamViewer is running
$UseInteractiveMode = $UserLoggedIn -and $TeamViewerRunning

$Arguments = $(
    "-DeploymentType $DeploymentType"
    if ($UseInteractiveMode) {
        '-DeployMode Interactive'
    }
    else {
        '-DeployMode Silent'
    }
    if ($AllowRebootPassThru) {
        '-AllowRebootPassThru'
    }
    if ($TerminalServerMode) {
        '-TerminalServerMode'
    }
    if ($DisableLogging) {
        '-DisableLogging'
    }
)

if ($UseInteractiveMode) {
    if ([Environment]::UserInteractive) {
        # Start-Process is used here otherwise script does not wait for completion
        $Process = Start-Process -FilePath '.\Invoke-AppDeployToolkit.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        $ExitCode = $Process.ExitCode
    }
    else {
        # Using Start-Process with ServiceUI results in Error Code 5 (Access Denied)
        &".\ServiceUI_$Architecture.exe" -process:explorer.exe Invoke-AppDeployToolkit.exe $Arguments
        $ExitCode = $LastExitCode
    }
}
else {
    # Silent mode - no UI needed (TeamViewer not running or no user logged in)
    $Process = Start-Process -FilePath '.\Invoke-AppDeployToolkit.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    $ExitCode = $Process.ExitCode
}

Pop-Location
exit $ExitCode




