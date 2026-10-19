# windows-scripts

**WeeklyMaintenance**

Comprehensive weekly Windows maintenance and update automation suite located in `WeeklyMaintenance/`.
- Orchestrates sequential updates across Windows Update (WUA API), Microsoft Store (`store.exe`), Patch My PC Home Updater, winget, and Driver Booster.
- Direct update execution via `Run-WeeklyMaintenance.cmd` or PowerShell 7 (`Update-WeeklyMaintenance.ps1`).
- Includes safety mechanisms: named mutex (`Local\WeeklyMaintenanceController`) against concurrent runs, safe reboot prompt (requires exact `RESTART` confirmation), optional Driver Booster skip (`-SkipDriverBooster`), and structured logging in `Logs/`.
- Offline test suite in `WeeklyMaintenance/Test-WeeklyMaintenance.ps1`.

**add_PC_to_domain.ps1**

Adds PC to specified domain with specified credentials.

**Clean_old_1C_backups.bat**

Script cleans files older than 30 days from D:\data\backup1C with .7z extension EXCEPT for files with mask name: 01.*.*.7z, 07.*.*.7z, 14.*.*.7z, 21.*.*.7z, 28.*.*.7z.

**Reopen_application_with_timeout.bat**

Script closes app and starts new with 2 seconds timeout.

**Windows_7_DisableAero.bat**

Script configs windows for more perfomance. Works for Windows 7.

**Windows_7_ApplyTheme.vbs**

Script works for Windows 7, checks for Current theme in registry and if it's not basic.theme, applies it and closes Personalisation window.
