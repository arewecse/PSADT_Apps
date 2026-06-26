$ErrorActionPreference = 'Stop'

# Intune Win32 app detection rule (custom script):
#   exit 0 + STDOUT  -> detected (compliant)
#   exit 1, no STDOUT -> not detected (will (re)install)

try {
    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'MSTeams' }
    if ($provisioned) {
        Write-Output "Detected: Provisioned package MSTeams ($($provisioned.PackageName))"
        exit 0
    }

    $installedAllUsers = Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction SilentlyContinue
    if ($installedAllUsers) {
        $version = ($installedAllUsers | Select-Object -First 1).Version
        Write-Output "Detected: AppX package MSTeams ($version)"
        exit 0
    }

    exit 1
}
catch {
    exit 1
}
