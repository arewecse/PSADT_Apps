$ErrorActionPreference = 'Stop'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected
# The exit code is ignored by SCCM, so this script always exits 0.

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
    }

    exit 0
}
catch {
    exit 0
}
