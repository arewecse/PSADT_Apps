$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Intune Win32 app detection rule (custom script):
#   exit 0 + STDOUT  -> detected (compliant)
#   exit 1, no STDOUT -> not detected (will (re)install)

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
        exit 0
    }

    exit 1
}
catch {
    exit 1
}
