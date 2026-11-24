<#
.SYNOPSIS
    SCCM Detection Script for TeamViewer Host (64-bit ONLY on 64-bit OS)
.DESCRIPTION
    Detects if TeamViewer Host 64-bit is installed with the required version.
    On 64-bit Windows: ONLY accepts 64-bit installation as valid.
    On 32-bit Windows: Accepts 32-bit installation.
    
    This ensures that 32-bit TeamViewer on 64-bit OS will be replaced with 64-bit version.
    
    Outputs "Detected" if the application is installed with the correct version.
    Outputs nothing if not detected or version is older.
.NOTES
    For use with SCCM/ConfigMgr application deployment.
    Detection Method: Script
    
    USE THIS VERSION IF: You want to enforce 64-bit TeamViewer on all 64-bit Windows systems
    (will trigger upgrade from 32-bit to 64-bit).
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
        $ExePath = "C:\Program Files\TeamViewer\TeamViewer.exe"
        
        if (Test-Path -Path $ExePath) {
            # Get the file version
            $FileInfo = Get-Item -Path $ExePath -ErrorAction Stop
            $VersionString = $FileInfo.VersionInfo.ProductVersion
            
            if ($VersionString) {
                # Extract version numbers (handle formats like "15.73.5.0" or "15.73.5")
                if ($VersionString -match '^(\d+\.\d+\.\d+)') {
                    $ExeVersion = [version]$Matches[1]
                    
                    # Check if version meets requirements
                    if ($ExeVersion -ge $RequiredVersion) {
                        $Detected = $true
                    }
                }
            }
        }
        
        # Note: 32-bit installation on 64-bit OS will naturally result in $Detected = $false
        # No need for explicit check - absence of 64-bit installation means not detected
    }
    else {
        # On 32-bit OS: Accept 32-bit TeamViewer
        $ExePath = "C:\Program Files\TeamViewer\TeamViewer.exe"
        
        if (Test-Path -Path $ExePath) {
            # Get the file version
            $FileInfo = Get-Item -Path $ExePath -ErrorAction Stop
            $VersionString = $FileInfo.VersionInfo.ProductVersion
            
            if ($VersionString) {
                # Extract version numbers
                if ($VersionString -match '^(\d+\.\d+\.\d+)') {
                    $ExeVersion = [version]$Matches[1]
                    
                    # Check if version meets requirements
                    if ($ExeVersion -ge $RequiredVersion) {
                        $Detected = $true
                    }
                }
            }
        }
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