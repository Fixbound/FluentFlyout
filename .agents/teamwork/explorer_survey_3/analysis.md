# Technical Analysis: GitHub Actions CI/CD Workflow & Release Automation (Requirement R3 & CI Criteria)

**Agent**: `explorer_survey_3`  
**Target Codebase**: `E:\Programacion\FluentFlyout`  
**Date**: 2026-11-10  
**Status**: Read-Only Survey Complete  

---

## 1. Executive Summary

Requirement **R3** and its associated acceptance criteria require adjusting and validating `.github/workflows/build-msix.yml` to:
1. Compile `FluentFlyoutMSIX.wapproj` under configuration `"GitHub Release"` (x64) with 0 errors.
2. Package the installer zip `FluentFlyout_<version>_x64_Installer.zip` incorporating `SystemFiles/Add-AppDevPackage.ps1`, the signed MSIX package/bundle, public test certificate (`.cer`), dependencies, and helper scripts (`FluentFlyout_Installer.bat`, `README.txt`).
3. Compute the SHA-256 checksum of the installer zip.
4. Publish the asset to GitHub Releases and embed the SHA-256 checksum in the release notes such that `UpdateCheckerService.cs` correctly discovers and verifies it.

Our investigation revealed critical defects in the current `.github/workflows/build-msix.yml` workflow that prevent reliable CI execution and break both manual installation and the in-app auto-updater:
- **Fork Crash on Secret Decoding**: Step `Decode signing certificate` unconditionally executes `[Convert]::FromBase64String("${{ secrets.MSIX_CERT_BASE64 }}")`. If this secret is missing or empty (e.g., in forks or community PRs), PowerShell throws an unhandled exception and aborts the entire workflow immediately.
- **Unsigned MSIX & Missing Test Certificate**: The workflow explicitly passes `/p:AppxPackageSigningEnabled=false` to MSBuild and never passes the decoded certificate. Consequently, MSBuild generates an unsigned MSIX package and omits the `.cer` certificate from the `*_Test` folder. Windows AppX Deployment Service refuses to install unsigned MSIX packages (`0x800B0100`), and `Add-AppDevPackage.ps1` fails with "Certificate file not found".
- **Missing .NET 10 SDK Setup**: `FluentFlyout.csproj` targets `net10.0-windows10.0.22000.0`. While `.github/workflows/dotnet-format.yml` includes `actions/setup-dotnet@v5` (`dotnet-version: 10.0.x`), `build-msix.yml` omits `setup-dotnet` entirely, risking compiler failures on runners where the .NET 10 SDK is not in MSBuild's SDK resolver path.
- **Inappropriate Build Mode**: The workflow passes `/p:UapAppxPackageBuildMode=StoreUpload` instead of `SideloadOnly` for the GitHub Release matrix entry.
- **Fragile Test Folder Discovery**: The command `Move-Item $testFolder.FullName "$outDir\SystemFiles"` assumes `$testFolder` is non-null and non-nested. If MSBuild fails to produce a folder matching `*_Test`, `$testFolder` is `$null` and the step fails with `Cannot bind argument to parameter 'Path' because it is null`.
- **Missing Release Tag Triggers**: The workflow only triggers on `workflow_dispatch` and `push` to `master` with path filter on `FluentFlyoutMSIX/Package.appxmanifest`. Pushing a release tag (e.g. `v2.16.0`) does not trigger the build.
- **Destructive Release Notes Overwrite**: When updating an existing release, `gh release edit $tag --title ... --notes $notes` completely replaces any existing changelog/release body instead of updating or appending the checksum metadata.
- **Missing Standalone Companion Checksum File**: The SHA-256 checksum is placed in the release body, but standard best practice companion file `*.sha256` is not uploaded as a separate release asset.

---

## 2. Codebase & Configuration Audit

### 2.1 Project Architecture and Build Matrix
- **Solution**: `FluentFlyout.sln` (Format 12.00, VS Version 18).
  - Contains three projects:
    1. `FluentFlyoutWPF\FluentFlyout.csproj` (`{A3576152-7AF6-4136-992A-1B3C1091652A}`)
    2. `FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj` (`{7C7CB0B2-26B9-4B8B-B5E8-30ABF5E2B331}`)
    3. `FluentFlyout.SourceGenerators\FluentFlyout.SourceGenerators.csproj` (`{5DB1F6F1-940A-4174-BF1C-4DF0739058B6}`)
- **Configurations Defined**:
  - `Debug`, `Release`, and `GitHub Release`.
  - In `FluentFlyout.csproj`:
    ```xml
    <TargetFramework>net10.0-windows10.0.22000.0</TargetFramework>
    <Configurations>Debug;Release;GitHub Release</Configurations>
    <PropertyGroup Condition="'$(Configuration)' == 'GitHub Release'">
      <DefineConstants>GITHUB_RELEASE</DefineConstants>
    </PropertyGroup>
    ```
  - When `GITHUB_RELEASE` is defined, `LicenseManager.cs` unlocks all premium features unconditionally without querying the Microsoft Store AppLicense API (`_isStoreVersion = false`, `_isPremiumUnlocked = true`).

### 2.2 Compilation Verification (`dotnet build`)
We independently verified the first acceptance criterion:
```powershell
dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64
```
**Result**: Build succeeded with **0 errors and 0 warnings**.
- `FluentFlyout.SourceGenerators -> FluentFlyout.SourceGenerators.dll`
- `FluentFlyout -> FluentFlyout.dll`

### 2.3 WAP Packaging (`FluentFlyoutMSIX.wapproj`) Properties
Key properties in `FluentFlyoutMSIX.wapproj`:
- `TargetPlatformVersion`: `10.0.26100.0`
- `TargetPlatformMinVersion`: `10.0.19041.0`
- `EntryPointProjectUniqueName`: `..\FluentFlyoutWPF\FluentFlyout.csproj`
- `GenerateTestArtifacts`: `True`
- `AppxBundlePlatforms`: `x64`
- `AppxBundle`: Set to `Always` under `GitHub Release|x64`
- `PackageCertificateThumbprint`: `25D3EFB3B470444AB88088492FCDA18F99BAF513`
- `AppxManifest`: `Package.appxmanifest`
  - `Identity.Name`: `unchihugo.FluentFlyout`
  - `Identity.Publisher`: `CN=49793F74-1457-4B66-A672-4ED3A640FC76`
  - `Identity.Version`: `2.16.0.0`
- **Certificate Files in Repo**: Neither `FluentFlyoutMSIX_TemporaryKey.pfx` nor `Package.StoreAssociation.xml` are checked into the repository (both are gitignored by `.gitignore` lines 220 and 239).

### 2.4 MSBuild Engine & SDK Resolver Requirements
- `FluentFlyoutMSIX.wapproj` uses `Microsoft.DesktopBridge.props` and `Microsoft.DesktopBridge.targets`. These targets exist only within the Visual Studio installation (`$(MSBuildExtensionsPath)\Microsoft\DesktopBridge\`), so `.wapproj` cannot be compiled via `dotnet msbuild`. It **must** be compiled with Visual Studio MSBuild (`msbuild.exe`).
- When MSBuild evaluates the referenced project `FluentFlyout.csproj` (`net10.0-windows10.0.22000.0`), the .NET 10 SDK requires MSBuild version 18.0+.
- Therefore, in CI (`windows-latest`), both `actions/setup-dotnet` (providing the .NET 10 SDK) and `microsoft/setup-msbuild` (providing Visual Studio MSBuild) must be configured in harmony.

---

## 3. Analysis of `.github/workflows/build-msix.yml`

### 3.1 Triggers and Events
Current trigger block:
```yaml
on:
  workflow_dispatch:
  push:
    branches:
      - master
    paths:
      - 'FluentFlyoutMSIX/Package.appxmanifest'
```
**Findings**:
1. No `tags` trigger is defined. When releases are created via git tags (`git push origin v2.16.0`), GitHub Actions ignores the push.
2. In GitHub Actions, combining `branches`, `tags`, and `paths` requires careful handling: path filters are evaluated only for branch pushes and ignored for tag pushes.
3. Recommended triggers:
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

### 3.2 Matrix Configuration
```yaml
strategy:
  matrix:
    configuration: ["GitHub Release", "Release"]
```
**Findings**:
- Job generates two parallel runs:
  - `"GitHub Release"`: Full premium features unlocked via `GITHUB_RELEASE` preprocessor symbol; published to GitHub Releases.
  - `"Release"`: Store-ready binaries uploaded as GitHub Actions artifacts for manual validation or Microsoft Store submission.
- The separation is sound; step `Publish GitHub Release installer` is correctly conditional on `if: matrix.configuration == 'GitHub Release'`.

### 3.3 Missing .NET 10 Setup Step
In `build-msix.yml`:
```yaml
      - name: Checkout
        uses: actions/checkout@v6

      - name: Setup MSBuild
        uses: microsoft/setup-msbuild@v3
```
Notice `dotnet-format.yml` contains:
```yaml
      - name: Setup .NET
        uses: actions/setup-dotnet@v5
        with:
          dotnet-version: 10.0.x
```
Without `actions/setup-dotnet` in `build-msix.yml`, runners may resolve an older SDK or fail with `NETSDK1045` during package restore and compilation.

### 3.4 NuGet Restore Step
Current command:
```powershell
nuget restore $env:SOLUTION_PATH
```
While `nuget.exe` exists on GitHub runners, restoring SDK-style projects like `FluentFlyout.csproj` with standalone `nuget.exe` is deprecated and prone to missing transitive dependencies. Using `dotnet restore $env:SOLUTION_PATH` or `msbuild $env:SOLUTION_PATH -t:restore` is modern, robust, and utilizes the active .NET 10 SDK.

### 3.5 App Version Extraction
Current command:
```powershell
[xml]$manifest = Get-Content 'FluentFlyoutMSIX\Package.appxmanifest'
$fullVersion = $manifest.Package.Identity.Version
$version = ($fullVersion -split '\.')[0..2] -join '.'
echo "APP_VERSION=$version" >> $env:GITHUB_ENV
```
**Findings**:
- `Package.appxmanifest` has `Version="2.16.0.0"`.
- `($fullVersion -split '\.')[0..2] -join '.'` cleanly produces `"2.16.0"`.
- Setting `APP_VERSION=2.16.0` in `$env:GITHUB_ENV` makes it available to subsequent steps.
- Safe file append syntax:
  `"APP_VERSION=$version" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8` prevents encoding anomalies across PowerShell versions.

### 3.6 Certificate Decoding and Signing Flaw (Critical)
Current implementation:
```yaml
      - name: Decode signing certificate
        run: |
          $cert = [Convert]::FromBase64String("${{ secrets.MSIX_CERT_BASE64 }}")
          [IO.File]::WriteAllBytes("$env:RUNNER_TEMP\cert.pfx", $cert)
```
Followed by:
```yaml
      - name: Build & Package (MSIX)
        run: |
          msbuild $env:WAP_PROJECT_PATH `
            /p:Configuration=$env:CONFIGURATION `
            /p:Platform=$env:PLATFORM `
            /p:UapAppxPackageBuildMode=StoreUpload `
            /p:AppxPackageDir="$env:GITHUB_WORKSPACE\AppxPackages\\" `
            /p:AppxPackageSigningEnabled=false `
```
**Severe Architectural Flaws**:
1. **Crash on missing secret**: If `MSIX_CERT_BASE64` is empty, `FromBase64String("")` crashes immediately:
   `Exception calling "FromBase64String" with "1" argument(s): "Invalid length for a Base-64 char array or string."`
2. **Decoded certificate never used**: `$env:RUNNER_TEMP\cert.pfx` is ignored because MSBuild is not given `/p:PackageCertificateKeyFile`.
3. **Unsigned package generation**: `/p:AppxPackageSigningEnabled=false` produces an unsigned `.msixbundle` / `.msix`.
4. **Failure of `Add-AppDevPackage.ps1`**: Because signing is disabled, MSBuild does not export a `.cer` certificate to `*_Test`. When `Add-AppDevPackage.ps1` runs on the user's machine, it halts immediately with `Error: Certificate file not found`.
5. **Failure of Windows MSIX Deployment**: Windows rejects installation of unsigned packages (`0x800B0100`).

**Required Fix**:
Implement resilient certificate handling that supports both production secrets and automated self-signed development certificates for forks:
```powershell
$pfxPath = "$env:RUNNER_TEMP\FluentFlyout_Signing.pfx"
$pfxPassword = "${{ secrets.MSIX_CERT_PASSWORD }}"
if ([string]::IsNullOrWhiteSpace($pfxPassword)) {
    $pfxPassword = "FluentFlyoutSideloadPassword123!"
}

$certBase64 = "${{ secrets.MSIX_CERT_BASE64 }}".Trim()
if (-not [string]::IsNullOrEmpty($certBase64)) {
    Write-Host "Using provided repository secret MSIX_CERT_BASE64..."
    $certBytes = [Convert]::FromBase64String($certBase64)
    [IO.File]::WriteAllBytes($pfxPath, $certBytes)
} else {
    Write-Host "No MSIX_CERT_BASE64 secret found; generating self-signed development certificate..."
    $secPass = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
    $cert = New-SelfSignedCertificate -Type Custom `
        -Subject "CN=49793F74-1457-4B66-A672-4ED3A640FC76" `
        -KeyUsage DigitalSignature `
        -FriendlyName "FluentFlyout Sideload Cert" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPass | Out-Null
}

echo "PFX_PATH=$pfxPath" >> $env:GITHUB_ENV
echo "PFX_PASSWORD=$pfxPassword" >> $env:GITHUB_ENV
```
And in MSBuild execution:
```powershell
msbuild $env:WAP_PROJECT_PATH `
  /p:Configuration=$env:CONFIGURATION `
  /p:Platform=$env:PLATFORM `
  /p:UapAppxPackageBuildMode=SideloadOnly `
  /p:AppxPackageDir="$env:GITHUB_WORKSPACE\AppxPackages\\" `
  /p:AppxPackageSigningEnabled=true `
  /p:PackageCertificateKeyFile="$env:PFX_PATH" `
  /p:PackageCertificatePassword="$env:PFX_PASSWORD" `
  /p:GenerateTestArtifacts=true
```

### 3.7 MSIX Installer Packaging & Layout
Current step:
```powershell
$outDir = "$env:GITHUB_WORKSPACE\InstallerOutput"
New-Item -ItemType Directory -Path $outDir | Out-Null
$testFolder = Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Directory |
  Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1
Move-Item $testFolder.FullName "$outDir\SystemFiles"
Copy-Item ".github\build-files\FluentFlyout_Installer.bat" "$outDir\"
Copy-Item ".github\build-files\README.txt" "$outDir\"
```
And downstream zip step:
```powershell
Compress-Archive -Path "InstallerOutput\*" -DestinationPath $zipPath
```

**Verification of Layout Compatibility**:
- Zip Root contains:
  - `FluentFlyout_Installer.bat`
  - `README.txt`
  - `SystemFiles\`
    - `Add-AppDevPackage.ps1`
    - `Add-AppDevPackage.resources\`
    - `*.cer`
    - `*.msixbundle` (or `*.msix`)
    - `Dependencies\`
- In `UpdateInstallerService.cs`:
  ```csharp
  var extractDir = Path.Join(runDir, "files");
  var zipPath = Path.Join(runDir, "update.zip");
  var installerScript = Path.Join(extractDir, "SystemFiles\\Add-AppDevPackage.ps1");
  var applyScript = Path.Join(runDir, "apply.ps1");

  var scriptBody =
      "Expand-Archive -LiteralPath " + Quote(zipPath) + " -DestinationPath " + Quote(extractDir) + "\r\n" +
      "& " + Quote(installerScript) + "\r\n";
  ```
  When `update.zip` is unpacked into `extractDir`, `extractDir\SystemFiles\Add-AppDevPackage.ps1` is located at the exact expected relative path.
- In `FluentFlyout_Installer.bat`:
  ```bat
  cd /d "%~dp0SystemFiles"
  PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& './Add-AppDevPackage.ps1' -SkipLoggingTelemetry"
  ```
  This also matches the layout.

**Hardening Needed**:
Instead of a simple `Move-Item` which fails if `$testFolder` is `$null` or if `SystemFiles` directory already exists:
```powershell
$outDir = "$env:GITHUB_WORKSPACE\InstallerOutput"
$systemFilesDir = Join-Path $outDir "SystemFiles"
New-Item -ItemType Directory -Path $systemFilesDir -Force | Out-Null

$testFolder = Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Directory -Recurse |
  Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1

if (-not $testFolder) {
  Write-Error "No *_Test folder found in AppxPackages. Directory listing:"
  Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Recurse | Select-Object FullName
  exit 1
}

Copy-Item -Path "$($testFolder.FullName)\*" -Destination $systemFilesDir -Recurse -Force
Copy-Item ".github\build-files\FluentFlyout_Installer.bat" "$outDir\"
Copy-Item ".github\build-files\README.txt" "$outDir\"
```

### 3.8 SHA-256 Checksum & Release Publishing
Current step:
```powershell
$zipName = "FluentFlyout_${{ env.APP_VERSION }}_${{ env.PLATFORM }}_Installer.zip"
$zipPath = "$env:GITHUB_WORKSPACE\$zipName"
Remove-Item $zipPath -ErrorAction Ignore
Compress-Archive -Path "InstallerOutput\*" -DestinationPath $zipPath
$sha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
$tag = "v${{ env.APP_VERSION }}"
$notes = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"
gh release view $tag 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  gh release create $tag --title "FluentFlyout $tag" --notes $notes
} else {
  gh release edit $tag --title "FluentFlyout $tag" --notes $notes
}
gh release upload $tag $zipPath --clobber
```

**Regex Matching in `UpdateCheckerService.cs`**:
In `UpdateCheckerService.cs` (lines 135–136):
```csharp
var match = Regex.Match(bodyElement.GetString() ?? string.Empty, @"GitHub Release x64\D*?([0-9a-fA-F]{64})");
sha256 = (match.Success && match.Groups.Count > 1) ? match.Groups[1].Value : string.Empty;
```
The string generated in the notes:
`"GitHub Release x64 checksum: $sha"`
`\D*?` matches ` checksum: ` and `([0-9a-fA-F]{64})` captures `$sha`.
This regex match succeeds.

**Enhancements Needed**:
1. **Preserve Existing Release Notes**:
   If the release already exists (for example, authored by maintainers with changelog and release notes), editing with `--notes $notes` destroys the original body.
   Instead:
   ```powershell
   $releaseExists = $false
   $existingNotes = ""
   try {
     $viewOutput = gh release view $tag --json body -q .body 2>$null
     if ($LASTEXITCODE -eq 0) {
       $releaseExists = $true
       $existingNotes = $viewOutput
     }
   } catch {
     $releaseExists = $false
   }

   $checksumBlock = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"

   if (-not $releaseExists) {
     gh release create $tag --title "FluentFlyout $tag" --notes $checksumBlock
   } else {
     if ($existingNotes -match 'GitHub Release x64\D*?[0-9a-fA-F]{64}') {
       $updatedNotes = $existingNotes -replace 'GitHub Release x64\D*?[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
     } else {
       $updatedNotes = "$existingNotes`n`n$checksumBlock"
     }
     gh release edit $tag --notes $updatedNotes
   }
   ```
2. **Companion Checksum File**:
   Generate `$zipPath.sha256`:
   ```powershell
   $shaFile = "$zipPath.sha256"
   "$sha  $zipName" | Out-File -FilePath $shaFile -Encoding ascii
   gh release upload $tag $shaFile --clobber
   ```
   This provides standard checksum verification for CLI tools (`sha256sum -c`).

---

## 4. Synthesis and Cross-Component Dependencies

| Requirement / Component | Current Implementation | Status | Corrective Action |
|---|---|---|---|
| **R3.1: MSBuild Setup & .NET SDK** | `setup-msbuild@v3`, missing `setup-dotnet` | ⚠️ Incomplete | Add `actions/setup-dotnet@v5` (`dotnet-version: 10.0.x`) and `dotnet restore`. |
| **R3.2: Signing Certificate** | Decodes `MSIX_CERT_BASE64` with no fallback, passes `SigningEnabled=false` | ❌ Broken | Graceful fallback to `New-SelfSignedCertificate` when secret is absent; pass `/p:AppxPackageSigningEnabled=true /p:PackageCertificateKeyFile=...`. |
| **R3.3: Packaging Mode** | `/p:UapAppxPackageBuildMode=StoreUpload` | ⚠️ Suboptimal | Use `SideloadOnly` for GitHub Release configuration to generate clean test artifacts. |
| **R3.4: Installer Zip Layout** | `Move-Item $testFolder.FullName "$outDir\SystemFiles"` without null check | ⚠️ Fragile | Create `SystemFiles/` explicitly, check `$testFolder` exists, copy contents recursively. |
| **R3.5: SHA-256 Checksum** | Computes hash, writes to release notes | ✅ Compatible, but destructive overwrite | Preserve existing release notes body and emit companion `.sha256` asset. |
| **R3.6: Asset Upload** | `gh release upload $tag $zipPath --clobber` | ✅ Working | Add upload of `.sha256` companion file. |
| **R3.7: Workflow Triggers** | `push` on master + path filter | ⚠️ Missing tags | Add `tags: ['v*']` to support git release tag triggers. |

---

## 5. Proposed Workflow Specification

The complete recommended replacement for `.github/workflows/build-msix.yml`:

```yaml
name: Build and Package MSIX

on:
  workflow_dispatch:
  push:
    branches:
      - master
    tags:
      - 'v*'
    paths:
      - 'FluentFlyoutMSIX/Package.appxmanifest'

permissions:
  contents: write

jobs:
  build:
    runs-on: windows-latest

    strategy:
      matrix:
        configuration: ["GitHub Release", "Release"]

    env:
      SOLUTION_PATH: FluentFlyout.sln
      WAP_PROJECT_PATH: FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj
      CONFIGURATION: ${{ matrix.configuration }}
      PLATFORM: x64

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Setup .NET SDK
        uses: actions/setup-dotnet@v5
        with:
          dotnet-version: 10.0.x

      - name: Setup MSBuild
        uses: microsoft/setup-msbuild@v3

      - name: Configure Signing Certificate
        shell: pwsh
        run: |
          $pfxPath = "$env:RUNNER_TEMP\FluentFlyout_Signing.pfx"
          $pfxPassword = "${{ secrets.MSIX_CERT_PASSWORD }}"
          if ([string]::IsNullOrWhiteSpace($pfxPassword)) {
              $pfxPassword = "FluentFlyoutDevPassword123!"
          }

          $certBase64 = "${{ secrets.MSIX_CERT_BASE64 }}".Trim()
          if (-not [string]::IsNullOrEmpty($certBase64)) {
              Write-Host "Using provided repository secret MSIX_CERT_BASE64..."
              $certBytes = [Convert]::FromBase64String($certBase64)
              [IO.File]::WriteAllBytes($pfxPath, $certBytes)
          } else {
            Write-Host "No MSIX_CERT_BASE64 secret found; generating self-signed development certificate..."
            $secPass = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
            $cert = New-SelfSignedCertificate -Type Custom `
                -Subject "CN=49793F74-1457-4B66-A672-4ED3A640FC76" `
                -KeyUsage DigitalSignature `
                -FriendlyName "FluentFlyout Sideload Cert" `
                -CertStoreLocation "Cert:\CurrentUser\My" `
                -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
            Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPass | Out-Null
          }

          "PFX_PATH=$pfxPath" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
          "PFX_PASSWORD=$pfxPassword" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8

      - name: Restore dependencies
        run: dotnet restore $env:SOLUTION_PATH

      - name: Extract app version
        shell: pwsh
        run: |
          [xml]$manifest = Get-Content 'FluentFlyoutMSIX\Package.appxmanifest'
          $fullVersion = $manifest.Package.Identity.Version
          $version = ($fullVersion -split '\.')[0..2] -join '.'
          "APP_VERSION=$version" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8

      - name: Build & Package (MSIX)
        shell: pwsh
        run: |
          $buildMode = if ($env:CONFIGURATION -eq 'GitHub Release') { 'SideloadOnly' } else { 'StoreUpload' }
          msbuild $env:WAP_PROJECT_PATH `
            /p:Configuration=$env:CONFIGURATION `
            /p:Platform=$env:PLATFORM `
            /p:UapAppxPackageBuildMode=$buildMode `
            /p:AppxPackageDir="$env:GITHUB_WORKSPACE\AppxPackages\\" `
            /p:AppxPackageSigningEnabled=true `
            /p:PackageCertificateKeyFile="$env:PFX_PATH" `
            /p:PackageCertificatePassword="$env:PFX_PASSWORD" `
            /p:GenerateTestArtifacts=true

      - name: Prepare installer structure
        shell: pwsh
        run: |
          $outDir = "$env:GITHUB_WORKSPACE\InstallerOutput"
          $systemFilesDir = Join-Path $outDir "SystemFiles"
          New-Item -ItemType Directory -Path $systemFilesDir -Force | Out-Null

          $testFolder = Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Directory -Recurse |
            Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1

          if (-not $testFolder) {
            Write-Error "No *_Test folder found in AppxPackages. Contents:"
            Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Recurse | Select-Object FullName
            exit 1
          }

          Copy-Item -Path "$($testFolder.FullName)\*" -Destination $systemFilesDir -Recurse -Force
          Copy-Item ".github\build-files\FluentFlyout_Installer.bat" "$outDir\"
          Copy-Item ".github\build-files\README.txt" "$outDir\"

      - name: Upload artifact
        uses: actions/upload-artifact@v7
        with:
          name: FluentFlyout_${{ env.APP_VERSION }}_${{ env.PLATFORM }}_${{ matrix.configuration == 'GitHub Release' && 'Installer' || 'Release' }}
          path: InstallerOutput\

      - name: Publish GitHub Release installer
        if: matrix.configuration == 'GitHub Release'
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $zipName = "FluentFlyout_${{ env.APP_VERSION }}_${{ env.PLATFORM }}_Installer.zip"
          $zipPath = "$env:GITHUB_WORKSPACE\$zipName"
          Remove-Item $zipPath -ErrorAction Ignore
          Compress-Archive -Path "InstallerOutput\*" -DestinationPath $zipPath

          $sha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
          $shaFile = "$zipPath.sha256"
          "$sha  $zipName" | Out-File -FilePath $shaFile -Encoding ascii

          $tag = "v${{ env.APP_VERSION }}"
          $checksumBlock = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"

          $releaseExists = $false
          $existingNotes = ""
          try {
            $viewOutput = gh release view $tag --json body -q .body 2>$null
            if ($LASTEXITCODE -eq 0) {
              $releaseExists = $true
              $existingNotes = $viewOutput
            }
          } catch {
            $releaseExists = $false
          }

          if (-not $releaseExists) {
            gh release create $tag --title "FluentFlyout $tag" --notes $checksumBlock
          } else {
            if ($existingNotes -match 'GitHub Release x64\D*?[0-9a-fA-F]{64}') {
              $updatedNotes = $existingNotes -replace 'GitHub Release x64\D*?[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
            } else {
              $updatedNotes = "$existingNotes`n`n$checksumBlock"
            }
            gh release edit $tag --notes $updatedNotes
          }

          gh release upload $tag $zipPath --clobber
          gh release upload $tag $shaFile --clobber
```
