<#
.SYNOPSIS
    SCCM Configuration Item - REMEDIATION script: assign TeamViewer Host to the company.
.DESCRIPTION
    Runs as SYSTEM when the discovery script returns NonCompliant:
      1. Skips devices with no TeamViewer, or with the identity cloned by the old package
         (those are fixed by the TeamViewer application package, which resets and reinstalls).
      2. Starts the TeamViewer service if it is stopped.
      3. Runs: TeamViewer.exe assignment --id <Assignment ID> --device-alias=<COMPUTERNAME> --retries=3 --timeout=120
      4. Re-checks the assignment state and logs the result.
    Log: C:\Windows\Logs\Software\TeamViewer_AssignmentRemediation.log
.NOTES
    Also usable as an Intune Remediations remediation script.
#>

$ErrorActionPreference = 'Stop'

## Assignment ID (Admin settings > Device Management > Rollout set-up > ... > Copy ID). Treat as a secret.
$assignmentId = '0001CoABChA3805QzyAR75VT-SlwpNETEigIACAAAgAJACDS-j2j8YVc1GfanRYkd4kFvBvigAoJKWBcq-8VazB7GkBIIXo9VBmolDuZjV0jI4-WXVYMA64LhEn-x16rTEJdmmrRjiClr63DAFHdB8I7Ar_jUUMrhLjnIaIpzCgdYQiUIAEQ0rDsjwc='

## Rollout configuration the device must be assigned to.
## The GUID is embedded in the assignment ID below; TeamViewer records it on the device as
## HKLM\SOFTWARE\TeamViewer\ManagedDeviceV2AssignmentId after a successful assignment.
$expectedAssignmentConfigId = '{37f34e50-cf20-11ef-9553-f92970a4d113}'

## Identity cloned onto devices by the old TeamViewer package (imported TeamViewer_CompanySettings.reg).
## These devices need the TeamViewer application package (identity reset + reinstall), not just re-assignment.
$clonedManagementId = '{b7113481-c353-42ea-bd40-6856e85ef3f6}'
$clonedIntuneDeviceId = '{d4e066e4-52d7-49b6-935c-bc7b4c613548}'

$teamViewerExe = Join-Path -Path $env:ProgramFiles -ChildPath 'TeamViewer\TeamViewer.exe'
$tvRoot = 'HKLM:\SOFTWARE\TeamViewer'
$tvDm = 'HKLM:\SOFTWARE\TeamViewer\DeviceManagementV2'

function Get-TeamViewerAssignmentState {
    [CmdletBinding()]
    param()

    if (!(Test-Path -LiteralPath $teamViewerExe -PathType Leaf)) {
        return 'NotInstalled'
    }

    $managementId = [string](Get-ItemProperty -Path $tvDm -Name 'ManagementId' -ErrorAction SilentlyContinue).ManagementId
    $intuneDeviceId = [string](Get-ItemProperty -Path $tvRoot -Name 'IntuneDeviceId' -ErrorAction SilentlyContinue).IntuneDeviceId
    $assignmentId = [string](Get-ItemProperty -Path $tvRoot -Name 'ManagedDeviceV2AssignmentId' -ErrorAction SilentlyContinue).ManagedDeviceV2AssignmentId

    if ($managementId -eq $clonedManagementId -or $intuneDeviceId -eq $clonedIntuneDeviceId) {
        return 'ClonedIdentity'
    }
    if ([string]::IsNullOrWhiteSpace($managementId)) {
        return 'NotAssigned'
    }
    if ($assignmentId -ne $expectedAssignmentConfigId) {
        return 'WrongAssignment'
    }
    return 'Assigned'
}

$logDir = Join-Path -Path $env:SystemRoot -ChildPath 'Logs\Software'
$logFile = Join-Path -Path $logDir -ChildPath 'TeamViewer_AssignmentRemediation.log'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (!(Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Value $line
    }
    catch { }
    Write-Output $line
}

## TeamViewer exit codes for "assignment" (TeamViewer KB "Deploy TeamViewer - 9/9").
$assignmentErrors = @{
    1   = 'Invalid command line arguments'
    2   = 'Signature verification error'
    3   = 'TeamViewer not installed'
    400 = 'Invalid argument / invalid assignment ID'
    401 = 'TeamViewer service not running'
    402 = 'Incompatible service version (reinstall TeamViewer)'
    403 = 'Not online - could not reach the TeamViewer cloud'
    404 = 'Another assignment is already running'
    405 = 'Timeout'
    406 = 'Failed for unknown reason'
    407 = 'Access denied (needs administrator/SYSTEM)'
    408 = 'Denied by policy (an active TeamViewer policy blocks re-assignment)'
}

try {
    Write-Log -Message "===== TeamViewer assignment remediation started on $env:COMPUTERNAME ====="
    $state = Get-TeamViewerAssignmentState
    Write-Log -Message "Current state: $state"

    switch ($state) {
        'NotInstalled' {
            Write-Log -Message 'TeamViewer is not installed. Nothing to do.'
            exit 0
        }
        'Assigned' {
            Write-Log -Message 'Device is already assigned to the expected rollout configuration. Nothing to do.'
            exit 0
        }
        'ClonedIdentity' {
            Write-Log -Level 'WARN' -Message 'Device carries the identity cloned by the old TeamViewer package. Re-assignment alone cannot fix this; deploy the TeamViewer application package (resets identity, reinstalls, assigns).'
            exit 1
        }
    }

    ## Assignment needs the TeamViewer service.
    $service = Get-Service -Name 'TeamViewer' -ErrorAction SilentlyContinue
    if (!$service) {
        Write-Log -Level 'ERROR' -Message 'TeamViewer service not found. Reinstall TeamViewer with the application package.'
        exit 1
    }
    if ($service.Status -ne 'Running') {
        Write-Log -Message 'Starting the TeamViewer service.'
        Start-Service -Name 'TeamViewer'
        Start-Sleep -Seconds 20
    }

    $arguments = "assignment --id $assignmentId --device-alias=$env:COMPUTERNAME --retries=3 --timeout=120"
    Write-Log -Message "Running: TeamViewer.exe assignment --id <redacted> --device-alias=$env:COMPUTERNAME --retries=3 --timeout=120"
    $process = Start-Process -FilePath $teamViewerExe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Log -Message 'Assignment command completed successfully.'
    }
    else {
        $reason = if ($assignmentErrors.ContainsKey($exitCode)) { $assignmentErrors[$exitCode] } else { 'Unknown error' }
        Write-Log -Level 'ERROR' -Message "Assignment failed with exit code $exitCode - $reason."
    }

    Start-Sleep -Seconds 10
    $newState = Get-TeamViewerAssignmentState
    Write-Log -Message "State after remediation: $newState"
    Write-Log -Message '===== TeamViewer assignment remediation finished ====='

    if ($newState -eq 'Assigned') { exit 0 }
    if ($exitCode -ne 0) { exit $exitCode }
    exit 1
}
catch {
    Write-Log -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"
    exit 1
}
