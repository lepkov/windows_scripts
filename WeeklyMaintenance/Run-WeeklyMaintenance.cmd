@echo off
setlocal
rem Store updates can terminate the Store-managed PowerShell host mid-run.
rem Prefer an existing non-Store runtime; the script rejects unsafe fallback hosts.
set "maintenancePwsh="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "maintenancePwsh=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined maintenancePwsh if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe" set "maintenancePwsh=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if not defined maintenancePwsh for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined maintenancePwsh set "maintenancePwsh=%%P"
if not defined maintenancePwsh (
    echo PowerShell 7 is required. Install it, then run this launcher again.
    pause
    exit /b 1
)
if /i "%~1"=="--runtime-path" (
    echo %maintenancePwsh%
    exit /b 0
)
"%maintenancePwsh%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-WeeklyMaintenance.ps1" %*
set "maintenanceExit=%errorlevel%"
exit /b %maintenanceExit%
