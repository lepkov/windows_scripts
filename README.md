# Windows Scripts Collection

A collection of PowerShell, Batch, and VBScript automation scripts for Windows administration, maintenance, Active Directory management, and environment configuration.

## Overview

| Script / Directory | Type | Description |
| --- | --- | --- |
| [`WeeklyMaintenance/`](#weeklymaintenance) | Suite | Comprehensive weekly update automation suite for Windows, Store, winget, Patch My PC, and Driver Booster. |
| [`AOVPN/`](#aovpn) | Suite | Always On VPN client configuration scripts, XML profile templates, and deployment instructions. |
| [`add_PC_to_domain.ps1`](#add_pc_to_domainps1) | PowerShell | Joins a local Windows machine to an Active Directory domain with specified credentials. |
| [`AWS_EC2_Get_Public_IPv4.ps1`](#aws_ec2_get_public_ipv4ps1) | PowerShell | Queries AWS EC2 Instance Metadata Service (IMDS) to retrieve the public IPv4 address. |
| [`Clean_old_1C_backups.bat`](#clean_old_1c_backupsbat) | Batch | Purges 1C backup archives (`.7z`) older than 30 days while preserving milestone weekly and monthly backups. |
| [`Clean_old_1C_backups.ps1`](#clean_old_1c_backupsps1) | PowerShell | Multi-tier backup retention cleanup removing odd-day backups after 30 days and non-weekly backups after 90 days. |
| [`Debloat_Windows10.ps1`](#debloat_windows10ps1) | PowerShell | Removes pre-installed Windows 10 UWP bloatware packages for all users and logs status to a network share. |
| [`deleteFoldersByMask.ps1`](#deletefoldersbymaskps1) | PowerShell | Recursively cleans temporary cache directories (`Temp`, `History`, `Thumbnails`) with `-WhatIf` safety support. |
| [`installLatestChrome32bit.ps1`](#installlatestchrome32bitps1) | PowerShell | Downloads and silently installs Google Chrome Enterprise 32-bit standalone MSI installer. |
| [`LogonSchedulerTask.ps1`](#logonschedulertaskps1) | PowerShell | Creates an elevated Windows scheduled task triggered automatically at user logon. |
| [`psexecNotepad.ps1`](#psexecnotepadps1) | PowerShell | Utility demonstrating remote process execution under administrative credentials via Sysinternals PsExec. |
| [`RDPConnectAndCertWarningOff.ps1`](#rdpconnectandcertwarningoffps1) | PowerShell | Suppresses RDP certificate mismatch warnings via registry tweaks, registers credentials, and launches mstsc. |
| [`Reopen_application_with_timeout.bat`](#reopen_application_with_timeoutbat) | Batch | Terminates a running application and relaunches it after a 2-second timeout delay. |
| [`searchInactivePCinAD.ps1`](#searchinactivepcinadps1) | PowerShell | Queries Active Directory for stale computer accounts inactive for more than 365 days. |
| [`setThemeCloseWindow.vbs`](#setthemeclosewindowvbs) | VBScript | Applies the Windows basic theme via `desk.cpl` and automatically closes the Personalization settings window. |
| [`Telegram_Notification.ps1`](#telegram_notificationps1) | PowerShell | Sends automated alert messages to a Telegram chat via the Telegram Bot API over TLS 1.2. |
| [`TurnOffLegalNoticeAndAutologin.ps1`](#turnofflegalnoticeandautologinps1) | PowerShell | Disables Windows legal notice logon prompts and configures registry keys for automatic logon. |
| [`Windows_7_ApplyTheme.vbs`](#windows_7_applythemevbs) | VBScript | Checks the active theme in the registry and applies the classic basic theme on Windows 7. |
| [`Windows_7_DisableAero.bat`](#windows_7_disableaerobat) | Batch | Tweaks Windows 7 visual effects registry settings to disable Aero glass and optimize GUI speed. |

---

## Detailed Descriptions

### WeeklyMaintenance/
Comprehensive weekly Windows maintenance and update automation suite located in `WeeklyMaintenance/`.
- Orchestrates sequential updates across Windows Update (WUA API), Microsoft Store (`store.exe`), Patch My PC Home Updater, winget, and Driver Booster.
- Direct update execution via `Run-WeeklyMaintenance.cmd` or PowerShell 7 (`Update-WeeklyMaintenance.ps1`).
- Includes safety mechanisms: named mutex (`Local\WeeklyMaintenanceController`) against concurrent runs, safe reboot prompt (requires exact `RESTART` confirmation), optional Driver Booster skip (`-SkipDriverBooster`), and structured logging in `Logs/`.
- Offline test suite in `WeeklyMaintenance/Test-WeeklyMaintenance.ps1`.

### AOVPN/
Always On VPN (AOVPN) automated client configuration suite.
- Contains client deployment scripts (`aovpn.lepkov.ru.ps1`) and XML profile configuration templates (`aovpn.lepkov.ru.xml`) for establishing Windows Always On VPN device tunnels.
- Includes setup prerequisites and step-by-step instructions in `AOVPN/README.md`.

### add_PC_to_domain.ps1
Joins a Windows workstation to a specified Active Directory domain using provided administrative credentials.
- Invokes `Add-Computer` with `-DomainName`, `-Credential`, and `-Restart` parameters to finalize domain membership.

### AWS_EC2_Get_Public_IPv4.ps1
Queries the AWS EC2 Instance Metadata Service (IMDS) at `http://169.254.169.254/latest/meta-data/public-ipv4` to retrieve and display the instance's public IPv4 address.

### Clean_old_1C_backups.bat
Automates cleanup of 1C backup archives (`.7z`) in `D:\data\backup1C` older than 30 days.
- Retains weekly and monthly milestone backups matching specific day masks (`01.*`, `07.*`, `14.*`, `21.*`, `28.*`).

### Clean_old_1C_backups.ps1
PowerShell implementation of a multi-stage backup retention policy.
- First iteration purges odd-day backup archives older than 30 days; second iteration purges all backups older than 90 days except weekly milestones (`01`, `08`, `15`, `22`, `28`).

### Debloat_Windows10.ps1
Removes pre-installed Windows 10 UWP bloatware and telemetry packages for current and all future users.
- Executes `Remove-AppxPackage` and `Remove-AppxProvisionedPackage` across all packages and outputs completion status to a network share.

### deleteFoldersByMask.ps1
Recursively searches a specified directory path to delete subfolders matching target names (`Temp`, `History`, `Thumbnails`).
- Includes `-WhatIf` switch by default for dry-run verification before actual deletion.

### installLatestChrome32bit.ps1
Downloads the latest Google Chrome Enterprise 32-bit standalone MSI installer directly from Google servers.
- Executes silent installation via `msiexec.exe /i ... /qn /norestart` and cleans up the temporary installer file.

### LogonSchedulerTask.ps1
Registers a Windows scheduled task configured to execute an administrative application with highest privileges at user logon.
- Uses `New-ScheduledTaskTrigger -AtLogon` and `New-ScheduledTaskPrincipal -RunLevel Highest` to bypass UAC prompts at login.

### psexecNotepad.ps1
Utility script demonstrating remote process execution via Sysinternals PsExec (`PsExec64.exe`).
- Executes a target executable in session 1 on a remote host using explicit administrative credentials.

### RDPConnectAndCertWarningOff.ps1
Automates Remote Desktop connections while suppressing TLS/certificate mismatch warning dialogs.
- Ensures `HKCU:\Software\Microsoft\Terminal Server Client\AuthenticationLevelOverride` is set to `0`, registers credentials with `cmdkey`, and launches `mstsc`.

### Reopen_application_with_timeout.bat
Closes a running application process and restarts it after a 2-second timeout delay.
- Uses `taskkill /f /im` followed by `timeout /t 2 /nobreak` and restarts the executable.

### searchInactivePCinAD.ps1
Queries Active Directory for stale computer accounts that have not logged in within the past 365 days.
- Utilizes `Get-ADComputer` filtered by `LastLogonDate` to assist in Active Directory cleanup.

### setThemeCloseWindow.vbs
VBScript helper that activates the Windows basic theme via `desk.cpl` and monitors the GUI to automatically close the Personalization window once applied.

### Telegram_Notification.ps1
Sends notification messages to a designated Telegram chat using the Telegram Bot API over TLS 1.2 via `Invoke-RestMethod`.

### TurnOffLegalNoticeAndAutologin.ps1
Disables the Windows interactive logon legal notice caption and text, and configures the registry (`Winlogon`) for automatic administrative logon.

### Windows_7_ApplyTheme.vbs
Checks the current Windows theme registry key and applies the Windows 7 Classic basic theme (`basic.theme`) to optimize interface performance.

### Windows_7_DisableAero.bat
Optimizes Windows 7 GUI performance by configuring visual effect registry parameters to disable Aero glass, animations, and shadows.

