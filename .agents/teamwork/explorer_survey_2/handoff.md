# Handoff Report: MSIX Packaging, Wapproj, Manifest & Local Build Compatibility

**Agent**: Explorer Survey 2  
**Recipient**: Project Orchestrator (`1641a46b-a931-42fe-9167-dd42fb177b07`)  
**Scope**: Requirements R4, R2 package integration, and Build/Packaging Acceptance Criteria  
**Date**: 2026-11-10  
**Handoff Type**: Hard (Investigation complete)

---

## 1. Observation

1. **WPF Acceptance Criteria Build**:
   - Command: `dotnet build "E:\Programacion\FluentFlyout\FluentFlyoutWPF\FluentFlyout.csproj" -c "GitHub Release" -p:Platform=x64`
   - Output:
     ```
       Determining projects to restore...
       All projects are up-to-date for restore.
       FluentFlyout.SourceGenerators -> E:\Programacion\FluentFlyout\FluentFlyout.SourceGenerators\bin\x64\GitHub Release\netstandard2.0\FluentFlyout.SourceGenerators.dll
       FluentFlyout -> E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll

     Build succeeded.
         0 Warning(s)
         0 Error(s)

     Time Elapsed 00:00:01.32
     ```
   - Confirms that acceptance criterion 1 (`dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`) passes with 0 errors and 0 warnings.

2. **Configuration & Symbol Definition**:
   - In `FluentFlyoutWPF/FluentFlyout.csproj` lines 20-22:
     ```xml
     <PropertyGroup Condition="'$(Configuration)' == 'GitHub Release'">
       <DefineConstants>GITHUB_RELEASE</DefineConstants>
     </PropertyGroup>
     ```
   - In `FluentFlyoutWPF/Classes/LicenseManager.cs` lines 87-92:
     ```csharp
     #if GITHUB_RELEASE
                 _isStoreVersion = false;
                 _isPremiumUnlocked = true;
                 _isInitialized = true;
                 return;
     #endif
     ```
   - In `FluentFlyout.sln` lines 47-48 & 85-87:
     `{A3576152-7AF6-4136-992A-1B3C1091652A}.GitHub Release|x64.ActiveCfg = GitHub Release|x64`
     `{7C7CB0B2-26B9-4B8B-B5E8-30ABF5E2B331}.GitHub Release|x64.ActiveCfg = GitHub Release|x64`

3. **Package Manifest Identity & Capabilities**:
   - In `FluentFlyoutMSIX/Package.appxmanifest` lines 11-14:
     ```xml
     <Identity
       Name="unchihugo.FluentFlyout"
       Publisher="CN=49793F74-1457-4B66-A672-4ED3A640FC76"
       Version="2.16.0.0" />
     ```
   - Lines 95-98:
     ```xml
     <Capabilities>
       <Capability Name="internetClient" />
       <rescap:Capability Name="runFullTrust" />
     </Capabilities>
     ```
   - Startup task extension in line 72-77: `TaskId="FluentFlyoutStartup"`.
   - Toast & COM activation extensions in lines 79-90: `ToastActivatorCLSID="79086E7F-0D65-4507-82B6-85F2288930D5"`, COM server `FluentFlyout\FluentFlyout.exe -ToastActivated`.

4. **WAP Project Settings and Certificate Configuration**:
   - In `FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj` lines 74-92:
     `<TargetPlatformVersion>10.0.26100.0</TargetPlatformVersion>`
     `<TargetPlatformMinVersion>10.0.19041.0</TargetPlatformMinVersion>`
     `<AppxPackageSigningEnabled>True</AppxPackageSigningEnabled>`
     `<GenerateTestArtifacts>True</GenerateTestArtifacts>`
     `<AppxBundlePlatforms>x64</AppxBundlePlatforms>`
     `<PackageCertificateThumbprint>25D3EFB3B470444AB88088492FCDA18F99BAF513</PackageCertificateThumbprint>`
   - On filesystem: `FluentFlyoutMSIX_TemporaryKey.pfx` and `Package.StoreAssociation.xml` are not present on disk, and `.gitignore` ignores `*.pfx` (line 239) and `Package.StoreAssociation.xml` (line 220).
   - In local certificate store: `Get-ChildItem -Recurse Cert:\ | Where-Object { $_.Thumbprint -eq "25D3EFB3B470444AB88088492FCDA18F99BAF513" }` returns empty.

5. **`Add-AppDevPackage.ps1` Origin and Layout**:
   - Located on disk at `C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Microsoft\VisualStudio\v17.0\AppxPackage\Add-AppDevPackage.ps1`.
   - Accompanied by subfolder `Add-AppDevPackage.resources\` (required by `Import-LocalizedData` in line 56).
   - Generated automatically by MSBuild into `AppxPackages\FluentFlyoutMSIX_<version>_Test\` when `GenerateTestArtifacts=true` and `UapAppxPackageBuildMode=SideloadOnly`.

6. **Flaws in `.github/workflows/build-msix.yml`**:
   - Line 37-38 decodes certificate secret:
     ```powershell
     $cert = [Convert]::FromBase64String("${{ secrets.MSIX_CERT_BASE64 }}")
     [IO.File]::WriteAllBytes("$env:RUNNER_TEMP\cert.pfx", $cert)
     ```
   - Lines 51-57 invoke MSBuild:
     ```powershell
     msbuild $env:WAP_PROJECT_PATH `
       /p:Configuration=$env:CONFIGURATION `
       /p:Platform=$env:PLATFORM `
       /p:UapAppxPackageBuildMode=StoreUpload `
       /p:AppxPackageDir="$env:GITHUB_WORKSPACE\AppxPackages\\" `
       /p:AppxPackageSigningEnabled=false `
     ```
   - Lines 63-65 expect `*_Test` folder:
     ```powershell
     $testFolder = Get-ChildItem "$env:GITHUB_WORKSPACE\AppxPackages" -Directory |
       Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1
     Move-Item $testFolder.FullName "$outDir\SystemFiles"
     ```
   - Verbatim consequence: `UapAppxPackageBuildMode=StoreUpload` builds Store packages (`.appxupload`) and **never** creates `*_Test`. Thus `$testFolder` is `$null`, causing `Move-Item` to throw `Cannot bind argument to parameter 'Path' because it is null`. Furthermore, `/p:AppxPackageSigningEnabled=false` produces an unsigned package that Windows refuses to sideload.

7. **Flaws in `UpdateInstallerService.cs` Integration**:
   - Lines 145-162 in `UpdateInstallerService.cs`:
     ```csharp
     var extractDir = Path.Join(runDir, "files");
     var zipPath = Path.Join(runDir, "update.zip");
     var installerScript = Path.Join(extractDir, "SystemFiles\\Add-AppDevPackage.ps1");
     var applyScript = Path.Join(runDir, "apply.ps1");

     var scriptBody =
         "Expand-Archive -LiteralPath " + Quote(zipPath) + " -DestinationPath " + Quote(extractDir) + "\r\n" +
         "& " + Quote(installerScript) + "\r\n";

     File.WriteAllText(applyScript, scriptBody);
     _ = Process.Start("powershell.exe", "-NoProfile -File \"" + applyScript + "\"");
     Application.Current.Shutdown();
     ```
   - `powershell.exe` is launched without `-ExecutionPolicy Bypass`.
   - No redirection or log capture is performed.
   - `Add-AppDevPackage.ps1` does not relaunch `FluentFlyout.exe`. Once the app shuts down, the user is not returned to the app.
   - `RunAndWait` blocks synchronously with `process.WaitForExit()`, freezing the WPF UI thread during download and hash check.

8. **Toolchain Version Dependency**:
   - `C:\Program Files\dotnet\sdk\10.0.401\minimumMSBuildVersion` contains `18.0.0`.
   - Visual Studio 2022 Community on this machine is MSBuild 17.14 (`17.14.60.43110`).
   - Running `MSBuild.exe` (17.14) against `FluentFlyoutMSIX.wapproj` yields:
     `error : Version 10.0.401 of the .NET SDK requires at least version 18.0.0 of MSBuild. The current available version of MSBuild is 17.14.60.43110.`
   - Conversely, `dotnet build` executes MSBuild 18 bundled in the .NET 10 SDK (`MSBuild version: 18.9.11+e34a38d2a`), successfully building `FluentFlyoutWPF/FluentFlyout.csproj`.

---

## 2. Logic Chain

1. From Observation 1, `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64` compiles with 0 errors and 0 warnings, verifying acceptance criterion 1.
2. From Observation 2, the preprocessor symbol `GITHUB_RELEASE` directly activates the premium bypass branch in `LicenseManager.cs`, satisfying the requirement that GitHub release packages have premium unlocked.
3. From Observation 3 and 4, Windows App Model requires the Subject of the code signing certificate to match `<Identity Publisher="CN=49793F74-1457-4B66-A672-4ED3A640FC76" />` exactly. Unsigned packages or mismatched publishers fail validation upon install.
4. From Observation 5 and 6, `Add-AppDevPackage.ps1` is produced only when `UapAppxPackageBuildMode=SideloadOnly` (or `SideLoadOnly`) and `GenerateTestArtifacts=true`. Setting `UapAppxPackageBuildMode=StoreUpload` and `AppxPackageSigningEnabled=false` in `.github/workflows/build-msix.yml` prevents `*_Test` from being created, breaking the workflow at the `Move-Item` step and outputting an unsigned, unusable package.
5. From Observation 6 and 7, the installer zip `FluentFlyout_<version>_x64_Installer.zip` is expected by `UpdateInstallerService.cs` to have `SystemFiles\Add-AppDevPackage.ps1`. When the CI packaging mode is corrected to `SideloadOnly` with signing enabled, the resulting zip matches this exact directory layout.
6. From Observation 7, `UpdateInstallerService.ApplyRun` spawns `powershell.exe -NoProfile -File apply.ps1`. Without `-ExecutionPolicy Bypass`, execution fails under standard Windows policy restrictions; without output redirection, all failure diagnostics are lost; without relaunching the binary, the user experience is broken.
7. From Observation 8, building `FluentFlyoutMSIX.wapproj` requires full MSBuild (DesktopBridge targets). Because the project targets .NET 10, the build environment must use MSBuild 18+ (bundled with .NET 10 / Visual Studio 2026/preview) or pre-publish the WPF app, to avoid the SDK resolver version gate.

---

## 3. Caveats

1. **Local Full Packaging Execution**: Building `FluentFlyoutMSIX.wapproj` end-to-end on this specific local workstation is currently restricted by the version gate between MSBuild 17.14 and .NET SDK 10 (`minimumMSBuildVersion 18.0.0`). In GitHub Actions, the runner image environment must be configured with compatible MSBuild and .NET 10 toolchains.
2. **Missing Test PFX in Repository**: Because `.gitignore` excludes `*.pfx`, no committed test certificate exists in the repo. A local build or CI step without secrets must dynamically generate a temporary self-signed certificate matching `CN=49793F74-1457-4B66-A672-4ED3A640FC76`.
3. **Admin Rights for First-Time Installation**: `Add-AppDevPackage.ps1` requires elevation if the self-signed certificate is not already present in `Cert:\LocalMachine\TrustedPeople`. Subsequent updates signed with the same certificate do not require certificate re-installation.

---

## 4. Conclusion

1. Requirement **R4** (MSIX packaging and installation compatibility) is fully mapped:
   - Manifest identity (`unchihugo.FluentFlyout`, `CN=49793F74-1457-4B66-A672-4ED3A640FC76`, `2.16.0.0`) and capabilities (`internetClient`, `runFullTrust`) are correctly defined.
   - The primary blocker in CI is `.github/workflows/build-msix.yml`: it uses `/p:UapAppxPackageBuildMode=StoreUpload` instead of `SideloadOnly`, disables signing (`/p:AppxPackageSigningEnabled=false`), and discards the decoded PFX.
2. Requirement **R2** (package integration with auto-updater) requires specific fixes in `UpdateInstallerService.cs`:
   - Non-blocking asynchronous download and hashing using `System.Security.Cryptography.SHA256`.
   - Generating `apply.ps1` with `-ExecutionPolicy Bypass`, `-SkipLoggingTelemetry`, stdout/stderr logging to `update_install.log`, and an app relaunch step via `shell:AppsFolder` / `Get-AppxPackage`.
3. Acceptance Criterion 1 (`dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`) is confirmed passing with **0 errors, 0 warnings**.

---

## 5. Verification Method

To independently verify the observations and conclusions:

1. **Verify WPF GitHub Release Compilation**:
   ```powershell
   dotnet build "E:\Programacion\FluentFlyout\FluentFlyoutWPF\FluentFlyout.csproj" -c "GitHub Release" -p:Platform=x64
   ```
   *Expected Result*: Build succeeded, 0 Warning(s), 0 Error(s).

2. **Verify License Premium Unlock Constant**:
   Inspect `FluentFlyoutWPF\Classes\LicenseManager.cs` lines 87-92.
   *Expected Result*: Confirms `#if GITHUB_RELEASE` sets `_isPremiumUnlocked = true`.

3. **Verify App Manifest Identity and Capabilities**:
   Inspect `FluentFlyoutMSIX\Package.appxmanifest` lines 11-14 and 95-98.
   *Expected Result*: Identity publisher is `CN=49793F74-1457-4B66-A672-4ED3A640FC76`, capabilities include `internetClient` and `runFullTrust`.

4. **Verify CI Workflow Defect**:
   Inspect `.github/workflows/build-msix.yml` lines 55, 57, and 63-65.
   *Expected Result*: Confirms `/p:UapAppxPackageBuildMode=StoreUpload`, `/p:AppxPackageSigningEnabled=false`, and dependency on `$testFolder` matching `*_Test`.

5. **Verify UpdateInstaller Expected Layout**:
   Inspect `FluentFlyoutWPF\Classes\Services\UpdateInstallerService.cs` line 147.
   *Expected Result*: Confirms path `SystemFiles\Add-AppDevPackage.ps1`.
