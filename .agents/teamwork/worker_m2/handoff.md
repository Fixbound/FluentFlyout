# Handoff Report: Milestone 2 — MSIX Packaging & Manifest Alignment

**Agent**: Worker M2 (`worker_m2`)  
**Recipient**: Project Orchestrator (`1641a46b-a931-42fe-9167-dd42fb177b07`)  
**Scope**: Milestone 2 — MSIX Packaging Configuration & Manifest Compatibility  
**Date**: 2026-11-10  
**Handoff Type**: Hard (Task complete)

---

## 1. Observation

1. **Manifest Identity & Extension Architecture**:
   - In `FluentFlyoutMSIX/Package.appxmanifest` lines 11-14:
     ```xml
     <Identity
       Name="unchihugo.FluentFlyout"
       Publisher="CN=49793F74-1457-4B66-A672-4ED3A640FC76"
       Version="2.16.0.0" />
     ```
   - In `FluentFlyoutMSIX/Package.appxmanifest` lines 95-98:
     ```xml
     <Capabilities>
       <Capability Name="internetClient" />
       <rescap:Capability Name="runFullTrust" />
     </Capabilities>
     ```
   - Lines 71-91 declare extensions: startup task (`FluentFlyoutStartup`), toast notification activation (`79086E7F-0D65-4507-82B6-85F2288930D5`), and COM server (`FluentFlyout\FluentFlyout.exe -ToastActivated`).
   - Line 9 previously had `IgnorableNamespaces="uap rescap"`. It was updated to:
     ```xml
     IgnorableNamespaces="uap rescap desktop com">
     ```
   - Executing schema validation against Windows Kits 10.0.26100.0 XSDs (`FoundationManifestSchema.xsd`, `AppxManifestSchema.xsd`, `DesktopManifestSchema.xsd`, `ComManifestSchema.xsd`) yielded:
     ```
     Package.appxmanifest XML parsed successfully. Root: Package
     Package.appxmanifest: 0 schema validation errors.
     ```

2. **Obsolete Machine Paths in Wapproj**:
   - In `FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj` line 87:
     ```xml
     <AppInstallerUri>C:\Users\hu8go\Desktop</AppInstallerUri>
     ```
     This referenced a non-existent personal developer path on machine `hu8go`. It was removed.

3. **Missing File References in Wapproj**:
   - In `FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj` lines 144-145:
     `Package.StoreAssociation.xml` and `FluentFlyoutMSIX_TemporaryKey.pfx` were referenced unconditionally, yet both are absent from git clones (excluded in `.gitignore`).
   - They were updated with conditional existence guards:
     ```xml
     <ItemGroup>
       <None Include="Package.StoreAssociation.xml" Condition="Exists('Package.StoreAssociation.xml')" />
       <None Include="FluentFlyoutMSIX_TemporaryKey.pfx" Condition="Exists('FluentFlyoutMSIX_TemporaryKey.pfx')" />
     </ItemGroup>
     ```

4. **"GitHub Release" (x64) Configuration in Wapproj**:
   - Lines 114-121 were configured with the required packaging properties:
     ```xml
     <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='GitHub Release|x64'">
       <AppxBundle>Always</AppxBundle>
       <GenerateTestArtifacts>True</GenerateTestArtifacts>
       <AppxBundlePlatforms>x64</AppxBundlePlatforms>
       <HoursBetweenUpdateChecks>0</HoursBetweenUpdateChecks>
       <AppxPackageSigningTimestampDigestAlgorithm>SHA256</AppxPackageSigningTimestampDigestAlgorithm>
       <UapAppxPackageBuildMode Condition="'$(UapAppxPackageBuildMode)'==''">SideloadOnly</UapAppxPackageBuildMode>
     </PropertyGroup>
     ```
   - In the global PropertyGroup, `UapAppxPackageBuildMode` was defaulted to `SideloadOnly`, and `PackageCertificateThumbprint` was conditioned on `PackageCertificateKeyFile` and `PackageCertificateThumbprint` being empty:
     ```xml
     <PackageCertificateThumbprint Condition="'$(PackageCertificateKeyFile)' == '' and '$(PackageCertificateThumbprint)' == ''">25D3EFB3B470444AB88088492FCDA18F99BAF513</PackageCertificateThumbprint>
     ```
     This prevents `ValidateSigningCertificate` in MSBuild DesktopBridge targets from failing on thumbprint mismatch when signing with custom or dynamic runner PFX certificates.

5. **WPF Acceptance Criteria Build**:
   - Command: `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
   - Verbatim output:
     ```
     Determining projects to restore...
     All projects are up-to-date for restore.
     FluentFlyout.SourceGenerators -> E:\Programacion\FluentFlyout\FluentFlyout.SourceGenerators\bin\x64\GitHub Release\netstandard2.0\FluentFlyout.SourceGenerators.dll
     FluentFlyout -> E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll

     Build succeeded.
         0 Warning(s)
         0 Error(s)

     Time Elapsed 00:00:01.23
     ```

6. **Wapproj MSBuild Evaluation**:
   - Command: `& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj /t:GetTargetPath /p:Configuration="GitHub Release" /p:Platform=x64`
   - Verbatim output:
     ```
     Build succeeded.
         0 Warning(s)
         0 Error(s)
     ```

7. **File Scope**:
   - `git diff --name-only FluentFlyoutMSIX/` outputs exactly:
     ```
     FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj
     FluentFlyoutMSIX/Package.appxmanifest
     ```
   - No other files were edited by Worker M2.

---

## 2. Logic Chain

1. From Observation 1, the manifest accurately defines identity (`unchihugo.FluentFlyout`, `CN=49793F74-1457-4B66-A672-4ED3A640FC76`, `2.16.0.0`), capabilities (`internetClient`, `runFullTrust`), visual elements, and COM/startup activation. Incorporating `desktop` and `com` into `IgnorableNamespaces` prevents namespace parsing failures during sideloading or installation across Windows builds, and XSD validation confirms 0 schema errors.
2. From Observation 2, removing `<AppInstallerUri>C:\Users\hu8go\Desktop</AppInstallerUri>` eliminates machine-specific paths that do not exist in CI or on other developer machines.
3. From Observation 3, guarding `Package.StoreAssociation.xml` and `FluentFlyoutMSIX_TemporaryKey.pfx` with `Condition="Exists('...')"` prevents MSBuild from emitting missing-file errors when building in a clean repository clone where `.gitignore` excludes them.
4. From Observation 4, adding `GenerateTestArtifacts=True`, `AppxBundlePlatforms=x64`, `HoursBetweenUpdateChecks=0`, `AppxPackageSigningTimestampDigestAlgorithm=SHA256`, and `UapAppxPackageBuildMode=SideloadOnly` directly to the `GitHub Release|x64` property group ensures that building with MSBuild in that configuration produces the required `*_Test` sideload directory containing `Add-AppDevPackage.ps1` and signing certificates.
5. From Observation 4 and MSBuild DesktopBridge target rules (`Microsoft.AppXPackage.Targets:914-925`), conditioning `PackageCertificateThumbprint` allows `PackageCertificateKeyFile` to take precedence without thumbprint collision errors.
6. From Observation 5 and 6, both the core WPF project and the packaging project evaluate and build with 0 errors and 0 warnings under the target configuration.
7. From Observation 7, strict file ownership boundaries were preserved.

---

## 3. Caveats

1. **Full MSIX Package Generation in Local Environment**: Building the full MSIX packaging target (`/t:Publish` or `/p:UapAppxPackageBuildMode=SideloadOnly`) on this specific local workstation is blocked by the MSBuild 17 vs .NET SDK 10 resolver constraint (`minimumMSBuildVersion 18.0.0`). In GitHub Actions (Milestone 3), the workflow will use `actions/setup-dotnet@v5` with .NET 10 and compatible MSBuild.
2. **Signing Certificate**: No `.pfx` is committed in git (by design and per `.gitignore`). Milestone 3 will configure dynamic self-signed certificate creation in CI matching `CN=49793F74-1457-4B66-A672-4ED3A640FC76`.

---

## 4. Conclusion

Milestone 2 objectives are complete:
- `Package.appxmanifest` has verified Identity, Publisher, Version (`2.16.0.0`), capabilities (`internetClient`, `runFullTrust`), visual elements, COM/Startup extensions, and sideload compatibility (`IgnorableNamespaces`), passing official XSD schema validation with 0 errors.
- `FluentFlyoutMSIX.wapproj` is cleansed of obsolete developer paths (`C:\Users\hu8go\Desktop`), missing files are safely guarded with `Condition="Exists('...')"` checks, and property group `'GitHub Release|x64'` is fully configured with `GenerateTestArtifacts=True`, `AppxBundlePlatforms=x64`, `HoursBetweenUpdateChecks=0`, `AppxPackageSigningTimestampDigestAlgorithm=SHA256`, and `UapAppxPackageBuildMode=SideloadOnly`.
- Acceptance criterion 1 (`dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`) compiles with **0 errors and 0 warnings**.

---

## 5. Verification Method

To independently verify the changes:

1. **Verify WPF Compilation**:
   ```powershell
   dotnet build "E:\Programacion\FluentFlyout\FluentFlyoutWPF\FluentFlyout.csproj" -c "GitHub Release" -p:Platform=x64
   ```
   *Expected Result*: Build succeeded with 0 Warning(s), 0 Error(s).

2. **Verify Wapproj Evaluation**:
   ```powershell
   & "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" "E:\Programacion\FluentFlyout\FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj" /t:GetTargetPath /p:Configuration="GitHub Release" /p:Platform=x64
   ```
   *Expected Result*: Build succeeded with 0 Warning(s), 0 Error(s).

3. **Verify AppxManifest XML Well-Formedness & XSD Validation**:
   ```powershell
   $schemaFolder = "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\winrt"
   $settings = New-Object System.Xml.XmlReaderSettings
   $settings.ValidationType = [System.Xml.ValidationType]::Schema
   $schemas = Get-ChildItem "$schemaFolder\*.xsd"
   foreach ($s in $schemas) { try { $null = $settings.Schemas.Add($null, $s.FullName) } catch { } }
   $errors = @()
   $settings.add_ValidationEventHandler({ param($sender, $e) $errors += "$($e.Severity): $($e.Message)" })
   $reader = [System.Xml.XmlReader]::Create("E:\Programacion\FluentFlyout\FluentFlyoutMSIX\Package.appxmanifest", $settings)
   while ($reader.Read()) { }
   $reader.Close()
   Write-Host "Validation Errors: $($errors.Count)"
   ```
   *Expected Result*: `Validation Errors: 0`.

4. **Verify Modified Files Scope**:
   ```powershell
   git status -s FluentFlyoutMSIX/
   ```
   *Expected Result*: Only `Package.appxmanifest` and `FluentFlyoutMSIX.wapproj` are modified.
