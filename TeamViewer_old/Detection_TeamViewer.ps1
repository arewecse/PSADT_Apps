<#
.SYNOPSIS
    Intune Detection Script for TeamViewer Host (64-bit)
.DESCRIPTION
    Detects if TeamViewer Host 64-bit is installed with the required version.
    This script checks both registry and actual executable version to ensure
    a proper installation.
    
    Returns exit code 0 if detected (installed), exit code 1 if not detected.
.NOTES
    For use with Intune Win32 app deployment.
    Detection Method: Custom Script
#>

# Required minimum version for detection (update this to match your deployed version)
$RequiredVersion = [version]"15.73.5"

$Detected = $false
$RegistryVersion = $null
$ExeVersion = $null
$Found64Bit = $false

# ============================================
# Check for TeamViewer 64-bit installation
# ============================================
try {
    # Check in Add/Remove Programs (both 32-bit and 64-bit registry)
    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Get all TeamViewer installations
    $TeamViewerApps = Get-ItemProperty -Path $UninstallPaths -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -like "*TeamViewer*" }
    
    if ($TeamViewerApps) {
        foreach ($TeamViewerApp in $TeamViewerApps) {
            # Check if this is the 64-bit version
            # Method 1: Check DisplayName for 64-bit indicators
            $NameIndicates64Bit = $TeamViewerApp.DisplayName -match '64-bit' -or 
            $TeamViewerApp.DisplayName -match 'x64' -or
            $TeamViewerApp.DisplayName -match 'Host'
            
            # Method 2: Check InstallLocation/UninstallString paths
            $PathIndicates64Bit = ($TeamViewerApp.InstallLocation -like '*Program Files\*' -and 
                $TeamViewerApp.InstallLocation -notlike '*Program Files (x86)*') -or
            ($TeamViewerApp.UninstallString -like '*Program Files\*' -and 
            $TeamViewerApp.UninstallString -notlike '*Program Files (x86)*')
            
            # Method 3: Check registry path - if it's NOT in WOW6432Node, it's likely 64-bit
            $RegPathIndicates64Bit = $TeamViewerApp.PSPath -notlike '*WOW6432Node*'
            
            # Method 4: Check if 64-bit executable exists (most reliable)
            $ExeIndicates64Bit = Test-Path -Path "C:\Program Files\TeamViewer\TeamViewer.exe"
            
            $Is64BitApp = $NameIndicates64Bit -or $PathIndicates64Bit -or $RegPathIndicates64Bit -or $ExeIndicates64Bit
            
            Write-Output "Detection check - Name: $NameIndicates64Bit, Path: $PathIndicates64Bit, RegPath: $RegPathIndicates64Bit, Exe: $ExeIndicates64Bit"
            
            if ($Is64BitApp) {
                $Found64Bit = $true
                try {
                    $RegistryVersion = [version]$TeamViewerApp.DisplayVersion
                    Write-Output "Registry shows 64-bit: $($TeamViewerApp.DisplayName) v$RegistryVersion"
                }
                catch {
                    Write-Output "Could not parse registry version: $($TeamViewerApp.DisplayVersion)"
                }
                break  # Found 64-bit, stop looking
            }
            else {
                Write-Output "Found 32-bit TeamViewer: $($TeamViewerApp.DisplayName) - Will be replaced with 64-bit"
            }
        }
    }
    
    # Check for 64-bit executable specifically
    $TeamViewerExePath64 = "C:\Program Files\TeamViewer\TeamViewer.exe"
    $TeamViewerExePath32 = "C:\Program Files (x86)\TeamViewer\TeamViewer.exe"
    
    if (Test-Path -Path $TeamViewerExePath64) {
        $Found64Bit = $true
        try {
            $ExeVersionString = (Get-Item -Path $TeamViewerExePath64).VersionInfo.ProductVersion
            # TeamViewer version string might have extra parts, take only Major.Minor.Build
            if ($ExeVersionString -match '(\d+\.\d+(?:\.\d+)?)') {
                $ExeVersion = [version]$Matches[1]
                Write-Output "64-bit executable version: $ExeVersion"
            }
        }
        catch {
            Write-Output "Could not parse 64-bit executable version"
        }
    }
    elseif (Test-Path -Path $TeamViewerExePath32) {
        Write-Output "Only 32-bit executable found at: $TeamViewerExePath32"
        Write-Output "32-bit version will be replaced with 64-bit"
        # Don't set Found64Bit = true, so detection fails and 64-bit gets installed
    }
    
    # Only consider detection successful if we found the 64-bit version
    if ($Found64Bit) {
        # Determine effective version
        if ($RegistryVersion -and $ExeVersion) {
            # Both registry and exe exist - use exe version as source of truth
            $EffectiveVersion = $ExeVersion
            if ($EffectiveVersion -ge $RequiredVersion) {
                $Detected = $true
            }
        }
        elseif ($ExeVersion) {
            # No registry but exe exists - still consider it installed if version matches
            $EffectiveVersion = $ExeVersion
            if ($EffectiveVersion -ge $RequiredVersion) {
                $Detected = $true
            }
        }
        elseif ($RegistryVersion) {
            # Registry exists but no exe = broken install
            Write-Output "WARNING: Registry entry found but no executable - broken installation"
            $EffectiveVersion = $RegistryVersion
            $Detected = $false
        }
    }
}
catch {
    Write-Output "Error checking TeamViewer installation: $($_.Exception.Message)"
}

# ============================================
# Return detection result
# ============================================
if ($Detected) {
    Write-Output "TeamViewer Host 64-bit Installed - Version: $EffectiveVersion (Required: $RequiredVersion)"
    Write-Output "Installation is valid."
    exit 0
}
elseif ($Found64Bit -and $EffectiveVersion) {
    Write-Output "TeamViewer Host 64-bit Installed but outdated - Version: $EffectiveVersion < Required: $RequiredVersion"
    exit 1
}
elseif (-not $Found64Bit -and (Test-Path "C:\Program Files (x86)\TeamViewer\TeamViewer.exe")) {
    Write-Output "Only 32-bit TeamViewer installed - 64-bit version required"
    exit 1
}
else {
    Write-Output "TeamViewer Host 64-bit Not Installed"
    exit 1
}
