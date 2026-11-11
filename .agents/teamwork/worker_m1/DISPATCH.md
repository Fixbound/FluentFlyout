# Dispatch: Worker M1

**Role**: Auto-Updater Engineer
**Working Directory**: E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\
**Milestone**: M1 - Auto-Updater Refactoring & Hardening
**Exclusively Owned Files**:
- `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`
- `FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs`

**Context & Inputs**:
- Authoritative User Request: `E:\Programacion\FluentFlyout\.agents\teamwork\ORIGINAL_REQUEST.md`
- Project Architecture & Interfaces: `E:\Programacion\FluentFlyout\PROJECT.md`
- Explorer Survey 1 Report: `E:\Programacion\FluentFlyout\.agents\teamwork\explorer_survey_1\handoff.md` and `analysis.md`

**Objectives**:
1. Implement Requirement R1 in `UpdateCheckerService.cs`:
   - Parameterize GitHub fork target (`unchihugo/FluentFlyout`) via clean defaults/constants.
   - Increase GitHub API request timeout from 2s to 15s.
   - Under `#if GITHUB_RELEASE`, disable fallback to upstream `fluentflyout.com` so fork builds are never overwritten by upstream releases.
   - Harden regex parsing of SHA-256 hash from release body: use robust pattern matching `(?i)(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})` and fallback patterns.
2. Implement Requirement R2 in `UpdateInstallerService.cs`:
   - Replace external `curl.exe` with managed async `HttpClient` streaming download.
   - Replace external `powershell.exe` SHA-256 check with native `System.Security.Cryptography.SHA256.HashDataAsync`.
   - Extract archive in C# using `System.IO.Compression.ZipFile.ExtractToDirectory` before initiating shutdown; verify `SystemFiles\Add-AppDevPackage.ps1` exists.
   - Generate `apply.ps1` that:
     * Waits for current process ID to exit (`Wait-Process -Id <pid> -Timeout 30`) to avoid MSIX `0x80073D02` lock.
     * Changes directory to `SystemFiles`.
     * Executes `Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry`.
     * Logs output to `update_install.log`.
     * Relaunches the app using `Get-AppxPackage '*FluentFlyout*'`.
   - Launch `powershell.exe` with `-ExecutionPolicy Bypass`, `UseShellExecute = true`, and `Verb = "runas"` for UAC elevation.
   - Clean error handling, logging, and non-blocking async execution.
3. Verify compilation:
   - Run `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
   - Must build with 0 errors and 0 warnings.
4. Produce `changes.md` and `handoff.md` in your working directory.


## 2026-11-10T19:44:08Z
[Message] timestamp=2026-11-10T19:44:08Z sender=1641a46b-a931-42fe-9167-dd42fb177b07 priority=MESSAGE_PRIORITY_HIGH content=You are Worker subagent for Milestone 1 in the Project Orchestrator team.
Your working directory is: E:\Programacion\FluentFlyout\.agents\teamwork\worker_m1\
The authoritative user request is located at: E:\Programacion\FluentFlyout\.agents\teamwork\ORIGINAL_REQUEST.md
Please read ORIGINAL_REQUEST.md, E:\Programacion\FluentFlyout\PROJECT.md, and DISPATCH.md in your working directory before starting.
Also read the detailed survey findings in E:\Programacion\FluentFlyout\.agents\teamwork\explorer_survey_1\handoff.md and analysis.md.
