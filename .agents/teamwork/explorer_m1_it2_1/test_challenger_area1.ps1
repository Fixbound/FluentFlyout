$ErrorActionPreference = "Stop"

$bt = [char]96
$sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
$sampleHashUpper = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

$c5_workflow = [regex]'(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_x64      = [regex]'(?im)^[^\r\n]*?\bx64\b[^\r\n]*?(?:checksum|sha-?256|hash|digest|[|:])[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_fallback = [regex]'(?im)^[^\r\n]*?\b(?:sha-?256|checksum)\b[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_generic  = [regex]'\b([0-9a-fA-F]{64})\b'

function Parse-Body ([string]$bodyText) {
    if ([string]::IsNullOrWhiteSpace($bodyText)) { return "" }
    $m = $c5_workflow.Match($bodyText)
    if (-not $m.Success) { $m = $c5_x64.Match($bodyText) }
    if (-not $m.Success) { $m = $c5_fallback.Match($bodyText) }
    if (-not $m.Success) { $m = $c5_generic.Match($bodyText) }
    if ($m.Success -and $m.Groups.Count -gt 1) {
        return $m.Groups[1].Value.Trim().ToLowerInvariant()
    }
    return ""
}

$harnessCases = @(
    @{ Name = "R1.1 Standard workflow format"; Body = "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.2 Uppercase hex hash"; Body = "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: $sampleHashUpper"; Expected = $sampleHash },
    @{ Name = "R1.3 Alternative sha256 keyword"; Body = "GitHub Release x64 sha256: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.4 Short header SHA-256"; Body = "SHA-256: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.5 Short header sha256"; Body = "sha256: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.6 Generic prefix checksum"; Body = "checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.7 Space separated, no colon"; Body = "sha256 $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.8 Noisy body with 40-char git commit SHA"; Body = "## Release notes`n* Commit 4f2c99a8b13c77d01234567890abcdef12345678`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.9 Markdown bold header"; Body = "**Checksum:** $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.10 Backtick-wrapped hash"; Body = "checksum: $bt$sampleHash$bt"; Expected = $sampleHash },
    @{ Name = "R1.11 Multi-arch collision (ARM64 before x64)"; Body = "## Downloads`nARM64 checksum: 1111111111111111111111111111111111111111111111111111111111111111`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.12 Previous release hash mentioned"; Body = "Previous release checksum was 3333333333333333333333333333333333333333333333333333333333333333`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "R1.13 Malformed hash: 63 hex"; Body = "GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85"; Expected = "" },
    @{ Name = "R1.14 Malformed hash: 65 hex"; Body = "GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"; Expected = "" },
    @{ Name = "R1.15 Non-hex chars in 64-char string"; Body = "GitHub Release x64 checksum: g3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"; Expected = "" },
    @{ Name = "R1.16 No checksum present in notes"; Body = "Bug fixes and improvements"; Expected = "" },
    @{ Name = "R1.17 Empty body"; Body = ""; Expected = "" }
)

Write-Host "=== AREA 1 CHALLENGER 1 TESTS WITH CANDIDATE 5 ===" -ForegroundColor Cyan
$p = 0
$f = 0
foreach ($t in $harnessCases) {
    $act = Parse-Body $t.Body
    if ($act -eq $t.Expected) {
        $p++
        Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
    } else {
        $f++
        Write-Host "[FAIL] $($t.Name): Expected='$($t.Expected)' Actual='$act'" -ForegroundColor Red
    }
}
Write-Host "Area 1 Summary: Passed=$p, Failed=$f (Total $($harnessCases.Count))"
