# Reviewer M3.1 Adversarial Test Suite

$ErrorActionPreference = "Stop"

Write-Host "=== TEST 1: App Version Extraction ==="
[xml]$manifest = Get-Content "E:\Programacion\FluentFlyout\FluentFlyoutMSIX\Package.appxmanifest"
$fullVersion = $manifest.Package.Identity.Version
$version = ($fullVersion -split '\.')[0..2] -join '.'
Write-Host "Full Version: $fullVersion"
Write-Host "Extracted 3-part Version: $version"
if (-not ($version -match '^\d+\.\d+\.\d+$')) {
    throw "Version extraction failed: $version"
}

Write-Host "`n=== TEST 2: Signing Certificate Generation & Publisher Match ==="
$publisherInManifest = $manifest.Package.Identity.Publisher
Write-Host "Manifest Publisher: $publisherInManifest"

$tempPfx = Join-Path ([System.IO.Path]::GetTempPath()) "Reviewer_Cert_Test.pfx"
$testPass = "FluentFlyoutDevPassword123!"
$secPass = ConvertTo-SecureString -String $testPass -Force -AsPlainText

$cert = New-SelfSignedCertificate -Type Custom `
    -Subject $publisherInManifest `
    -KeyUsage DigitalSignature `
    -FriendlyName "FluentFlyout Review Test Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")

Export-PfxCertificate -Cert $cert -FilePath $tempPfx -Password $secPass | Out-Null
Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue

$certFromFile = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($tempPfx, $testPass)
Write-Host "Exported PFX Subject: $($certFromFile.Subject)"
if ($certFromFile.Subject -ne $publisherInManifest) {
    throw "Cert subject '$($certFromFile.Subject)' does not match manifest publisher '$publisherInManifest'"
}
Remove-Item $tempPfx -Force

Write-Host "`n=== TEST 3: Staged Installer Structure & Build Files ==="
$batPath = "E:\Programacion\FluentFlyout\.github\build-files\FluentFlyout_Installer.bat"
$readmePath = "E:\Programacion\FluentFlyout\.github\build-files\README.txt"

if (-not (Test-Path $batPath)) { throw "FluentFlyout_Installer.bat missing from .github/build-files" }
if (-not (Test-Path $readmePath)) { throw "README.txt missing from .github/build-files" }

$batContent = Get-Content $batPath -Raw
Write-Host "Checking FluentFlyout_Installer.bat content..."
if (-not ($batContent -match 'Add-AppDevPackage\.ps1')) {
    throw "FluentFlyout_Installer.bat does not invoke Add-AppDevPackage.ps1"
}
if (-not ($batContent -match 'cd /d "%~dp0SystemFiles"')) {
    throw "FluentFlyout_Installer.bat does not change directory to SystemFiles"
}

Write-Host "`n=== TEST 4: Release Notes Regex Replacement Stress Testing ==="
$testSha1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$testSha2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
$zipName = "FluentFlyout_${version}_x64_Installer.zip"
$checksumBlock = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $testSha2"

# Scenario A: Brand new release (no prior notes)
$updatedA = $checksumBlock
Write-Host "Scenario A (new release):`n$updatedA"

# Scenario B: Existing release with standard checksum block replacement
$existingNotesB = "Initial release notes for v$version`n`nGitHub Release x64 installer: old_name.zip`nGitHub Release x64 checksum: $testSha1"
if ($existingNotesB -match 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}') {
    $updatedB = $existingNotesB -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $testSha2"
    if ($updatedB -match 'GitHub Release x64 installer:\s*\S+') {
        $updatedB = $updatedB -replace 'GitHub Release x64 installer:\s*\S+', "GitHub Release x64 installer: $zipName"
    }
}
Write-Host "`nScenario B (replacement):`n$updatedB"
if (-not ($updatedB -match "GitHub Release x64 checksum: $testSha2")) {
    throw "Scenario B failed to replace checksum"
}
if (-not ($updatedB -match "GitHub Release x64 installer: $zipName")) {
    throw "Scenario B failed to replace installer name"
}

# Scenario C: Existing release without checksum block (append)
$existingNotesC = "Release notes without any checksum block yet."
$updatedC = if ([string]::IsNullOrWhiteSpace($existingNotesC)) {
    $checksumBlock
} else {
    "$existingNotesC`n`n$checksumBlock"
}
Write-Host "`nScenario C (append):`n$updatedC"
if (-not ($updatedC -match "GitHub Release x64 checksum: $testSha2")) {
    throw "Scenario C failed to append checksum"
}

Write-Host "`n=== TEST 5: Interoperability with UpdateCheckerService ==="
$dllPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"
$asm = [System.Reflection.Assembly]::LoadFrom($dllPath)
$type = $asm.GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService")
$method = $type.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public,NonPublic,Static")

foreach ($scenario in @(@{Name="A"; Body=$updatedA}, @{Name="B"; Body=$updatedB}, @{Name="C"; Body=$updatedC})) {
    $json = @"
{
  "tag_name": "v$version",
  "body": "$($scenario.Body -replace "`n", "\n" -replace "`r", "")",
  "assets": [
    {
      "name": "$zipName",
      "browser_download_url": "https://github.com/unchihugo/FluentFlyout/releases/download/v$version/$zipName"
    }
  ]
}
"@
    $doc = [System.Text.Json.JsonDocument]::Parse($json)
    $parseResult = $method.Invoke($null, @($doc))
    Write-Host "Scenario $($scenario.Name): AssetUrl=$($parseResult.Item1), SHA=$($parseResult.Item2)"
    if ($parseResult.Item2 -ne $testSha2) {
        throw "Scenario $($scenario.Name) failed SHA extraction. Expected $testSha2, got $($parseResult.Item2)"
    }
}

Write-Host "`n=== ALL ADVERSARIAL STRESS TESTS PASSED SUCCESSFULLY! ==="
