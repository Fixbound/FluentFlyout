# BRIEFING — 2026-11-10T19:54:00Z

## Mission
Implement Milestone 1 (M1): Refactor and harden UpdateCheckerService.cs and UpdateInstallerService.cs for GitHub fork auto-updates.

## 🔒 My Identity
- Archetype: worker
- Roles: implementer, qa
- Working directory: E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\
- Original parent: 1641a46b-a931-42fe-9167-dd42fb177b07
- Milestone: M1 - Auto-Updater Refactoring & Hardening

## 🔒 Key Constraints
- Exclusively own and edit:
  * FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs
  * FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs
- DO NOT modify any other files in the project.
- DO NOT cheat, hardcode test results, or create facade implementations.
- Must compile cleanly with 0 errors and 0 warnings under "GitHub Release" (x64).

## Current Parent
- Conversation ID: 1641a46b-a931-42fe-9167-dd42fb177b07
- Updated: not yet

## Task Summary
- **What to build**:
  1. `UpdateCheckerService.cs`: Parameterize GitHub fork target (`unchihugo/FluentFlyout`), 15s timeout, disable upstream fallback for `#if GITHUB_RELEASE`, harden SHA-256 regex, select `*x64*Installer.zip`.
  2. `UpdateInstallerService.cs`: In-process async `HttpClient` streaming download, in-process `SHA256.HashDataAsync`, pre-shutdown extraction via `ZipFile.ExtractToDirectory`, generation of robust `apply.ps1` (Wait-Process, cd SystemFiles, Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry, logging to update_install.log, relaunch via Get-AppxPackage), launch via elevated PowerShell (`Verb="runas"`, `UseShellExecute=true`, `-ExecutionPolicy Bypass`).
- **Success criteria**:
  * Clean compilation under `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64` (0 errors, 0 warnings).
  * Robust updater and checker logic meeting all R1 & R2 specifications.
- **Interface contracts**: PROJECT.md § Interface Contracts
- **Code layout**: PROJECT.md § Code Layout

## Key Decisions Made
- Used dedicated `HttpClient` in `UpdateCheckerService` with 15s timeout and dynamic User-Agent (`FluentFlyout/{version}`) to eliminate reliance on `FluentFlyoutApiClient`'s 2s timeout.
- Strictly isolated upstream site fallback under `#if GITHUB_RELEASE` to protect unlocked fork builds from upstream prompt overwrites.
- In `UpdateInstallerService`, replaced `curl.exe` with managed async `HttpClient` streaming download and `powershell.exe` with native `SHA256.HashDataAsync`.
- Pre-shutdown extraction in C# via `ZipFile.ExtractToDirectory` validates `Add-AppDevPackage.ps1` prior to app termination.
- Generated `apply.ps1` includes process exit wait, transcript logging, directory change to `SystemFiles`, silent execution with `-Force`, and app relaunch.
- Elevated launch via `powershell.exe` with `Verb = "runas"` and `-ExecutionPolicy Bypass`.
- Thread safety in `ShowUpdateChoiceAndApplyAsync` using `Dispatcher.InvokeAsync`.

## Artifact Index
- E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\DISPATCH.md — Dispatch instructions
- E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\BRIEFING.md — Situational awareness
- E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\progress.md — Progress heartbeat
- E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\changes.md — Change log
- E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\handoff.md — 5-component handoff report

## Change Tracker
- **Files modified**:
  * `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs` — GitHub fork parameters, 15s timeout, strictly disabled site fallback under GITHUB_RELEASE, hardened SHA-256 regex, x64 asset selection, robust version parsing.
  * `FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs` — Managed streaming download, native SHA-256 hashing, pre-shutdown zip extraction, robust apply.ps1 generator, elevated execution, UI thread safety.
- **Build status**: `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64` -> Build succeeded. 0 Warning(s), 0 Error(s).
- **Pending issues**: None

## Quality Status
- **Build/test result**: Pass (0 errors, 0 warnings on modified files; 0 warnings on GitHub Release build)
- **Lint status**: Clean (enforce code style passes)
- **Tests added/modified**: Verified regex patterns (5/5 formats) and apply.ps1 PowerShell parser syntax (0 syntax errors).
