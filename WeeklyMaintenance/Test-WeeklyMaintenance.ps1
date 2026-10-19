#requires -Version 7.0
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Update-WeeklyMaintenance.ps1"
$script:Checks = 0
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "$Message -- expected '$Expected', got '$Actual'" }
    $script:Checks++
}
function New-Candidate([string]$Title = 'Security Update KB123', [bool]$Optional = $false, [int]$Type = 1, [string[]]$Categories = @()) {
    [pscustomobject]@{ Title=$Title; IsBeta=$false; BrowseOnly=$Optional; Type=$Type; CategoryIDs=$Categories; CanRequestUserInput=$false }
}

# 1. Update filter decisions
foreach ($title in @('2026-10 Cumulative Update Preview (KB123)', 'Предварительный просмотр накопительного обновления', 'Windows Insider Preview', '.NET Preview Update', 'Бета-версия Windows')) {
    Assert-Equal (Get-WindowsUpdateDecision (New-Candidate $title)).Install $false "Exclude preview: $title"
}
$candidate = New-Candidate; $candidate.IsBeta=$true
Assert-Equal (Get-WindowsUpdateDecision $candidate).Install $false 'Exclude beta metadata'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Stable required update')).Install $true 'Include required stable update'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Intel driver' $true 2)).Install $true 'Include optional driver'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Optional cumulative update' $true)).Install $false 'Defer ambiguous optional software'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Security Update' $true 1 @('0fa1201d-4330-4fa8-8ae9-b877473b6441'))).Install $true 'Include optional classified security update'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Windows version upgrade' $false 1 @('3689bdc8-b205-4af4-8d4a-a63924c5e9d5'))).Install $false 'Defer feature upgrade'
Assert-Equal (Get-WindowsUpdateDecision (New-Candidate 'Contoso - Firmware - 1.2' $true 2)).Install $false 'Defer firmware'
$candidate = New-Candidate; $candidate.CanRequestUserInput = $true
Assert-Equal (Get-WindowsUpdateDecision $candidate).Install $false 'Defer interactive update'

# 2. Restart answer validation
Assert-Equal (Test-RestartAnswer 'RESTART') $true 'Accept exact uppercase RESTART'
Assert-Equal (Test-RestartAnswer "  RESTART `r`n") $true 'Accept padded RESTART'
Assert-Equal (Test-RestartAnswer 'restart') $false 'Reject lowercase restart'
Assert-Equal (Test-RestartAnswer 'y') $false 'Reject y'
Assert-Equal (Test-RestartAnswer 'yes') $false 'Reject yes'
Assert-Equal (Test-RestartAnswer 'да') $false 'Reject russian yes'
Assert-Equal (Test-RestartAnswer '') $false 'Reject empty answer'
Assert-Equal (Test-RestartAnswer $null) $false 'Reject null answer'

# 3. Store pending count parsing
Assert-Equal (Get-StorePendingCount "Updates available (3 found)`n1. App A`n2. App B`n3. App C") 3 'Parse store update count'
Assert-Equal (Get-StorePendingCount 'All your apps are up to date.') 0 'Parse store up to date english'
Assert-Equal (Get-StorePendingCount 'No app updates available.') 0 'Parse store no updates'
Assert-Equal (Get-StorePendingCount 'Нет доступных обновлений.') 0 'Parse store up to date russian'
Assert-Equal (Get-StorePendingCount 'Random output') $null 'Return null on unrecognized store output'

# 4. Patch My PC summary parsing
$patchLog = @(
    '2026-10-19 12:00:00 [INFO] Started installing Foo',
    '2026-10-19 12:01:00 [INFO] Application Foo has been successfully updated',
    '2026-10-19 12:02:00 [INFO] Application Bar has been successfully updated',
    '2026-10-19 12:02:30 [INFO] Application Foo has been successfully updated',
    '2026-10-19 12:03:00 [ERROR] Baz update failed'
)
$parsed = Get-PatchUpdateSummary $patchLog
Assert-Equal ($parsed.UpdatedApps -join ',') 'Foo,Bar' 'Deduplicate updated apps'
Assert-Equal $parsed.HasErrors $true 'Detect errors in Patch My PC log'
Assert-Equal $parsed.Errors.Count 1 'Capture error lines'

# 5. Maintenance stage ordering
$defaultOrder = Get-MaintenanceStageOrder
Assert-Equal ($defaultOrder -join ';') 'Windows Update;Microsoft Store;Patch My PC;winget;Driver Booster' 'Standard stage ordering'
$storeOnlyOrder = Get-MaintenanceStageOrder -StoreOnly
Assert-Equal $storeOnlyOrder 'Microsoft Store' 'Store only stage ordering'

# 6. Exit code mapping
$cleanSummary = [pscustomobject]@{ Stages = @((New-StageResult 'A' 'Updated' 'ok'), (New-StageResult 'B' 'AlreadyCurrent' 'ok')) }
Assert-Equal (Get-MaintenanceExitCode $cleanSummary) 0 'Exit code 0 on clean run'
$failedSummary = [pscustomobject]@{ Stages = @((New-StageResult 'A' 'Failed' 'boom'), (New-StageResult 'B' 'Updated' 'ok')) }
Assert-Equal (Get-MaintenanceExitCode $failedSummary) 1 'Exit code 1 on failed stage'
$attnSummary = [pscustomobject]@{ Stages = @((New-StageResult 'A' 'NeedsAttention' 'check'), (New-StageResult 'B' 'Updated' 'ok')) }
Assert-Equal (Get-MaintenanceExitCode $attnSummary) 2 'Exit code 2 on needs attention'
Assert-Equal (Get-MaintenanceExitCode $null) 0 'Exit code 0 when handed off'

# 7. Pipeline execution
$orderLog = [Collections.Generic.List[string]]::new()
$actions = [ordered]@{
    First = { $orderLog.Add('First'); New-StageResult 'First' 'Updated' 'ok' }
    Broken = { $orderLog.Add('Broken'); throw 'simulated failure' }
    Last = { $orderLog.Add('Last'); New-StageResult 'Last' 'Updated' 'ok' }
}
$script:promptCalled = $false
$script:restartCalled = $false
$summary = Invoke-MaintenanceStages -Actions $actions `
    -PromptAction { $script:promptCalled = $true; 'RESTART' } `
    -RestartAction { $script:restartCalled = $true } `
    -OnCompleted { param($s) Assert-Equal $s.Stages.Count 3 'OnCompleted sees all stages' }
Assert-Equal ($orderLog -join ';') 'First;Broken;Last' 'Pipeline continues after a stage exception'
Assert-Equal $script:promptCalled $true 'Prompt invoked when NoRebootPrompt is omitted'
Assert-Equal $script:restartCalled $true 'Restart action executed when RESTART confirmed'
Assert-Equal $summary.Stages[1].Status 'Failed' 'Pipeline records failed stage'

# Verify NoRebootPrompt suppresses prompt
$script:promptCalled2 = $false
$summary2 = Invoke-MaintenanceStages -Actions $actions -NoRebootPrompt `
    -PromptAction { $script:promptCalled2 = $true; 'RESTART' } `
    -RestartAction { } `
    -OnCompleted { param($s) }
Assert-Equal $script:promptCalled2 $false 'NoRebootPrompt suppresses prompt'

# 8. Native capture and UTF-8 handling
$capture = Invoke-NativeCapture -Executable (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-Command','[Console]::Out.WriteLine("fixture output"); [Console]::Error.WriteLine("fixture error"); exit 7')
Assert-Equal $capture.ExitCode 7 'Preserve native exit code'
Assert-Equal ($capture.Output -match 'fixture output') $true 'Capture stdout'
Assert-Equal ($capture.Output -match 'fixture error') $true 'Capture stderr'
$savedEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(866)
    $unicodeCapture = Invoke-NativeCapture -Executable (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-Command','[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::WriteLine("Обновление ✓")')
    Assert-Equal ($unicodeCapture.Output.Trim()) 'Обновление ✓' 'Decode native UTF-8 independently of terminal code page'
} finally { [Console]::OutputEncoding = $savedEncoding }

# 9. Store stage & completion waiting
$testOutput = Join-Path $PSScriptRoot 'TestOutput'
$null = New-Item -ItemType Directory -Path $testOutput -Force
$progressLog = Join-Path $testOutput 'fixture-updater.log'
'old record: ignore this' | Set-Content -LiteralPath $progressLog
$escapedLog = $progressLog.Replace("'","''")
$appendCommand = "[IO.File]::AppendAllText('$escapedLog', '[INFO] Application Fixture App has been successfully updated' + [Environment]::NewLine)"
$progressCapture = Invoke-NativeCapture -Executable (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-Command',$appendCommand) -LogTailPath $progressLog
Assert-Equal $progressCapture.ProgressLines.Count 1 'Capture only newly appended updater log records'
Assert-Equal (Get-PatchUpdateSummary $progressCapture.ProgressLines).UpdatedApps[0] 'Fixture App' 'Collect per-application success while native updater runs'

$nativeImplementation = ${function:Invoke-NativeCapture}
try {
    $script:CapturedArgs = [Collections.Generic.List[string]]::new()
    function Invoke-NativeCapture($Executable, $Arguments) {
        $script:CapturedArgs.Add(($Arguments -join ' '))
        [pscustomobject]@{ExitCode=0;Output='Failed to read input in non-interactive mode.'}
    }
    $storeResult = Invoke-StoreStage -LogDirectory $testOutput
    Assert-Equal $storeResult.Status 'NeedsAttention' 'Zero Store exit code with failure is not verified success'
    Assert-Equal ($script:CapturedArgs -join ';') 'updates --apply;updates' 'Apply followed by non-applying verification scan'

    $script:StoreScanNumber = 0
    function Invoke-NativeCapture($Executable, $Arguments) {
        $script:StoreScanNumber++
        [pscustomobject]@{ ExitCode=0; Output=$(if ($script:StoreScanNumber -eq 1) { 'Updates available (1 found)' } else { 'No updates available.' }) }
    }
    $storeResult = Wait-StoreCompletion -Executable 'fixture-store.exe' -LogDirectory $testOutput -VerificationAttempts 2 -DelaySeconds 0
    Assert-Equal $storeResult.Status 'Verified' 'Wait for queued Store installations instead of failing immediately'
    Assert-Equal $script:StoreScanNumber 2 'Rescan after Store reports remaining queued update'
} finally { Set-Item -Path function:Invoke-NativeCapture -Value $nativeImplementation }

# 10. Driver Booster skip option
Assert-Equal (Invoke-DriverStage -Skip).Status 'Skipped' 'Skip driver stage without launching GUI'

# 11. Elevation without launching process
$startProcessImplementation = Get-Item function:Start-Process -ErrorAction SilentlyContinue
$script:MaintenanceScriptPath = "C:\Fixture with apostrophe's\Update-WeeklyMaintenance.ps1"
$script:WorkerArguments = $null
$script:ElevationCalls = 0
try {
    function Start-Process($FilePath, $Verb, $WindowStyle, [switch]$PassThru, $ArgumentList) {
        Assert-Equal $Verb RunAs 'Worker explicitly requests elevation'
        Assert-Equal $WindowStyle Normal 'User can see elevated update terminal'
        $script:WorkerArguments = $ArgumentList
        $script:ElevationCalls++
        $fake = [pscustomobject]@{ExitCode=0}
        $fake | Add-Member ScriptMethod WaitForExit { }
        $fake | Add-Member ScriptMethod Dispose { }
        $fake
    }
    Request-MaintenanceElevation -ScriptPath $script:MaintenanceScriptPath -NoRebootPrompt -StoreOnly
    Assert-Equal $script:ElevationCalls 1 'Elevate complete run only once'
    $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:WorkerArguments[-1]))
    $tokens=$null; $parseErrors=$null
    $null = [Management.Automation.Language.Parser]::ParseInput($decoded,[ref]$tokens,[ref]$parseErrors)
    Assert-Equal @($parseErrors).Count 0 'Worker invocation parses even with apostrophe in path'
    Assert-Equal ($decoded -match "apostrophe''s") $true 'Quote paths without code injection'
    Assert-Equal ($decoded -match '-StoreOnly' -and $decoded -match '-NoRebootPrompt') $true 'Preserve run options across single elevation'
    Assert-Equal ($decoded -match '-Apply') $false 'Do not pass obsolete -Apply flag'
    Assert-Equal ($decoded -match '-Worker') $false 'Do not spawn elevated stage workers'
} finally {
    Remove-Item function:Start-Process
    if ($startProcessImplementation) { Set-Item function:Start-Process $startProcessImplementation.ScriptBlock }
}

Write-Host "PASS: $script:Checks assertions; no update installers or reboot commands executed."
