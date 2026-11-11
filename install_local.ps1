$pfxPath = "E:\Programacion\FluentFlyout\dev_cert.pfx"
$pfxPassword = "FluentFlyoutDevPassword123!"
$secPass = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
$subject = "CN=49793F74-1457-4B66-A672-4ED3A640FC76"

# 1. Create self-signed certificate
Write-Host "Creating self-signed code signing certificate..."
$cert = New-SelfSignedCertificate -Type Custom `
    -Subject $subject `
    -KeyUsage DigitalSignature `
    -FriendlyName "FluentFlyout Local Signing Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")

# 2. Export PFX
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPass | Out-Null

# 3. Add to CurrentUser\TrustedPeople
Write-Host "Importing certificate into Cert:\CurrentUser\TrustedPeople..."
$trustedStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "CurrentUser")
$trustedStore.Open("ReadWrite")
$trustedStore.Add($cert)
$trustedStore.Close()

# 4. Sign the MSIX
$msixPath = "E:\Programacion\FluentFlyout\FluentFlyout_2.16.0_x64.msix"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

Write-Host "Signing MSIX package..."
& $signtool sign /fd SHA256 /a /f $pfxPath /p $pfxPassword $msixPath

# 5. Install the package
Write-Host "Installing MSIX package via Add-AppxPackage..."
Add-AppxPackage -Path $msixPath -ForceApplicationShutdown

Write-Host "Installation completed successfully!"
