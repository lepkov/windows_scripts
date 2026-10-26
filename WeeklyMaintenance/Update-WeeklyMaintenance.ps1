#requires -Version 7.0
<#
.SYNOPSIS
Weekly Windows maintenance script: updates Windows, Microsoft Store apps, Patch My PC apps, winget packages, and Driver Booster drivers.
.EXAMPLE
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1
pwsh -NoProfile -File .\Update-WeeklyMaintenance.ps1 -SkipDriverBooster -NoRebootPrompt
#>
[CmdletBinding()]
param(
    [switch]$SkipDriverBooster,
    [switch]$NoRebootPrompt,
    [switch]$StoreOnly,
    [string]$ExpectedUserSid
)

function New-StageResult {
    param([string]$Name, [string]$Status, [string]$Detail, [bool]$RebootRequired = $false)
    [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; RebootRequired = $RebootRequired }
}

function Get-WindowsUpdateDecision {
    param([Parameter(Mandatory)]$Candidate)
    $reason = ''
    if ($Candidate.IsBeta -or $Candidate.Title -match '(?i)\b(preview|insider|beta)\b|предварительн|инсайдер|бета') {
        $reason = 'Preview, beta or Insider release excluded'
    } elseif ($Candidate.CategoryIDs -contains '3689bdc8-b205-4af4-8d4a-a63924c5e9d5') {
        $reason = 'Feature upgrade requires separate review'
    } elseif ($Candidate.Title -match '(?i)firmware|прошивк|встроенн.{0,12}программ') {
        $reason = 'Firmware requires separate review'
    } elseif ($Candidate.CanRequestUserInput) {
        $reason = 'May require input during Windows installation'
    } elseif ($Candidate.BrowseOnly -and $Candidate.Type -ne 2 -and
        -not @($Candidate.CategoryIDs | Where-Object { $_ -in @(
            '0fa1201d-4330-4fa8-8ae9-b877473b6441', # Security updates
            'e6cf1350-c01b-414d-a61f-263d14d133b4', # Critical updates
            'e0789628-ce08-4437-be74-2495b842f43b'  # Definition updates
        ) }).Count) {
        $reason = 'Optional software: stable release not established; review KB manually'
    }
    [pscustomobject]@{ Install = ($reason -eq ''); Reason = $(if ($reason) { $reason } else { 'Eligible non-preview update' }) }
}

function Test-RestartAnswer {
    param([AllowEmptyString()][string]$Answer)
    $Answer.Trim() -ceq 'RESTART'
}

function Get-MaintenanceExitCode {
    param($Summary)
    if (-not $Summary) { return 0 } # Unelevated bootstrap handed off and exited.
    if (@($Summary.Stages | Where-Object Status -EQ 'Failed').Count) { return 1 }
    if (@($Summary.Stages | Where-Object Status -EQ 'NeedsAttention').Count) { return 2 }
    return 0
}

function Invoke-MaintenanceStages {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Actions,
        [switch]$NoRebootPrompt,
        [scriptblock]$PromptAction = { Read-Host 'All stages have ended. Type RESTART to reboot, or press Enter to keep working' },
        [scriptblock]$RestartAction = { Restart-Computer -Confirm:$false },
        [scriptblock]$OnCompleted = { param($Summary) }
    )
    $stages = [Collections.Generic.List[object]]::new()
    foreach ($name in $Actions.Keys) {
        Write-Host "`n--- $name ---" -ForegroundColor Cyan
        try {
            $results = @(& $Actions[$name])
            if (-not $results.Count) { throw 'Stage returned no result.' }
            foreach ($item in $results) {
                if (-not $item.PSObject.Properties['Status']) { throw 'Stage returned an invalid result.' }
                $stages.Add($item)
                Write-Host "$($item.Name): $($item.Status) -- $($item.Detail)"
            }
        } catch {
            $stages.Add((New-StageResult $name 'Failed' $_.Exception.Message))
            Write-Warning "$name failed: $($_.Exception.Message)"
        }
    }
    $summary = [pscustomobject]@{
        Mode           = 'Update'
        FinishedAt     = [DateTimeOffset]::Now.ToString('o')
        Stages         = $stages.ToArray()
        RebootRequired = [bool]@($stages | Where-Object RebootRequired).Count
    }
    & $OnCompleted $summary
    # This is the only path to a reboot: after every stage and final reporting.
    if (-not $NoRebootPrompt) {
        if (Test-RestartAnswer (& $PromptAction)) { & $RestartAction }
    }
    $summary
}

function Read-UpdaterProgress {
    param([IO.StreamReader]$Reader, [Collections.Generic.List[string]]$Lines)
    if (-not $Reader) { return }
    while ($null -ne ($line = $Reader.ReadLine())) {
        $Lines.Add($line)
        if ($line -match 'INFO|ERROR|WARN|Started installing|downloaded successfully|installer exit code') {
            Write-Host "[Patch My PC] $line"
        }
    }
}

function Invoke-NativeCapture {
    param([Parameter(Mandatory)][string]$Executable, [string[]]$Arguments = @(), [string]$LogTailPath)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $info.RedirectStandardInput = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $progressLines = [Collections.Generic.List[string]]::new()
    $logReader = $null
    try {
        if ($LogTailPath -and (Test-Path -LiteralPath $LogTailPath)) {
            $logStream = [IO.File]::Open($LogTailPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $null = $logStream.Seek(0, [IO.SeekOrigin]::End)
            $logReader = [IO.StreamReader]::new($logStream, [Text.Encoding]::UTF8, $true)
        }
        $null = $process.Start()
        # Never accept an install prompt accidentally.
        $process.StandardInput.WriteLine('n')
        $process.StandardInput.Close()
        $output = [Text.StringBuilder]::new()
        $readers = @($process.StandardOutput, $process.StandardError)
        $tasks = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
        $ended = @($false, $false)
        # Drain both streams concurrently and print progress into the visible console/transcript.
        while (-not ($ended[0] -and $ended[1])) {
            Read-UpdaterProgress -Reader $logReader -Lines $progressLines
            $received = $false
            for ($index = 0; $index -lt 2; $index++) {
                if (-not $ended[$index] -and $tasks[$index].IsCompleted) {
                    $line = $tasks[$index].GetAwaiter().GetResult()
                    if ($null -eq $line) {
                        $ended[$index] = $true
                    } else {
                        $null = $output.AppendLine($line)
                        Write-Host $line
                        $tasks[$index] = $readers[$index].ReadLineAsync()
                    }
                    $received = $true
                }
            }
            if (-not $received) { Start-Sleep -Milliseconds 100 }
        }
        $process.WaitForExit()
        Read-UpdaterProgress -Reader $logReader -Lines $progressLines
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output.ToString(); ProgressLines = $progressLines.ToArray() }
    } finally {
        if ($logReader) { $logReader.Dispose() }
        $process.Dispose()
    }
}

function Get-RebootState {
    $pending = $false
    try { $pending = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch { }
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path -LiteralPath $key) { $pending = $true }
    }
    $pending
}

function Find-DriverBooster {
    $root = Join-Path ${env:ProgramFiles(x86)} 'IObit\Driver Booster'
    if (Test-Path -LiteralPath $root) {
        Get-ChildItem -LiteralPath $root -Directory | Where-Object Name -Match '^\d+(\.\d+){1,3}$' |
            Sort-Object { [version]$_.Name } -Descending | ForEach-Object {
                $path = Join-Path $_.FullName 'DriverBooster.exe'
                if (Test-Path -LiteralPath $path) { $path }
            } | Select-Object -First 1
    }
}

function Invoke-DriverStage {
    param([switch]$Skip)
    if ($Skip) { return New-StageResult 'Driver Booster' 'Skipped' 'Skipped by command-line option' }
    $path = Find-DriverBooster
    if (-not $path) { throw 'Driver Booster executable not found.' }
    Write-Host 'In Driver Booster: leave automatic reboot/shutdown OFF, install the desired drivers,' -ForegroundColor Yellow
    Write-Host 'then EXIT Driver Booster completely (including its tray icon). The script continues when it exits.' -ForegroundColor Yellow
    $existing = @(Get-Process -Name DriverBooster -ErrorAction SilentlyContinue)
    if (-not $existing.Count) {
        $process = Start-Process -FilePath $path -PassThru
        $process.WaitForExit()
        $process.Dispose()
    }
    while (@(Get-Process -Name DriverBooster, DriverUpdate -ErrorAction SilentlyContinue).Count) {
        Start-Sleep -Seconds 3
    }
    New-StageResult 'Driver Booster' 'ManualStepEnded' 'Application exited; driver installation result is shown by Driver Booster' (Get-RebootState)
}

function Invoke-WindowsStage {
    param([Parameter(Mandatory)][string]$LogDirectory)
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'WeeklyMaintenance'
    # The wildcard includes optional installation deployment actions, not only automatic ones.
    $scan = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0 and DeploymentAction=*')
    if ([int]$scan.ResultCode -ne 2) { throw "Windows update scan was incomplete (result $($scan.ResultCode)); nothing installed." }
    $eligible = [Collections.Generic.List[object]]::new()
    $decisions = [Collections.Generic.List[object]]::new()
    foreach ($update in $scan.Updates) {
        $candidate = [pscustomobject]@{
            Title               = $update.Title
            IsBeta              = [bool]$update.IsBeta
            BrowseOnly          = [bool]$update.BrowseOnly
            Type                = [int]$update.Type
            CategoryIDs         = @($update.Categories | ForEach-Object CategoryID)
            CanRequestUserInput = [bool]$update.InstallationBehavior.CanRequestUserInput
            UpdateID            = $update.Identity.UpdateID
            KB                  = @($update.KBArticleIDs)
        }
        $decision = Get-WindowsUpdateDecision $candidate
        $decisions.Add([pscustomobject]@{ Candidate = $candidate; Install = $decision.Install; Reason = $decision.Reason })
        if ($decision.Install) { $eligible.Add($update) }
    }
    ConvertTo-Json -InputObject $decisions.ToArray() -Depth 7 | Set-Content -LiteralPath (Join-Path $LogDirectory 'windows-candidates.json') -Encoding utf8
    $excluded = $scan.Updates.Count - $eligible.Count
    $installed = 0
    $failed = 0
    $deferred = 0
    $reboot = Get-RebootState
    $installLog = [Collections.Generic.List[object]]::new()
    foreach ($update in $eligible) {
        $installer = $session.CreateUpdateInstaller()
        $installer.AllowSourcePrompts = $false
        $installer.ForceQuiet = $true
        if ($installer.RebootRequiredBeforeInstallation) {
            $deferred = $eligible.Count - $installed - $failed
            $reboot = $true
            break
        }
        try {
            if (-not $update.EulaAccepted) { $update.AcceptEula() }
            $collection = New-Object -ComObject Microsoft.Update.UpdateColl
            $null = $collection.Add($update)
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $collection
            $downloadResult = $downloader.Download()
            if (-not $update.IsDownloaded) { throw "Download incomplete (result $($downloadResult.ResultCode))" }
            $installer.Updates = $collection
            # WUA installation does not call Restart-Computer. Reboot is a returned requirement.
            $result = $installer.Install()
            $itemResult = $result.GetUpdateResult(0)
            $reboot = $reboot -or [bool]$result.RebootRequired
            $installLog.Add([pscustomobject]@{ Title = $update.Title; ResultCode = $itemResult.ResultCode; HResult = $itemResult.HResult; RebootRequired = $result.RebootRequired })
            if ([int]$itemResult.ResultCode -eq 2) { $installed++ } else { $failed++ }
        } catch {
            $failed++
            $installLog.Add([pscustomobject]@{ Title = $update.Title; Error = $_.Exception.Message })
        }
    }
    ConvertTo-Json -InputObject $installLog.ToArray() -Depth 5 | Set-Content -LiteralPath (Join-Path $LogDirectory 'windows-installation.json') -Encoding utf8
    $status = if ($failed -or $deferred -or $excluded) { 'NeedsAttention' } elseif ($installed) { 'Updated' } else { 'AlreadyCurrent' }
    New-StageResult 'Windows Update' $status "$installed installed, $failed failed, $deferred deferred until reboot, $excluded excluded/review; details in Windows JSON logs" $reboot
}

function Get-StorePendingCount {
    param([string]$Output)
    if ($Output -match '(?i)Updates available\s*\((\d+) found\)') { return [int]$Matches[1] }
    if ($Output -match '(?i)no (?:app )?updates (?:are )?(?:available|found)|all (?:your )?apps are up.to.date|нет доступных обновлений|обновления не найдены') { return 0 }
    return $null
}

function Invoke-StoreStage {
    param([Parameter(Mandatory)][string]$LogDirectory)
    $path = (Get-Command store.exe -CommandType Application -ErrorAction Stop).Source
    $arguments = @('updates', '--apply')
    $result = Invoke-NativeCapture $path $arguments
    $result.Output | Set-Content -LiteralPath (Join-Path $LogDirectory 'store-output.txt') -Encoding utf8
    if ($result.ExitCode -ne 0) { throw "Store returned $($result.ExitCode); see store-output.txt" }
    $waitSeconds = if ($result.Output -match 'Updates started|Started installation') { 60 } else { 0 }
    Wait-StoreCompletion -Executable $path -LogDirectory $LogDirectory -InitialDelaySeconds $waitSeconds
}

function Wait-StoreCompletion {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$LogDirectory,
        [ValidateRange(1, 180)][int]$VerificationAttempts = 15,
        [ValidateRange(0, 60)][int]$DelaySeconds = 30,
        [ValidateRange(0, 120)][int]$InitialDelaySeconds = 0
    )
    if ($InitialDelaySeconds) {
        Write-Host "Store queued its updates. Giving installations $InitialDelaySeconds seconds before verification."
        Start-Sleep -Seconds $InitialDelaySeconds
    }
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        $verify = Invoke-NativeCapture $Executable @('updates')
        $verify.Output | Set-Content -LiteralPath (Join-Path $LogDirectory 'store-verification.txt') -Encoding utf8
        $remaining = Get-StorePendingCount $verify.Output
        if ($verify.ExitCode -ne 0 -or $null -eq $remaining) { break }
        if ($remaining -eq 0) {
            return New-StageResult 'Microsoft Store' 'Verified' 'Follow-up Store scan reports no available updates'
        }
        Write-Host "$remaining Store update(s) still pending; waiting for queued installations ($attempt/$VerificationAttempts)."
        if ($attempt -lt $VerificationAttempts) { Start-Sleep -Seconds $DelaySeconds }
    }
    New-StageResult 'Microsoft Store' 'NeedsAttention' 'Store verification did not reach an empty queue; inspect store-output.txt and store-verification.txt'
}

function Invoke-PatchStage {
    param([Parameter(Mandatory)][string]$LogDirectory)
    $path = Join-Path $env:ProgramFiles 'Patch My PC\Patch My PC Home Updater\PatchMyPC-HomeUpdater.exe'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Patch My PC Home Updater executable not found.' }
    if (@(Get-Process -Name PatchMyPC-HomeUpdater -ErrorAction SilentlyContinue).Count) {
        return New-StageResult 'Patch My PC' 'NeedsAttention' 'Already running; close it before rerunning this script. A second instance could return before updates finish.'
    }
    $vendorLog = Join-Path $env:ProgramData 'PatchMyPC\PatchMyPCHomeUpdater.log'
    Write-Host 'Following the Patch My PC log: downloads, installation results and updated application names.'
    $result = Invoke-NativeCapture $path @('/s') -LogTailPath $vendorLog
    $result.Output | Set-Content -LiteralPath (Join-Path $LogDirectory 'patch-output.txt') -Encoding utf8
    # Wait for a replacement Home Updater instance after a self-update, without killing it.
    while (@(Get-Process -Name PatchMyPC-HomeUpdater -ErrorAction SilentlyContinue).Count) { Start-Sleep -Seconds 3 }
    if (Test-Path -LiteralPath $vendorLog) {
        Get-Content -LiteralPath $vendorLog -Tail 250 | Set-Content -LiteralPath (Join-Path $LogDirectory 'patch-vendor-log-tail.txt') -Encoding utf8
    }
    if ($result.ExitCode -notin @(0, 3010)) { throw "Patch My PC returned $($result.ExitCode); see patch logs" }
    $patchSummary = Get-PatchUpdateSummary $result.ProgressLines
    $patchSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $LogDirectory 'patch-results.json') -Encoding utf8
    $status = if ($patchSummary.HasErrors) { 'NeedsAttention' } elseif ($patchSummary.UpdatedApps.Count) { 'Updated' } else { 'CommandCompleted' }
    $detail = if ($patchSummary.UpdatedApps.Count) { 'Updated: ' + ($patchSummary.UpdatedApps -join ', ') } else { 'No successful application updates recorded in this run; see patch-results.json and vendor log' }
    New-StageResult 'Patch My PC' $status $detail (($result.ExitCode -eq 3010) -or (Get-RebootState))
}

function Get-PatchUpdateSummary {
    param([string[]]$Lines)
    $updated = [Collections.Generic.List[string]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -match 'Application (.+) has been successfully updated') {
            if (-not $updated.Contains($Matches[1])) { $updated.Add($Matches[1]) }
        }
        if ($line -match '\bERROR\b') { $errors.Add($line) }
    }
    [pscustomobject]@{ UpdatedApps = $updated.ToArray(); HasErrors = ($errors.Count -gt 0); Errors = $errors.ToArray() }
}

function Invoke-WingetStage {
    param([Parameter(Mandatory)][string]$LogDirectory)
    $path = (Get-Command winget.exe -CommandType Application -ErrorAction Stop).Source
    $arguments = @('upgrade', '--disable-interactivity', '--all', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    # Deliberately no --allow-reboot, --force, --include-pinned or hash bypass.
    $result = Invoke-NativeCapture $path $arguments
    $result.Output | Set-Content -LiteralPath (Join-Path $LogDirectory 'winget-output.txt') -Encoding utf8
    $hex = '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$result.ExitCode), 0)
    if ($hex -eq '0x8A15002B') { return New-StageResult winget 'AlreadyCurrent' 'No applicable package upgrades found' (Get-RebootState) }
    if ($result.ExitCode -notin @(0, 3010)) { throw "winget returned $hex; see winget-output.txt for per-package results" }
    New-StageResult winget 'CommandCompleted' 'See winget-output.txt for package results; pins and unknown-version defaults preserved' (($result.ExitCode -eq 3010) -or (Get-RebootState))
}

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-StorePowerShellHost {
    param([Parameter(Mandatory)][string]$RuntimeHome)
    $RuntimeHome -match '(?i)[\\/]WindowsApps[\\/]Microsoft\.PowerShell_'
}

function Get-MaintenanceStageOrder {
    param([switch]$StoreOnly)
    if ($StoreOnly) { return 'Microsoft Store' }
    @('Windows Update', 'Microsoft Store', 'Patch My PC', 'winget', 'Driver Booster')
}

function Request-MaintenanceElevation {
    param([string]$ScriptPath, [switch]$SkipDriverBooster, [switch]$NoRebootPrompt, [switch]$StoreOnly)
    $quotedPath = $ScriptPath.Replace("'", "''")
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $command = "& '$quotedPath' -ExpectedUserSid '$sid'"
    if ($SkipDriverBooster) { $command += ' -SkipDriverBooster' }
    if ($NoRebootPrompt) { $command += ' -NoRebootPrompt' }
    if ($StoreOnly) { $command += ' -StoreOnly' }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Write-Host 'Approve administrator access once. The complete routine will use one elevated terminal.'
    $null = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Verb RunAs -WindowStyle Normal -PassThru -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded)
}

function Start-Maintenance {
    if (-not $IsWindows) { throw 'This script requires Windows and PowerShell 7.' }
    $ErrorActionPreference = 'Stop'
    if (Test-StorePowerShellHost $PSHOME) {
        throw 'Microsoft Store can terminate its PowerShell host while updating it. Use Run-WeeklyMaintenance.cmd with a non-Store PowerShell 7 runtime (MSI or portable).'
    }
    if (-not (Test-IsAdministrator)) {
        Request-MaintenanceElevation -ScriptPath $PSCommandPath -SkipDriverBooster:$SkipDriverBooster -NoRebootPrompt:$NoRebootPrompt -StoreOnly:$StoreOnly
        return
    }
    if ($ExpectedUserSid -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedUserSid) {
        throw 'Approve elevation using the same Windows account.'
    }
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $mutex = [Threading.Mutex]::new($false, 'Local\WeeklyMaintenanceController')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Another maintenance controller is already running.' }
        $runPath = Join-Path $PSScriptRoot ('Logs\run-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Path $runPath -Force | Out-Null
        Start-Transcript -LiteralPath (Join-Path $runPath 'controller-transcript.txt') | Out-Null
        try {
            Write-Host "Mode: INSTALL UPDATES. Logs: $runPath"
            $actions = [ordered]@{}
            foreach ($stage in (Get-MaintenanceStageOrder -StoreOnly:$StoreOnly)) {
                $actions[$stage] = switch ($stage) {
                    'Windows Update' { { Invoke-WindowsStage -LogDirectory $runPath } }
                    'Microsoft Store' { { Invoke-StoreStage -LogDirectory $runPath } }
                    'Patch My PC' { { Invoke-PatchStage -LogDirectory $runPath } }
                    'winget' { { Invoke-WingetStage -LogDirectory $runPath } }
                    'Driver Booster' { { Invoke-DriverStage -Skip:$SkipDriverBooster } }
                }
            }
            $onCompleted = {
                param($Summary)
                $Summary.RebootRequired = $Summary.RebootRequired -or (Get-RebootState)
                $Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runPath 'summary.json') -Encoding utf8
                Write-Host "`nRoutine ended. Reboot requirement detected: $($Summary.RebootRequired)" -ForegroundColor Cyan
                $Summary.Stages | Format-Table Name, Status, Detail -Wrap | Out-Host
                Write-Host "Full results: $runPath"
            }
            $summary = Invoke-MaintenanceStages -Actions $actions -NoRebootPrompt:$NoRebootPrompt -OnCompleted $onCompleted
        } finally { Stop-Transcript | Out-Null }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
    $summary
}

if ($MyInvocation.InvocationName -ne '.') {
    $summary = Start-Maintenance
    exit (Get-MaintenanceExitCode $summary)
}
