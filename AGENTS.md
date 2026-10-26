# Windows administration scripts

Primary branch: `master`.

## Scope and safeguards
- This repository contains PowerShell, Batch, and VBScript utilities. Preserve each script's supported Windows/runtime requirements and avoid unrelated rewrites of legacy utilities.
- Keep diffs focused and update affected README files. Supply credentials through protected configuration or credential stores.
- Do not execute system-changing scripts merely to validate them. Preview deletion targets; verify paths and permissions before changing files, registry settings, tasks, domain membership, or reboot behavior.

## WeeklyMaintenance
- Follow `WeeklyMaintenance/README.md`; use `WeeklyMaintenance/Run-WeeklyMaintenance.cmd` for normal execution and preserve its non-Store PowerShell 7 runtime selection.
- Preserve the single-run mutex and exact `RESTART` confirmation before rebooting. Keep unattended Store operations noninteractive and preserve vendor logging/file-attribute handling.

## Verification
- Parse affected PowerShell files with the matching runtime's PowerShell parser without executing them. Use isolated fixtures for behavior checks.
- Offline maintenance tests: `pwsh -NoProfile -File WeeklyMaintenance/Test-WeeklyMaintenance.ps1`.
- Batch/VBScript changes require syntax review and isolated validation appropriate to their supported host.
- Documentation-only changes require path/command review and `git diff --check`; do not run maintenance or reboot for documentation validation.

## Language, security, and Git completion
- All README files, documentation, and code comments MUST be in English.
- Before completion and before any push, scan working code, relevant untracked files, staged changes, and full Git history across all local refs for sensitive data (tokens, passwords, private keys, and credentials). Use a secret scanner, review findings, and never print secret values. Confirmed exposures block pushing until remediated; revoke/rotate exposed credentials and coordinate any shared-history rewrite.
- Inspect Git status before editing. Preserve unrelated changes, branches, worktrees, and stashes.
- Commit ALL task changes, including required tests and documentation, and integrate them into the primary branch. Remove all task-created temporary branches, worktrees, stashes, patches, and scratch files; retain permanent tests and operational data.
- Finish with no task-owned uncommitted changes. Verify Git status, integration into the primary branch, and branch/worktree cleanup; report unrelated pending work.
- Only after verification, secret review, commits, integration, and cleanup may the primary branch be pushed to GitHub. Do not push temporary branches or force-push automatically.

## Graphify
- For codebase questions, query an existing graph first; verify decisive findings against current source. Use path/explain for focused questions and wiki/report for broad navigation.
- If unavailable, stale, or insufficient, continue with source search and report the limitation.
- Refresh after relevant source changes using the installed skill. Review generated diffs, commit required outputs, and remove task-created disposable caches.
- For /graphify, follow the installed skill first.
