<#
.SYNOPSIS
    Intune Remediations - DETECTION script: TeamViewer Host company assignment.
.DESCRIPTION
    Outputs a single string evaluated by the CI compliance rule (Value equals "Compliant"):
      Compliant     - TeamViewer is assigned to the Stratum Reservoir rollout configuration,
                      or TeamViewer is not installed on this device (not applicable).
      NonCompliant  - TeamViewer is installed but not assigned, assigned to another configuration,
                      or still carries the identity cloned by the old TeamViewer package.
    Read-only: makes no changes. Safe to run as often as required.
.NOTES
    Intune: exit 0 = compliant, exit 1 = run the remediation script.
#>

$ErrorActionPreference = 'Stop'

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

try {
    $state = Get-TeamViewerAssignmentState
    if ($state -in @('Assigned', 'NotInstalled')) {
        Write-Output 'Compliant'
        exit 0
    }
    Write-Output 'NonCompliant'
    exit 1
}
catch {
    Write-Output 'NonCompliant'
    exit 1
}
