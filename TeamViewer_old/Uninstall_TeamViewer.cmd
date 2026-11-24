@echo off
cd /d "%~dp0"
SET "PowerShellPath=%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PowerShellPath%" SET "PowerShellPath=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

"%PowerShellPath%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-ServiceUI.ps1" -DeploymentType Uninstall
