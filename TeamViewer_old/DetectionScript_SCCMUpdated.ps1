<#
.SYNOPSIS
    SCCM Detection Script for TeamViewer Host (64-bit ONLY on 64-bit OS)
.DESCRIPTION
    Detects if TeamViewer Host 64-bit is installed with the required version.
    Checks both file system AND registry for comprehensive detection.
    
    On 64-bit Windows: ONLY accepts 64-bit installation as valid.
    On 32-bit Windows: Will trigger uninstall/reinstall (always returns NOT DETECTED).
    
    Outputs "Detected" if the application is installed with the correct version.
    Outputs nothing if not detected or version is older.
.NOTES
    For use with SCCM/ConfigMgr application deployment.
    Detection Method: Script
#>

$ErrorActionPreference = 'SilentlyContinue'

# Required minimum version for detection
$RequiredVersion = [version]"15.73.5"

# Detection flag
$Detected = $false

try {
    # Determine OS architecture
    $Is64BitOS = [System.Environment]::Is64BitOperatingSystem
    
    if ($Is64BitOS) {
        # On 64-bit OS: ONLY accept 64-bit TeamViewer
        
        # First, check registry for ANY TeamViewer installation
        $RegistryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        $InstalledProducts = Get-ItemProperty $RegistryPaths -ErrorAction SilentlyContinue |
            Where-Object {$_.DisplayName -like "*TeamViewer*"}
        
        # Check if any 32-bit installation exists (in WOW6432Node or Program Files (x86))
        $Has32BitInstall = $false
        
        foreach ($Product in $InstalledProducts) {
            # Check install location
            if ($Product.InstallLocation -like "*Program Files (x86)*") {
                $Has32BitInstall = $true
                break
            }
            # Or check if uninstall path is in WOW6432Node registry
            if ($Product.PSPath -like "*WOW6432Node*") {
                $Has32BitInstall = $true
                break
            }
        }
        
        # If 32-bit installation found, force reinstall
        if ($Has32BitInstall) {
            $Detected = $false
        }
        else {
            # No 32-bit install, now check for compliant 64-bit installation
            $BasePath = "C:\Program Files\TeamViewer"
            $FullVersionExe = "$BasePath\TeamViewer.exe"
            $HostVersionExe = "$BasePath\TeamViewerHost.exe"
            
            # Check for TeamViewer.exe (full version)
            if (Test-Path -Path $FullVersionExe) {
                $FileInfo = Get-Item -Path $FullVersionExe -ErrorAction Stop
                $VersionString = $FileInfo.VersionInfo.ProductVersion
                
                if ($VersionString) {
                    if ($VersionString -match '^(\d+\.\d+\.\d+)') {
                        $ExeVersion = [version]$Matches[1]
                        
                        if ($ExeVersion -ge $RequiredVersion) {
                            $Detected = $true
                        }
                    }
                }
            }
            # Check for TeamViewerHost.exe if full version not found
            elseif (Test-Path -Path $HostVersionExe) {
                $FileInfo = Get-Item -Path $HostVersionExe -ErrorAction Stop
                $VersionString = $FileInfo.VersionInfo.ProductVersion
                
                if ($VersionString) {
                    if ($VersionString -match '^(\d+\.\d+\.\d+)') {
                        $ExeVersion = [version]$Matches[1]
                        
                        if ($ExeVersion -ge $RequiredVersion) {
                            $Detected = $true
                        }
                    }
                }
            }
            # If we found registry entry but no files, something is wrong - force reinstall
            elseif ($InstalledProducts) {
                $Detected = $false
            }
        }
    }
    else {
        # On 32-bit OS: Always return NOT DETECTED to force uninstall/reinstall
        $Detected = $false
    }
}
catch {
    # Silently handle any errors - treat as not detected
    $Detected = $false
}

# Return detection result for SCCM
if ($Detected) {
    Write-Output "Detected"
}

# Always exit 0 for SCCM detection scripts
exit 0