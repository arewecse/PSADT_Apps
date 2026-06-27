param(
    [string]$MinimumVersion = '',
    [bool]$EnforceMinimumVersion = $false,
    [bool]$RequireProtect = $true
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Intune Win32 app detection rule (custom script):
#   exit 0 + STDOUT  -> detected (compliant)
#   exit 1, no STDOUT -> not detected or below minimum version (will (re)install)

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
        exit 1
    }

    $entries = Get-UninstallRegistryEntries

    $opticsEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylanceOPTICS' } | Select-Object -First 1

    if ($RequireProtect) {
        $protectEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylancePROTECT' } | Select-Object -First 1
        if (!$protectEntry) {
            exit 1
        }
    }

    if (!$opticsEntry) {
        exit 1
    }

    $opticsVersion = ConvertTo-ParsedVersion -VersionText ([string]$opticsEntry.DisplayVersion)

    if ($EnforceMinimumVersion) {
        if ($minimumParsed -and (!$opticsVersion -or $opticsVersion -lt $minimumParsed)) {
            exit 1
        }
    }

    Write-Output "Detected: $($opticsEntry.DisplayName) [$($opticsEntry.DisplayVersion)]"
    exit 0
}
catch {
    exit 1
}
