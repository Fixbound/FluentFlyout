$regex = [regex]::new('(?i)(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})')
$fallback = [regex]::new('\b([0-9a-fA-F]{64})\b')

$testCases = @(
    "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: 1111111111111111111111111111111111111111111111111111111111111111",
    "GitHub Release x64 sha256: 2222222222222222222222222222222222222222222222222222222222222222",
    "SHA256: 3333333333333333333333333333333333333333333333333333333333333333",
    "SHA-256: 4444444444444444444444444444444444444444444444444444444444444444",
    "checksum: 5555555555555555555555555555555555555555555555555555555555555555",
    "Some notes without prefix: 6666666666666666666666666666666666666666666666666666666666666666",
    "Commit sha: 1234567890abcdef1234567890abcdef12345678",
    ""
)

foreach ($tc in $testCases) {
    $m = $regex.Match($tc)
    if ($m.Success) {
        Write-Output ("MATCH primary: " + $m.Groups[1].Value)
    } else {
        $m2 = $fallback.Match($tc)
        if ($m2.Success) {
            Write-Output ("MATCH fallback: " + $m2.Groups[1].Value)
        } else {
            Write-Output "NO MATCH"
        }
    }
}
