param(
    [string]$MinimumProtectVersion = '',
    [string]$MinimumOpticsVersion = '',
    [bool]$EnforceMinimumVersion = $false
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
    $minimumProtectParsed = ConvertTo-ParsedVersion -VersionText $MinimumProtectVersion
    $minimumOpticsParsed = ConvertTo-ParsedVersion -VersionText $MinimumOpticsVersion

    if ($EnforceMinimumVersion -and ($MinimumProtectVersion -and !$minimumProtectParsed)) {
        exit 1
    }

    if ($EnforceMinimumVersion -and ($MinimumOpticsVersion -and !$minimumOpticsParsed)) {
        exit 1
    }

    $entries = Get-UninstallRegistryEntries

    $protectEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylancePROTECT' } | Select-Object -First 1
    $opticsEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylanceOPTICS' } | Select-Object -First 1

    if (!$protectEntry -or !$opticsEntry) {
        exit 1
    }

    $protectVersion = ConvertTo-ParsedVersion -VersionText ([string]$protectEntry.DisplayVersion)
    $opticsVersion = ConvertTo-ParsedVersion -VersionText ([string]$opticsEntry.DisplayVersion)

    if ($EnforceMinimumVersion) {
        if ($minimumProtectParsed -and (!$protectVersion -or $protectVersion -lt $minimumProtectParsed)) {
            exit 1
        }

        if ($minimumOpticsParsed -and (!$opticsVersion -or $opticsVersion -lt $minimumOpticsParsed)) {
            exit 1
        }
    }

    Write-Output "Detected: $($protectEntry.DisplayName) [$($protectEntry.DisplayVersion)] + $($opticsEntry.DisplayName) [$($opticsEntry.DisplayVersion)]"
    exit 1
}
catch {
    exit 1
}
