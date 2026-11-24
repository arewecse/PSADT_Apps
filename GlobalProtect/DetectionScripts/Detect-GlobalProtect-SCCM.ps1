param(
    [string]$MinimumVersion = '6.3.3',
    [bool]$EnforceMinimumVersion = $true
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

    # GlobalProtect versions can carry a hotfix/build suffix (e.g. "6.3.3-640" or "6.3.3.640").
    # Compare on Major.Minor.Build only so hotfix builds of the same release are treated as equal.
    if ($VersionText -match '^\s*(\d+)\.(\d+)\.(\d+)') {
        return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
    }

    return $null
}

function Get-GlobalProtectInstall {
    [CmdletBinding()]
    param()

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entry = foreach ($path in $uninstallRoots) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.DisplayName -eq 'GlobalProtect' }
    }
    $entry = $entry | Select-Object -First 1
    if (!$entry) {
        return $null
    }

    $version = ConvertTo-ParsedVersion -VersionText ([string]$entry.DisplayVersion)

    # Fall back to the PanGPA.exe file version if the registry version cannot be parsed.
    if (!$version) {
        $panGpaPath = Join-Path -Path $env:ProgramFiles -ChildPath 'Palo Alto Networks\GlobalProtect\PanGPA.exe'
        if (Test-Path -LiteralPath $panGpaPath -PathType Leaf) {
            $fileInfo = (Get-Item -LiteralPath $panGpaPath).VersionInfo
            $version = [version]"$($fileInfo.FileMajorPart).$($fileInfo.FileMinorPart).$($fileInfo.FileBuildPart)"
        }
    }

    return [pscustomobject]@{
        DisplayName    = [string]$entry.DisplayName
        DisplayVersion = [string]$entry.DisplayVersion
        Version        = $version
    }
}

try {
    $minimumParsed = ConvertTo-ParsedVersion -VersionText $MinimumVersion

    if ($EnforceMinimumVersion -and ($MinimumVersion -and !$minimumParsed)) {
        exit 0
    }

    $app = Get-GlobalProtectInstall
    if ($app) {
        $isDetected = $true
        if ($EnforceMinimumVersion) {
            if ($minimumParsed -and (!$app.Version -or $app.Version -lt $minimumParsed)) {
                $isDetected = $false
            }
        }

        if ($isDetected) {
            Write-Output "Detected: $($app.DisplayName) [$($app.DisplayVersion)]"
        }
    }

    exit 0
}
catch {
    exit 0
}
