@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 is required. Install it, then run this launcher again.
    pause
    exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-WeeklyMaintenance.ps1" %*
set "maintenanceExit=%errorlevel%"
exit /b %maintenanceExit%
