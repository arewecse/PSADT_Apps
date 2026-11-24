<#
.SYNOPSIS
    Export TeamViewer Registry Configuration
.DESCRIPTION
    This script exports all TeamViewer registry settings from a configured machine
    so they can be applied to other deployments to prevent the company assignment dialog.
.NOTES
    Run this on a machine that has TeamViewer already configured and assigned to
    STRATUM Reservoir company.
#>

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "TeamViewer Registry Export Script" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$ExportPath = "$PSScriptRoot\TeamViewer_CompanySettings.reg"

Write-Host "Exporting TeamViewer registry settings..." -ForegroundColor Yellow

# Export both 64-bit and 32-bit registry paths
$registryPaths = @(
    "HKLM\SOFTWARE\TeamViewer",
    "HKLM\SOFTWARE\WOW6432Node\TeamViewer"
)

$success = $false

foreach ($path in $registryPaths) {
    Write-Host "Checking: $path" -ForegroundColor Gray
    $result = reg query $path 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Found! Exporting..." -ForegroundColor Green
        reg export $path $ExportPath /y | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Host "  Exported successfully!" -ForegroundColor Green
        }
        break
    }
}

if ($success) {
    Write-Host ""
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "Registry exported to: $ExportPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "File size: $((Get-Item $ExportPath).Length) bytes" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Copy this file to: PSADT_TeamViewer\SupportFiles\" -ForegroundColor White
    Write-Host "2. The deployment script will automatically use it" -ForegroundColor White
    Write-Host ""
    
    # Show a preview of the exported settings
    Write-Host "Preview of exported settings:" -ForegroundColor Yellow
    Write-Host "------------------------------" -ForegroundColor Gray
    Get-Content $ExportPath -Encoding Unicode | Select-Object -First 20
    Write-Host "... (truncated)" -ForegroundColor Gray
    Write-Host ""
}
else {
    Write-Host ""
    Write-Host "ERROR: TeamViewer registry not found!" -ForegroundColor Red
    Write-Host "Make sure TeamViewer is installed on this machine." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
