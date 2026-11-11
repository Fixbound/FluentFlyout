# Adversarial Stress Testing Script for Auditor M3
$ErrorActionPreference = "Stop"

Write-Host "=== Stress Test 1: Markdown with regex special characters and emojis ==="
$specialNotes = @'
# Release 🎉 v2.16.0-beta [PRO]
Special chars: $100, \n \t, *asterisk*, [link](https://test.com)
GitHub Release x64 installer: old_app.zip
GitHub Release x64 checksum: 1111111111111111111111111111111111111111111111111111111111111111

Note: Do not delete $HOME
'@

$newZip = "FluentFlyout_2.16.0_x64_Installer.zip"
$newSha = "2222222222222222222222222222222222222222222222222222222222222222"

$updatedNotes = $specialNotes
if ($updatedNotes -match 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}') {
    $updatedNotes = $updatedNotes -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $newSha"
    if ($updatedNotes -match 'GitHub Release x64 installer:\s*\S+') {
        $updatedNotes = $updatedNotes -replace 'GitHub Release x64 installer:\s*\S+', "GitHub Release x64 installer: $newZip"
    }
}

if (-not $updatedNotes.Contains($newSha)) {
    throw "Stress Test 1 Failed: New SHA not inserted"
}
if (-not $updatedNotes.Contains($newZip)) {
    throw "Stress Test 1 Failed: New Zip not inserted"
}
if (-not $updatedNotes.Contains('$100')) {
    throw "Stress Test 1 Failed: Special char $100 was corrupted"
}
if (-not $updatedNotes.Contains('🎉')) {
    throw "Stress Test 1 Failed: Emoji was corrupted"
}
Write-Host "Stress Test 1 Passed: Special characters and emojis preserved properly."

Write-Host "`n=== Stress Test 2: Whitespace and newline variations in CERT_BASE64 ==="
$raw = "   " + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("TestCertBytes")) + " `r`n  "
$cleaned = if ($null -ne $raw) { $raw.Trim() } else { "" }
$bytes = [Convert]::FromBase64String($cleaned)
$roundtrip = [System.Text.Encoding]::UTF8.GetString($bytes)
if ($roundtrip -ne "TestCertBytes") {
    throw "Stress Test 2 Failed: Base64 decode failed after whitespace trim"
}
Write-Host "Stress Test 2 Passed: Whitespace padding handled cleanly."

Write-Host "`n=== Stress Test 3: Missing Test Folder Trapping ==="
$tempEmpty = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempEmpty | Out-Null
try {
    $testFolder = Get-ChildItem $tempEmpty -Directory -Recurse |
        Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1
    if (-not $testFolder) {
        $trapped = $true
    } else {
        $trapped = $false
    }
    if (-not $trapped) {
        throw "Stress Test 3 Failed: Trapping failed"
    }
    Write-Host "Stress Test 3 Passed: Missing test folder correctly identified as fatal error condition."
} finally {
    Remove-Item $tempEmpty -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== ALL STRESS TESTS PASSED ==="
