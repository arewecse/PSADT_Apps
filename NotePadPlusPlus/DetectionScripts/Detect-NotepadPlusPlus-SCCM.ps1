param(
    [string]$MinimumVersion = '8.9.6.4',
    [bool]$EnforceMinimumVersion = $true
)

$ErrorActionPreference = 'Stop'

# SCCM (Configuration Manager) application detection clause:
#   STDOUT written -> detected (installed)
#   no STDOUT       -> not detected
# The exit code is ignored by SCCM, so this script always exits 0.

function Get-NotepadPlusPlusInstall {
    [CmdletBinding()]
    param()

    $uninstallRoot = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )

    foreach ($view in $views) {
        $baseKey = $null
        $rootKey = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $rootKey = $baseKey.OpenSubKey($uninstallRoot)
            if (!$rootKey) {
                continue
            }

            foreach ($subKeyName in $rootKey.GetSubKeyNames()) {
                $appKey = $null
                try {
                    $appKey = $rootKey.OpenSubKey($subKeyName)
                    if (!$appKey) {
                        continue
                    }

                    $displayName = [string]$appKey.GetValue('DisplayName', $null)
                    if ($displayName -like 'Notepad++*') {
                        return [pscustomobject]@{
                            DisplayName    = $displayName
                            DisplayVersion = [string]$appKey.GetValue('DisplayVersion', $null)
                        }
                    }
                }
                finally {
                    if ($appKey) {
                        $appKey.Dispose()
                    }
                }
            }
        }
        finally {
            if ($rootKey) {
                $rootKey.Dispose()
            }
            if ($baseKey) {
                $baseKey.Dispose()
            }
        }
    }

    return $null
}

try {
    $app = Get-NotepadPlusPlusInstall
    if (!$app) {
        exit 0
    }

    if (-not $EnforceMinimumVersion) {
        Write-Output "Detected: $($app.DisplayName)"
        exit 0
    }

    $reportedVersion = [string]$app.DisplayVersion
    $parsed = $null
    if ([string]::IsNullOrWhiteSpace($reportedVersion) -or ![version]::TryParse($reportedVersion, [ref]$parsed)) {
        exit 0
    }

    if ($parsed -ge [version]$MinimumVersion) {
        Write-Output "Detected: $($app.DisplayName) $reportedVersion"
    }

    exit 0
}
catch {
    exit 0
}
