$env:RUNNER_TEMP = [System.IO.Path]::GetTempPath()
$env:CERT_BASE64 = ""
$env:CERT_PASSWORD = ""

$pfxPath = Join-Path $env:RUNNER_TEMP "FluentFlyout_Signing_Test.pfx"
$pfxPassword = $env:CERT_PASSWORD
if ([string]::IsNullOrWhiteSpace($pfxPassword)) {
    $pfxPassword = "FluentFlyoutDevPassword123!"
}

$rawBase64 = if ($null -ne $env:CERT_BASE64) { $env:CERT_BASE64.Trim() } else { "" }

if (-not [string]::IsNullOrWhiteSpace($rawBase64)) {
    Write-Host "Using provided repository secret MSIX_CERT_BASE64..."
    $certBytes = [Convert]::FromBase64String($rawBase64)
    [IO.File]::WriteAllBytes($pfxPath, $certBytes)
} else {
    Write-Host "No MSIX_CERT_BASE64 secret found; generating dynamic self-signed certificate..."
    $secPass = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
    $cert = New-SelfSignedCertificate -Type Custom `
        -Subject "CN=49793F74-1457-4B66-A672-4ED3A640FC76" `
        -KeyUsage DigitalSignature `
        -FriendlyName "FluentFlyout Sideload Cert" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPass | Out-Null
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
}

Write-Host "PFX exists: $(Test-Path $pfxPath)"
Write-Host "PFX length: $((Get-Item $pfxPath).Length)"
Remove-Item $pfxPath -Force
