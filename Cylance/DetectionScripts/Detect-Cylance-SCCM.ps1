param(
    [string]$MinimumProtectVersion = '',
    [string]$MinimumOpticsVersion = '',
    [bool]$EnforceMinimumVersion = $false
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
    $minimumProtectParsed = ConvertTo-ParsedVersion -VersionText $MinimumProtectVersion
    $minimumOpticsParsed = ConvertTo-ParsedVersion -VersionText $MinimumOpticsVersion

    if ($EnforceMinimumVersion -and ($MinimumProtectVersion -and !$minimumProtectParsed)) {
        exit 0
    }

    if ($EnforceMinimumVersion -and ($MinimumOpticsVersion -and !$minimumOpticsParsed)) {
        exit 0
    }

    $entries = Get-UninstallRegistryEntries

    $protectEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylancePROTECT' } | Select-Object -First 1
    $opticsEntry = $entries | Where-Object { [string]$_.DisplayName -match '^CylanceOPTICS' } | Select-Object -First 1

    if ($protectEntry -and $opticsEntry) {
        $protectVersion = ConvertTo-ParsedVersion -VersionText ([string]$protectEntry.DisplayVersion)
        $opticsVersion = ConvertTo-ParsedVersion -VersionText ([string]$opticsEntry.DisplayVersion)

        $isDetected = $true
        if ($EnforceMinimumVersion) {
            if ($minimumProtectParsed -and (!$protectVersion -or $protectVersion -lt $minimumProtectParsed)) {
                $isDetected = $false
            }
            if ($minimumOpticsParsed -and (!$opticsVersion -or $opticsVersion -lt $minimumOpticsParsed)) {
                $isDetected = $false
            }
        }

        if ($isDetected) {
            Write-Output "Detected: $($protectEntry.DisplayName) [$($protectEntry.DisplayVersion)] + $($opticsEntry.DisplayName) [$($opticsEntry.DisplayVersion)]"
        }
    }

    exit 0
}
catch {
    exit 0
}
