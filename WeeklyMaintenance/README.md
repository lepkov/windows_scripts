# Weekly Maintenance

PowerShell 7 automation utility for performing weekly maintenance on Windows systems.

It orchestrates 5 sequential update stages:
1. **Windows Update** (via Windows Update Agent COM API, filtering out Previews, Betas, and Insiders)
2. **Microsoft Store** (via `store.exe updates --apply` for both the initial request and completion retries; no interactive bare `store updates` calls)
3. **Patch My PC Home Updater** (via `PatchMyPC-HomeUpdater.exe /s` with live progress tailing)
4. **winget** (via `winget upgrade --all --silent --accept-source-agreements --accept-package-agreements`)
5. **Driver Booster** (interactive manual stage, skipped if `-SkipDriverBooster` is specified)

---

## Quick Start

### Option 1: Batch Launcher
Double-click **`Run-WeeklyMaintenance.cmd`** or run it from any terminal. It validates PowerShell 7 availability and forwards any command-line arguments to the script.

The launcher prefers an existing non-Store PowerShell installation: the MSI installation under Program Files, then Codex's bundled portable runtime when present. This prevents a Store PowerShell update from closing the updater itself. Direct execution in Store-managed PowerShell is rejected before updates start. `Run-WeeklyMaintenance.cmd --runtime-path` prints the selected runtime without installing anything.

### Option 2: PowerShell Direct Execution
Run via a non-Store PowerShell 7 runtime (`pwsh`); use the batch launcher if your default `pwsh` comes from Microsoft Store:

```powershell
# Run full weekly maintenance
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1

# Run without Driver Booster interactive GUI
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1 -SkipDriverBooster

# Run unattended without asking for a reboot at the end
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1 -NoRebootPrompt

# Combined: skip Driver Booster and do not prompt for reboot
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1 -SkipDriverBooster -NoRebootPrompt

# Retry only Microsoft Store updates
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1 -StoreOnly -NoRebootPrompt
```

---

## Safety & Features

- **Direct Update**: Automatically executes updates without requiring an `-Apply` switch.
- **Mutex Protection**: Uses named mutex `Local\WeeklyMaintenanceController` to prevent concurrent executions.
- **Single UAC Elevation**: Automatically requests administrator rights via `RunAs` in a visible console if launched unelevated.
- **Safe Reboot Confirmation**: Even if updates indicate a reboot is pending, a reboot is only triggered if the user explicitly types **`RESTART`** (case-sensitive). Any other input or pressing Enter continues without rebooting.
- **Clean UTF-8 Output**: Explicit UTF-8 stream handling ensures clean output across localized Windows consoles.
- **Non-interactive Store retries**: Every Store request includes `--apply`. Queued installations are retried within the bounded wait; only an empty update queue is marked verified. CLI input/errors are never treated as success just because the exit code is zero.
- **Structured Logs**: Runtime logs and JSON summaries (`summary.json`, `windows-candidates.json`, `windows-installation.json`, `patch-results.json`) are stored in `Logs/run-<timestamp>-<id>/`.
- **Non-blocking vendor logs**: Patch My PC monitoring opens short read snapshots rather than holding its log open. If the updater writes exclusively, monitoring waits and catches up after the handle is released.
- **Patch My PC data workaround**: Before updating, clear only the Hidden attribute on its existing `local.dat`. Home Updater restores Hidden after writing, which otherwise makes its next overwrite fail with access denied. File data and permissions are preserved. Error summaries match ERROR severity, so temporary WARNING messages remain visible without being mislabeled as failed updates.

Close apps that use OBS Virtual Camera before updating OBS Studio. In a live run, Antigravity and Claude had its DLL loaded and blocked the installer; after exiting both apps, OBS updated successfully. The routine leaves app closure to the user.

---

## Testing

Run the offline unit test suite:

```powershell
pwsh -NoProfile -File .\Test-WeeklyMaintenance.ps1
```
