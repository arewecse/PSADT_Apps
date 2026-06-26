param(
    [string]$MinimumVersion = '16.0.20026.20166',
    [bool]$EnforceMinimumVersion = $true
)

$ErrorActionPreference = 'Stop'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected
# The exit code is ignored by SCCM, so this script always exits 0.

function Get-ClickToRunConfiguration {
    [CmdletBinding()]
    param()

    $subKey = 'SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )

    foreach ($view in $views) {
        $baseKey = $null
        $configKey = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $configKey = $baseKey.OpenSubKey($subKey)
            if ($configKey) {
                return [pscustomobject]@{
                    VersionToReport   = [string]$configKey.GetValue('VersionToReport', $null)
                }
            }
        }
        finally {
            if ($configKey) {
                $configKey.Dispose()
            }
            if ($baseKey) {
                $baseKey.Dispose()
            }
        }
    }

    return $null
}

try {
    $config = Get-ClickToRunConfiguration
    if (!$config) {
        exit 0
    }

    if (-not $EnforceMinimumVersion) {
        Write-Output 'Detected: Microsoft Office Click-to-Run'
        exit 0
    }

    $reportedVersion = [string]$config.VersionToReport
    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($reportedVersion) -or ![version]::TryParse($reportedVersion, [ref]$parsed)) {
        exit 0
    }

    if ($parsed -ge [version]$MinimumVersion) {
        Write-Output "Detected: Microsoft Office Click-to-Run $reportedVersion"
    }

    exit 0
}
catch {
    exit 0
}
