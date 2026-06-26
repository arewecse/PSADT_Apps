$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected
# The exit code is ignored by SCCM, so this script always exits 0.

function Get-MSTeamsDetection {
    [CmdletBinding()]
    param()

    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'MSTeams' } | Select-Object -First 1
    if ($provisioned) {
        return [pscustomobject]@{
            Detected = $true
            Detail   = "Provisioned package MSTeams ($($provisioned.PackageName))"
        }
    }

    $installedAllUsers = Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installedAllUsers) {
        return [pscustomobject]@{
            Detected = $true
            Detail   = "AppX package MSTeams ($($installedAllUsers.Version))"
        }
    }

    return [pscustomobject]@{
        Detected = $false
        Detail   = $null
    }
}

try {
    $result = Get-MSTeamsDetection
    if ($result.Detected) {
        Write-Output "Detected: $($result.Detail)"
    }

    exit 0
}
catch {
    exit 0
}
