param(
    [string]$MinimumVersion = '18.11.2',
    [bool]$EnforceMinimumVersion = $true,
    [string[]]$RequiredWorkloads = @(
        'Microsoft.VisualStudio.Workload.ManagedDesktop',
        'Microsoft.VisualStudio.Workload.NetWeb'
    )
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Intune Win32 app detection rule (custom script):
#   exit 0 + STDOUT  -> detected (compliant)
#   exit 1, no STDOUT -> not detected, below minimum version or missing a required workload (will (re)install)

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

    # Compare on Major.Minor.Build only, ignoring any suffix after the release number.
    if ($VersionText -match '^\s*(\d+)\.(\d+)\.(\d+)') {
        return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
    }

    return $null
}

function Get-VisualStudioCommunityInstall {
    [CmdletBinding()]
    param()

    # vswhere.exe ships with the Visual Studio Installer, so when it is missing Visual Studio is not installed.
    $vsWhereExe = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path -LiteralPath $vsWhereExe -PathType Leaf)) {
        return $null
    }

    # Visual Studio 2026 is major version 18. -requires only returns instances that have every listed workload.
    $vsWhereArguments = @('-all', '-products', 'Microsoft.VisualStudio.Product.Community', '-version', '[18.0,19.0)', '-format', 'json', '-nologo')
    if ($RequiredWorkloads) {
        $vsWhereArguments += '-requires'
        $vsWhereArguments += $RequiredWorkloads
    }

    $json = (& $vsWhereExe @vsWhereArguments) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    $instances = ConvertFrom-Json -InputObject $json
    $installs = foreach ($instance in $instances) {
        # State flags: 1 = Local, 2 = Registered, 4 = NoRebootRequired, 8 = NoErrors.
        # An instance that is only waiting on a restart still counts as installed; one whose setup failed does not.
        if (([uint32]$instance.state -band 11) -ne 11) {
            continue
        }

        [pscustomobject]@{
            DisplayName    = [string]$instance.displayName
            DisplayVersion = [string]$instance.catalog.productDisplayVersion
            Version        = ConvertTo-ParsedVersion -VersionText ([string]$instance.catalog.productDisplayVersion)
        }
    }

    return $installs | Sort-Object -Property Version -Descending | Select-Object -First 1
}

try {
    $minimumParsed = ConvertTo-ParsedVersion -VersionText $MinimumVersion

    if ($EnforceMinimumVersion -and ($MinimumVersion -and !$minimumParsed)) {
        exit 1
    }

    $app = Get-VisualStudioCommunityInstall
    if (!$app) {
        exit 1
    }

    if ($EnforceMinimumVersion) {
        if ($minimumParsed -and (!$app.Version -or $app.Version -lt $minimumParsed)) {
            exit 1
        }
    }

    Write-Output "Detected: $($app.DisplayName) [$($app.DisplayVersion)]"
    exit 0
}
catch {
    exit 1
}
