param(
    [string]$MinimumVersion = '15.83.7',
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

    # TeamViewer versions can carry a build/suffix (e.g. "15.83.7.0" or "15.83.7 HC").
    # Compare on Major.Minor.Build only so hotfix builds of the same release are treated as equal.
    if ($VersionText -match '^\s*(\d+)\.(\d+)\.(\d+)') {
        return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
    }

    return $null
}

function Get-TeamViewerInstall {
    [CmdletBinding()]
    param()

    # Compliant only when the 64-bit, EXE-based TeamViewer Host is installed. Any of the following is treated
    # as NOT detected so SCCM/Intune runs the package, which removes it and installs the current Host:
    #   - a 32-bit install (WOW6432Node / Program Files (x86))
    #   - an MSI-based install (WindowsInstaller = 1)
    #   - the TeamViewer full client instead of the Host module
    #   - a Host older than the minimum version
    $entries = @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.DisplayName -like 'TeamViewer*' })
    $x86Entries = @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.DisplayName -like 'TeamViewer*' })

    if ($x86Entries.Count -gt 0 -or ($entries | Where-Object { [string]$_.InstallLocation -like '*Program Files (x86)*' })) {
        return $null
    }

    $entry = $entries | Select-Object -First 1
    if (!$entry) {
        return $null
    }

    if ($entries | Where-Object { $_.WindowsInstaller -eq 1 }) {
        return $null
    }

    $isHost = [string]$entry.DisplayName -match 'Host'
    if (!$isHost) {
        $isHost = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\TeamViewer' -Name 'IsHostModule' -ErrorAction SilentlyContinue).IsHostModule -eq 1
    }
    if (!$isHost) {
        return $null
    }

    # Devices deployed with the old package carry an identity cloned from one PC (imported .reg file).
    # Treat them as NOT detected so the package resets the identity and re-assigns the device.
    $managementId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\TeamViewer\DeviceManagementV2' -Name 'ManagementId' -ErrorAction SilentlyContinue).ManagementId
    $intuneDeviceId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\TeamViewer' -Name 'IntuneDeviceId' -ErrorAction SilentlyContinue).IntuneDeviceId
    if ([string]$managementId -eq '{b7113481-c353-42ea-bd40-6856e85ef3f6}' -or [string]$intuneDeviceId -eq '{d4e066e4-52d7-49b6-935c-bc7b4c613548}') {
        return $null
    }

    $version = ConvertTo-ParsedVersion -VersionText ([string]$entry.DisplayVersion)

    # Fall back to the TeamViewer.exe file version if the registry version cannot be parsed.
    if (!$version) {
        $teamViewerExe = Join-Path -Path $env:ProgramFiles -ChildPath 'TeamViewer\TeamViewer.exe'
        if (Test-Path -LiteralPath $teamViewerExe -PathType Leaf) {
            $version = ConvertTo-ParsedVersion -VersionText ((Get-Item -LiteralPath $teamViewerExe).VersionInfo.ProductVersion)
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

    $app = Get-TeamViewerInstall
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
