param(
    [string]$DisplayNamePattern = 'Adobe Acrobat',  # Unified installer registers as 'Adobe Acrobat (64-bit)' regardless of Reader or Pro mode
    [string]$MinimumVersion = '26.001.21662'
)

$ErrorActionPreference = 'Stop'

function Get-InstalledAppVersion {
    param([string]$NamePattern)

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $foundVersions = @()
    foreach ($root in $roots) {
        if (!(Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (!$item -or [string]::IsNullOrWhiteSpace($item.DisplayName) -or [string]::IsNullOrWhiteSpace($item.DisplayVersion)) {
                continue
            }

            if ($item.DisplayName -match $NamePattern) {
                $parsed = $null
                if ([version]::TryParse([string]$item.DisplayVersion, [ref]$parsed)) {
                    $foundVersions += [pscustomobject]@{
                        DisplayName = [string]$item.DisplayName
                        DisplayVersion = [string]$item.DisplayVersion
                        ParsedVersion = $parsed
                    }
                }
            }
        }
    }

    if (!$foundVersions) {
        return $null
    }

    return ($foundVersions | Sort-Object -Property ParsedVersion -Descending | Select-Object -First 1)
}

try {
    $detected = Get-InstalledAppVersion -NamePattern $DisplayNamePattern
    if (!$detected) {
        Write-Host "Not detected: no installed app matched pattern [$DisplayNamePattern]."
        exit 1
    }

    $requiredVersion = [version]$MinimumVersion
    if ($detected.ParsedVersion -ge $requiredVersion) {
        Write-Host "Detected: $($detected.DisplayName) $($detected.DisplayVersion)"
        exit 0
    }

    Write-Host "Not detected: installed version $($detected.DisplayVersion) is below required $MinimumVersion."
    exit 1
}
catch {
    Write-Host "Detection failed: $($_.Exception.Message)"
    exit 1
}
