$pfxPath = "E:\Programacion\FluentFlyout\dev_cert.pfx"
$pfxPassword = "FluentFlyoutDevPassword123!"
$secPass = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
$subject = "CN=49793F74-1457-4B66-A672-4ED3A640FC76"

Write-Host "Generating self-signed certificate with BasicConstraints and CodeSigning EKU..."
$cert = New-SelfSignedCertificate -Type Custom `
    -Subject $subject `
    -KeyUsage DigitalSignature `
    -FriendlyName "FluentFlyout Sideload Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

# Verify extensions
$hasBasic = ($cert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.19" }) -ne $null
$hasEku = ($cert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }) -ne $null
Write-Host "BasicConstraints present: $hasBasic, EKU present: $hasEku"

# Export PFX and CER
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPass | Out-Null

$outDir = "E:\Programacion\FluentFlyout\InstallerOutput\SystemFiles"
$cerPath = Join-Path $outDir "FluentFlyout_2.16.0.0_x64.cer"
[System.IO.File]::WriteAllBytes($cerPath, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

# Sign MSIX
$msixPath = Join-Path $outDir "FluentFlyout_2.16.0.0_x64.msix"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

Write-Host "Re-signing MSIX with compliant certificate..."
& $signtool sign /fd SHA256 /a /f $pfxPath /p $pfxPassword $msixPath

# Also unblock all files
Get-ChildItem -Path "E:\Programacion\FluentFlyout\InstallerOutput" -Recurse | Unblock-File

Write-Host "Certificate and MSIX updated successfully!"
