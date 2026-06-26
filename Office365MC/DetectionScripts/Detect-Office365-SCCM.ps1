param(
    # Product release ID expected in the Click-to-Run configuration (matches configuration.xml <Product ID=...>).
    [string]$ProductReleaseId = 'O365ProPlusEEANoTeamsRetail',
    [string]$MinimumVersion = '16.0.20026.20166'
)

$ErrorActionPreference = 'Stop'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected
# The exit code is ignored by SCCM, so this script always exits 0.

try {
    $configKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (!(Test-Path -LiteralPath $configKey)) {
        exit 0
    }

    $config = Get-ItemProperty -LiteralPath $configKey -ErrorAction SilentlyContinue
    if (!$config) {
        exit 0
    }

    # Confirm the expected product is part of the installed Click-to-Run package.
    $productReleaseIds = [string]$config.ProductReleaseIds
    if ([string]::IsNullOrWhiteSpace($productReleaseIds) -or ($productReleaseIds -split ',') -notcontains $ProductReleaseId) {
        exit 0
    }

    $reportedVersion = [string]$config.VersionToReport
    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($reportedVersion) -or ![version]::TryParse($reportedVersion, [ref]$parsed)) {
        exit 0
    }

    if ($parsed -ge [version]$MinimumVersion) {
        Write-Output "Detected: $ProductReleaseId $reportedVersion"
    }

    exit 0
}
catch {
    exit 0
}
