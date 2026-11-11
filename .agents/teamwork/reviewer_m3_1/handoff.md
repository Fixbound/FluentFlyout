# Quality & Adversarial Review Report: Milestone 3 CI Workflow

**Reviewer / Critic Agent**: `reviewer_m3_1`  
**Working Directory**: `E:\Programacion\FluentFlyout\.agents\teamwork\reviewer_m3_1\`  
**Target File**: `E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml`  
**Reviewed Agent**: `worker_m3` (`.agents/teamwork/worker_m3/handoff.md`)  
**Verdict**: **APPROVE**  
**Overall Risk Assessment**: **LOW**

---

## 1. Observation

### 1.1 Baseline Build Verification
- **Command Executed**:
  `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
- **Output / Result**:
  ```text
  Determining projects to restore...
  All projects are up-to-date for restore.
  FluentFlyout.SourceGenerators -> E:\Programacion\FluentFlyout\FluentFlyout.SourceGenerators\bin\x64\GitHub Release\netstandard2.0\FluentFlyout.SourceGenerators.dll
  FluentFlyout -> E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll

  Build succeeded.
      0 Warning(s)
      0 Error(s)
  Time Elapsed 00:00:01.42
  ```

### 1.2 Workflow Structure & YAML Inspection
- **File**: `E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml`
- **Triggers (Lines 3–11)**:
  ```yaml
  on:
    workflow_dispatch:
    push:
      branches:
        - master
      tags:
        - 'v*'
      paths:
        - 'FluentFlyoutMSIX/Package.appxmanifest'
  ```
  Verified valid YAML structure.
- **SDK Setup & Tooling (Lines 34–40)**:
  ```yaml
  - name: Setup .NET SDK
    uses: actions/setup-dotnet@v5
    with:
      dotnet-version: 10.0.x

  - name: Setup MSBuild
    uses: microsoft/setup-msbuild@v3
  ```
  Verified `actions/setup-dotnet@v5` with `dotnet-version: 10.0.x` positioned prior to MSBuild setup.
- **Dependency Restoration (Lines 76–77)**:
  ```yaml
  - name: Restore dependencies
    run: dotnet restore $env:SOLUTION_PATH
  ```
- **Signing Certificate Fallback (Lines 42–74)**:
  Inspects `$env:CERT_BASE64`. If empty or whitespace, dynamically generates a self-signed code-signing certificate with `-Subject "CN=49793F74-1457-4B66-A672-4ED3A640FC76"` matching `FluentFlyoutMSIX\Package.appxmanifest` line 13 (`Publisher="CN=49793F74-1457-4B66-A672-4ED3A640FC76"`).
- **Packaging Parameters (Lines 87–99)**:
  Configures `$buildMode = if ($env:CONFIGURATION -eq 'GitHub Release') { 'SideloadOnly' } else { 'StoreUpload' }`, passes `/p:AppxPackageSigningEnabled=true`, `/p:PackageCertificateKeyFile="$env:PFX_PATH"`, `/p:PackageCertificatePassword="$env:PFX_PASSWORD"`, and `/p:GenerateTestArtifacts=true`. Note trailing double backslash `/p:AppxPackageDir="$env:GITHUB_WORKSPACE\AppxPackages\\"` preventing Windows quote escaping.
- **Installer Staging Structure (Lines 101–120)**:
  Locates `*_Test` directory in `AppxPackages`, copies contents to `InstallerOutput\SystemFiles`, and copies `FluentFlyout_Installer.bat` and `README.txt` into root `InstallerOutput\`.
- **Release Checksum & Companion Asset (Lines 127–181)**:
  Computes SHA-256 hash using `(Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()`, generates `$zipPath.sha256`, creates/edits release via `gh release view`/`create`/`edit` with `--notes-file` and UTF-8 encoding, and uploads both `.zip` and `.sha256` using `--clobber`.

### 1.3 Independent Script & AST Validation
- **PowerShell AST Check**:
  Executed `python E:\Programacion\FluentFlyout\.agents\teamwork\worker_m3\verify_workflow.py`. All 6 PowerShell script steps parsed with 0 syntax errors.
- **Adversarial Test Suite Execution**:
  Executed `pwsh -NoProfile -ExecutionPolicy Bypass -File E:\Programacion\FluentFlyout\.agents\teamwork\reviewer_m3_1\adversarial_test.ps1`.
  - Version extraction: `2.16.0.0` -> `2.16.0`.
  - Dynamic certificate subject match: `CN=49793F74-1457-4B66-A672-4ED3A640FC76` matches manifest publisher exactly.
  - Release notes regex replacement: verified replacement, appending to existing notes, and brand-new release notes.
  - Interoperability with `UpdateCheckerService.ParseInstallerAsset`: verified that all 3 release note formats extract the expected asset URL and SHA-256 hash correctly.
- **Archive Extraction Hierarchy**:
  Verified via temporary pwsh run that `Compress-Archive -Path "InstallerOutput\*"` produces an archive where `SystemFiles\Add-AppDevPackage.ps1` extracts directly to `extractDir\SystemFiles\Add-AppDevPackage.ps1`, matching `UpdateInstallerService.cs:263` and `FluentFlyout_Installer.bat:13`.

---

## 2. Logic Chain

1. **Trigger Semantics (Observation 1.2)**:
   In GitHub Actions, `push` triggers with both `tags:` and `paths:` apply path filters exclusively to branch pushes. Tag pushes (`v*`) ignore path filters, ensuring that tagging any commit triggers a full release build. Pushes to `master` trigger only when `Package.appxmanifest` is modified, preventing unnecessary builds on doc or non-packaging commits. `workflow_dispatch` allows on-demand execution.
2. **Compiler Environment Alignment (Observation 1.1, 1.2)**:
   `FluentFlyout.csproj` targets `net10.0-windows10.0.22000.0`. Installing the .NET 10.0.x SDK via `actions/setup-dotnet@v5` sets `DOTNET_ROOT` and prepends the .NET 10 SDK to `PATH` before `microsoft/setup-msbuild@v3` is configured. This ensures the MSBuild SdkResolver discovers .NET 10, eliminating `NETSDK1045` failures.
3. **Resilient Signing Architecture (Observation 1.2, 1.3)**:
   If `secrets.MSIX_CERT_BASE64` is configured in the repository, it is decoded to `$env:RUNNER_TEMP\FluentFlyout_Signing.pfx`. If empty (e.g. initial fork deployments or CI test runs), PowerShell generates a self-signed certificate with Code Signing EKU (`1.3.6.1.5.5.7.3.3`) matching publisher `CN=49793F74-1457-4B66-A672-4ED3A640FC76`. MSBuild succeeds in signing the package and generating the `*_Test` artifact folder.
4. **Packaging & Staging Alignment (Observation 1.2, 1.3)**:
   Passing `/p:UapAppxPackageBuildMode=SideloadOnly` and `/p:GenerateTestArtifacts=true` causes MSBuild to output the `*_Test` folder containing `Add-AppDevPackage.ps1` and the test certificate. The workflow stages these inside `InstallerOutput\SystemFiles\`, alongside root helper scripts `FluentFlyout_Installer.bat` and `README.txt`. When compressed to `FluentFlyout_<version>_x64_Installer.zip` and unpacked by `UpdateInstallerService.cs`, `extractDir\SystemFiles\Add-AppDevPackage.ps1` exists at the expected path.
5. **Integrity & Checksum Contract (Observation 1.2, 1.3)**:
   The computed SHA-256 hash is embedded in the release notes in the exact format:
   `GitHub Release x64 installer: FluentFlyout_<version>_x64_Installer.zip`
   `GitHub Release x64 checksum: <sha256>`
   This format was stress-tested against `UpdateCheckerService.ParseInstallerAsset` and confirmed to match all regex patterns (`Sha256WorkflowRegex`, `Sha256X64Regex`, and `Sha256SurveyRegex`). The companion `.sha256` asset is also uploaded with `--clobber`.
6. **Integrity Violations Check**:
   No hardcoded test mocks, bypass shortcuts, or dummy facades exist in the workflow. All outputs are computed dynamically at runtime from the actual build artifacts.

---

## 3. Caveats

- **GitHub Remote Infrastructure**: Live GitHub Actions execution requires pushing to GitHub and triggering the runner. Independent local testing used Python YAML AST verification, PowerShell 7 AST parsing, Windows SDK certificate creation, and MSBuild / dotnet build execution to prove runner compatibility.
- **Repository Secrets**: Repositories without `MSIX_CERT_BASE64` will generate self-signed certificates. This is intended and compatible with Windows Developer Mode sideloading via `Add-AppDevPackage.ps1`.

---

## 4. Conclusion

The implementation of Milestone 3 by `worker_m3` adheres strictly to Requirement **R3**, aligns with project interface contracts in `PROJECT.md`, passes all acceptance criteria, and compiles cleanly with 0 errors and 0 warnings.

**Verdict**: **APPROVE**

---

## 5. Verification Method

To independently verify these results:

1. **Verify Baseline .NET Build**:
   ```powershell
   Set-Location "E:\Programacion\FluentFlyout"
   dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64
   ```
   *Expected Result*: `Build succeeded. 0 Warning(s) 0 Error(s)`.

2. **Run Adversarial Review Test Suite**:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "E:\Programacion\FluentFlyout\.agents\teamwork\reviewer_m3_1\adversarial_test.ps1"
   ```
   *Expected Result*: `=== ALL ADVERSARIAL STRESS TESTS PASSED SUCCESSFULLY! ===`.

3. **Verify Worker M3 Syntax Validation**:
   ```powershell
   python "E:\Programacion\FluentFlyout\.agents\teamwork\worker_m3\verify_workflow.py"
   ```
   *Expected Result*: `ALL WORKFLOW CHECKS PASSED SUCCESSFULLY!`.
