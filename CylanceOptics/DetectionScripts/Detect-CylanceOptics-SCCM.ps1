param(
    [string]$MinimumVersion = '3.4.2263.0',
    [bool]$EnforceMinimumVersion = $true,
    [bool]$RequireProtect = $true
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected or below minimum version
# The exit code is ignored by SCCM, so this script always exits 0.

function ConvertTo-ParsedVersion {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $parsed = $null
    if ([version]::TryParse($VersionText, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-UninstallRegistryEntries {
    [CmdletBinding()]
    param()

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $uninstallRoots) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }
}

try {
    $minimumParsed = ConvertTo-ParsedVersion -VersionText $MinimumVersion

    if ($EnforceMinimumVersion -and ($MinimumVersion -and !$minimumParsed)) {
        exit 0
    }

    $entries = Get-UninstallRegistryEntries

    $opticsEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylanceOPTICS' } | Select-Object -First 1

    if ($RequireProtect) {
        $protectEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylancePROTECT' } | Select-Object -First 1
        if (!$protectEntry) {
            exit 0
        }
    }

    if ($opticsEntry) {
        $opticsVersion = ConvertTo-ParsedVersion -VersionText ([string]$opticsEntry.DisplayVersion)

        $isDetected = $true
        if ($EnforceMinimumVersion) {
            if ($minimumParsed -and (!$opticsVersion -or $opticsVersion -lt $minimumParsed)) {
                $isDetected = $false
            }
        }

        if ($isDetected) {
            Write-Output "Detected: $($opticsEntry.DisplayName) [$($opticsEntry.DisplayVersion)]"
        }
    }

    exit 0
}
catch {
    exit 0
}
