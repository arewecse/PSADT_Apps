param(
    # Product release ID expected in the Click-to-Run configuration (matches configuration.xml <Product ID=...>).
    [string]$ProductReleaseId = 'O365ProPlusEEANoTeamsRetail',
    [string]$MinimumVersion = '16.0.20026.20166'
)

$ErrorActionPreference = 'Stop'

# Intune Win32 app detection rule (custom script):
#   exit 0 + STDOUT  -> detected (compliant)
#   exit 1, no STDOUT -> not detected (will (re)install)

try {
    $configKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (!(Test-Path -LiteralPath $configKey)) {
        exit 1
    }

    $config = Get-ItemProperty -LiteralPath $configKey -ErrorAction SilentlyContinue
    if (!$config) {
        exit 1
    }

    # Confirm the expected product is part of the installed Click-to-Run package.
    $productReleaseIds = [string]$config.ProductReleaseIds
    if ([string]::IsNullOrWhiteSpace($productReleaseIds) -or ($productReleaseIds -split ',') -notcontains $ProductReleaseId) {
        exit 1
    }

    $reportedVersion = [string]$config.VersionToReport
    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($reportedVersion) -or ![version]::TryParse($reportedVersion, [ref]$parsed)) {
        exit 1
    }

    if ($parsed -ge [version]$MinimumVersion) {
        Write-Output "Detected: $ProductReleaseId $reportedVersion"
        exit 0
    }

    exit 1
}
catch {
    exit 1
}
