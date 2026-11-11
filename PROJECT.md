# Project: FluentFlyout Auto-Updater & CI Hardening (Camino A)

## Architecture
FluentFlyout is a Windows flyout utility built with WPF (.NET 10) and packaged as an MSIX application via Windows Application Packaging Project (`FluentFlyoutMSIX.wapproj`).
The project architecture for updates and CI consists of:
1. **Application Layer (`FluentFlyoutWPF`)**:
   - `UpdateCheckerService.cs`: Queries the GitHub Releases API for fork repository releases (`unchihugo/FluentFlyout`), parses release tags/versions, extracts the installer asset URL (`*x64*Installer.zip`), and extracts the expected SHA-256 hash from release notes.
   - `UpdateInstallerService.cs`: Downloads the release installer zip asynchronously in-process (`HttpClient`), validates the SHA-256 hash in-process (`SHA256.HashDataAsync`), extracts the archive into a staging directory (`ZipFile.ExtractToDirectory`), generates a hardened decoupled updater script (`apply.ps1`), launches it with elevation (`powershell.exe -ExecutionPolicy Bypass -Verb runas`), and terminates the app gracefully.
   - `LicenseManager.cs`: Unlocks premium features under configuration `#if GITHUB_RELEASE`.
2. **Packaging Layer (`FluentFlyoutMSIX`)**:
   - `FluentFlyoutMSIX.wapproj`: DesktopBridge packaging project configured for `SideloadOnly` with test artifacts enabled (`GenerateTestArtifacts=True`) and package signing enabled (`AppxPackageSigningEnabled=True`).
   - `Package.appxmanifest`: Defines identity (`unchihugo.FluentFlyout`, `CN=49793F74-1457-4B66-A672-4ED3A640FC76`), capabilities, startup tasks, and COM activation.
3. **CI/CD Layer (`.github/workflows/build-msix.yml`)**:
   - Compiles WPF app and MSIX package on `windows-latest` with .NET 10 SDK and MSBuild.
   - Handles signing certificates dynamically (uses `MSIX_CERT_BASE64` secret if available, or generates a valid self-signed certificate matching the manifest publisher).
   - Stages the `_Test` folder into `SystemFiles/` alongside `FluentFlyout_Installer.bat` and `README.txt`.
   - Packages `FluentFlyout_<version>_x64_Installer.zip`, computes SHA-256 hash, and publishes the release and assets via GitHub CLI (`gh release`).
4. **Testing & Verification Layer (`tests/`)**:
   - Unit tests and automated offline verification harnesses exercising update check parsing, regex extraction, SHA-256 hashing, staging extraction, and script generation.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | GitHub Fork Endpoint Configuration | Parameterized fork target (`unchihugo/FluentFlyout`) in `UpdateCheckerService.cs`, 15s timeout, disable upstream fallback for GitHub builds | M1 | Survey (R1) |
| 2 | Robust SHA-256 Regex Extraction | Robust regex extracting SHA-256 checksum from release notes regardless of formatting or preceding tokens | M1 | Survey (R2) |
| 3 | Managed In-Process Download & Hash | Replace `curl.exe` with async `HttpClient` and `powershell.exe` with `SHA256.HashDataAsync` | M1 | Survey (R2) |
| 4 | Decoupled Installer Script Hardening | Pre-extract in C#, write `apply.ps1` with process wait (`Wait-Process`), bypass policy, directory change to `SystemFiles`, `-Force`, logging to `update_install.log`, and app relaunch | M1 | Survey (R2) |
| 5 | MSIX Packaging Configuration & Alignment | Configure `FluentFlyoutMSIX.wapproj` and `Package.appxmanifest` for sideload compatibility, publisher matching, and test artifact generation | M2 | Survey (R4) |
| 6 | CI Workflow .NET 10 SDK Setup | Add `actions/setup-dotnet@v5` with .NET 10.0.x in `build-msix.yml` to prevent `NETSDK1045` | M3 | Survey (R3) |
| 7 | CI Workflow Resilient Signing Strategy | Graceful secret decode or dynamic self-signed certificate generation matching publisher, passed to MSBuild | M3 | Survey (R3) |
| 8 | CI Sideload Packaging & Asset Assembly | Build mode `SideloadOnly`, sign package, stage `SystemFiles/Add-AppDevPackage.ps1`, compress zip, and upload `.sha256` companion | M3 | Survey (R3) |
| 9 | CI Release Publishing & Trigger Hardening | Add tag triggers (`tags: ['v*']`), preserve existing release notes when editing, and format checksum notes | M3 | Survey (R3) |
| 10| Offline E2E Verification & Test Suite | Test harnesses for update parsing, hash validation, zip extraction, decoupled script execution, and CI YAML validation | M4 | Acceptance Criteria |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Auto-Updater Refactoring & Hardening | Refactor `UpdateCheckerService.cs` and `UpdateInstallerService.cs` (Features 1-4) | None | DONE |
| M2 | MSIX Packaging & Manifest Alignment | Align `FluentFlyoutMSIX.wapproj` and `Package.appxmanifest` (Feature 5) | None | DONE |
| M3 | GitHub Actions CI/CD Pipeline | Overhaul `.github/workflows/build-msix.yml` (Features 6-9) | M1, M2 | DONE |
| M4 | E2E Verification & Audit | Offline simulation tests, checksum & installer harness, audit verification (Feature 10) | M1, M2, M3 | DONE |

## Interface Contracts
### `UpdateCheckerService` ↔ GitHub API & `UpdateInstallerService`
- **GitHub API Endpoint**: `https://api.github.com/repos/{owner}/{repo}/releases/latest`
- **Output Record**: `UpdateCheckResult` with:
  - `IsUpdateAvailable: bool`
  - `NewestVersion: string`
  - `AssetUrl: string` (must end with `Installer.zip` and contain `x64`)
  - `ExpectedSha256: string` (64-character hex lowercase/uppercase)
  - `ReleaseNotes: string`

### `UpdateInstallerService` ↔ Windows Operating System
- **Staging Directory**: `%TEMP%\FluentFlyout_Update_{timestamp}\`
- **Zip Archive**: `update.zip`
- **Extracted Contents**: `files\SystemFiles\Add-AppDevPackage.ps1`
- **Launcher Script**: `apply.ps1`
  - Parameters: `-ExecutionPolicy Bypass -NoProfile -File apply.ps1`
  - Elevation: `Verb = "runas"`
  - Logging: `update_install.log`

### CI Packaging ↔ GitHub Releases
- **Asset Name**: `FluentFlyout_{version}_x64_Installer.zip`
- **Release Body Format**:
  ```markdown
  GitHub Release x64 installer: FluentFlyout_{version}_x64_Installer.zip
  GitHub Release x64 checksum: {sha256_hash}
  ```
- **Companion Asset**: `FluentFlyout_{version}_x64_Installer.zip.sha256`

## Code Layout
- `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`: Update checker & API parser (Owned by M1 Worker)
- `FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs`: Download, hash verification, staging, launcher (Owned by M1 Worker)
- `FluentFlyoutMSIX/Package.appxmanifest`: MSIX manifest identity and capabilities (Owned by M2 Worker)
- `FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj`: Packaging project properties and targets (Owned by M2 Worker)
- `.github/workflows/build-msix.yml`: GitHub Actions CI/CD workflow (Owned by M3 Worker)
- `tests/`: Automated unit & simulation tests (Owned by M4 Worker)
