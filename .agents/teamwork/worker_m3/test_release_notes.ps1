$zipName = "FluentFlyout_2.16.0_x64_Installer.zip"
$sha = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
$checksumBlock = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"

# Case 1: Fresh notes (empty existing notes)
$existingNotes1 = ""
$updated1 = if ([string]::IsNullOrWhiteSpace($existingNotes1)) { $checksumBlock } else { "$existingNotes1`n`n$checksumBlock" }
Write-Host "Case 1 matches Sha256WorkflowRegex: $($updated1 -match '(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b')"
Write-Host "Case 1 matches survey regex: $($updated1 -match 'GitHub Release x64\D*?([0-9a-fA-F]{64})')"

# Case 2: Existing release with custom changelog and previous checksum
$existingNotes2 = @"
## Changelog
- Added smooth animations
- Fixed volume slider

GitHub Release x64 installer: FluentFlyout_2.15.0_x64_Installer.zip
GitHub Release x64 checksum: 0000000000000000000000000000000000000000000000000000000000000000
"@

$updated2 = $existingNotes2
if ($updated2 -match 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}') {
    $updated2 = $updated2 -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
    if ($updated2 -match 'GitHub Release x64 installer:\s*\S+') {
        $updated2 = $updated2 -replace 'GitHub Release x64 installer:\s*\S+', "GitHub Release x64 installer: $zipName"
    }
} elseif ($updated2 -match 'GitHub Release x64\D*?[0-9a-fA-F]{64}') {
    $updated2 = $updated2 -replace 'GitHub Release x64\D*?[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
} else {
    $updated2 = "$updated2`n`n$checksumBlock"
}

Write-Host "Case 2 preserved changelog: $($updated2.StartsWith("## Changelog"))"
Write-Host "Case 2 updated zip: $($updated2.Contains($zipName))"
Write-Host "Case 2 updated sha: $($updated2.Contains($sha))"
Write-Host "Case 2 matches Sha256WorkflowRegex: $($updated2 -match '(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b')"
Write-Host "Case 2 matches survey regex: $($updated2 -match 'GitHub Release x64\D*?([0-9a-fA-F]{64})')"

# Case 3: Existing release with changelog but NO previous checksum
$existingNotes3 = @"
## Changelog
- New release
"@

$updated3 = $existingNotes3
if ($updated3 -match 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}') {
    $updated3 = $updated3 -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
} elseif ($updated3 -match 'GitHub Release x64\D*?[0-9a-fA-F]{64}') {
    $updated3 = $updated3 -replace 'GitHub Release x64\D*?[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $sha"
} else {
    $updated3 = "$updated3`n`n$checksumBlock"
}

Write-Host "Case 3 preserved changelog: $($updated3.StartsWith("## Changelog"))"
Write-Host "Case 3 appended checksum block: $($updated3.Contains($checksumBlock))"
Write-Host "Case 3 matches Sha256WorkflowRegex: $($updated3 -match '(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b')"
