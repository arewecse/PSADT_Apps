param(
    [string]$MinimumVersion = '26149.1205.4798.6437',
    [bool]$EnforceMinimumVersion = $true
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

function Get-ProvisionedPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$ProvisionedPackage
    )

    $fromProperty = ConvertTo-ParsedVersion -VersionText ([string]$ProvisionedPackage.Version)
    if ($fromProperty) {
        return $fromProperty
    }

    $packageName = [string]$ProvisionedPackage.PackageName
    if ($packageName -match '^MSTeams_(\d+\.\d+\.\d+\.\d+)_') {
        return (ConvertTo-ParsedVersion -VersionText $Matches[1])
    }

    return $null
}

try {
    $minimumParsed = ConvertTo-ParsedVersion -VersionText $MinimumVersion
    if ($EnforceMinimumVersion -and !$minimumParsed) {
        exit 1
    }

    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'MSTeams' } | Select-Object -First 1
    if ($provisioned) {
        $detectedVersion = Get-ProvisionedPackageVersion -ProvisionedPackage $provisioned
        if (!$EnforceMinimumVersion -or ($detectedVersion -and $detectedVersion -ge $minimumParsed)) {
            Write-Output "Detected: Provisioned package MSTeams ($($provisioned.PackageName))"
            exit 0
        }
    }

    $installedAllUsers = Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installedAllUsers) {
        $detectedVersion = ConvertTo-ParsedVersion -VersionText ([string]$installedAllUsers.Version)
        if (!$EnforceMinimumVersion -or ($detectedVersion -and $detectedVersion -ge $minimumParsed)) {
            Write-Output "Detected: AppX package MSTeams ($($installedAllUsers.Version))"
            exit 0
        }
    }

    exit 1
}
catch {
    exit 1
}
