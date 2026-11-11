$ErrorActionPreference = "Stop"

$bt = [char]96
$sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
$armHash    = "1111111111111111111111111111111111111111111111111111111111111111"

$testCases = @(
    @{ Name = "Standard"; Text = "GitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "Uppercase"; Text = "GitHub Release x64 checksum: " + $sampleHash.ToUpper(); Expected = $sampleHash },
    @{ Name = "Backtick x64"; Text = "GitHub Release x64 checksum: $bt$sampleHash$bt"; Expected = $sampleHash },
    @{ Name = "Bold Markdown"; Text = "**GitHub Release x64 checksum:** $sampleHash"; Expected = $sampleHash },
    @{ Name = "Bold and Backtick"; Text = "**GitHub Release x64 checksum:** $bt$sampleHash$bt"; Expected = $sampleHash },
    @{ Name = "Header SHA-256"; Text = "SHA-256: $sampleHash"; Expected = $sampleHash },
    @{ Name = "Generic checksum:"; Text = "checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "Space separated"; Text = "sha256 $sampleHash"; Expected = $sampleHash },
    @{ Name = "Noisy commit before"; Text = "Commit 4f2c99a8b13c77d01234567890abcdef12345678`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "ARM64 before x64 plain"; Text = "ARM64 checksum: $armHash`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "ARM64 before x64 backtick"; Text = "ARM64 checksum: $bt$armHash$bt`nGitHub Release x64 checksum: $bt$sampleHash$bt"; Expected = $sampleHash },
    @{ Name = "ARM64 before x64 bold"; Text = "**ARM64 checksum:** $armHash`n**GitHub Release x64 checksum:** $sampleHash"; Expected = $sampleHash },
    @{ Name = "Table format"; Text = "| Arch | SHA-256 |`n|---|---|`n| arm64 | $bt$armHash$bt |`n| x64 | $bt$sampleHash$bt |"; Expected = $sampleHash },
    @{ Name = "65-char hex"; Text = "GitHub Release x64 checksum: ${sampleHash}a"; Expected = "" },
    @{ Name = "63-char hex"; Text = "GitHub Release x64 checksum: " + $sampleHash.Substring(0, 63); Expected = "" },
    @{ Name = "Previous release mentioned"; Text = "Previous release checksum was $armHash`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "x64 mentioned in changelog before ARM64 (no period)"; Text = "Changelog:`n- Fixed bug on x64 platform`n`nARM64 checksum: $armHash`nx64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "Previous release x64 mentioned before workflow x64"; Text = "Previous release x64 checksum: $armHash`nGitHub Release x64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "x64 container hash in changelog before x64 checksum"; Text = "Changelog:`n- Updated x64 container 2222222222222222222222222222222222222222222222222222222222222222`n`nDownloads:`nx64 checksum: $sampleHash"; Expected = $sampleHash },
    @{ Name = "x64 in table with arm64 row first"; Text = "| Arch | Hash |`n| ARM64 | $armHash |`n| x64 | $sampleHash |"; Expected = $sampleHash }
)

# Candidates
$c1_x64 = [regex]'(?i)(?:GitHub\s+Release\s+x64|x64)[\s\w-]*?(?:checksum|sha-?256)[\s:]+([0-9a-fA-F]{64})\b'
$c1_fallback = [regex]'(?i)(?:sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})\b'

$c4_x64 = [regex]'(?im)^[^\r\n]*?\b(?:github\s+release\s+x64|x64\b)[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c4_fallback = [regex]'(?im)^[^\r\n]*?\b(?:sha-?256|checksum)\b[^\r\n]*?\b([0-9a-fA-F]{64})\b'

$c5_workflow = [regex]'(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_x64      = [regex]'(?im)^[^\r\n]*?\bx64\b[^\r\n]*?(?:checksum|sha-?256|hash|digest|[|:])[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_fallback = [regex]'(?im)^[^\r\n]*?\b(?:sha-?256|checksum)\b[^\r\n]*?\b([0-9a-fA-F]{64})\b'
$c5_generic  = [regex]'\b([0-9a-fA-F]{64})\b'

function Run-Suite ($name, $rxX64, $rxFallback) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    $passed = 0
    $failed = 0
    foreach ($t in $testCases) {
        $sha = ""
        $m = $rxX64.Match($t.Text)
        if ($m.Success) {
            $sha = $m.Groups[1].Value
        } else {
            $m2 = $rxFallback.Match($t.Text)
            if ($m2.Success) {
                $sha = $m2.Groups[1].Value
            }
        }
        $isPass = ($sha.ToLowerInvariant() -eq $t.Expected.ToLowerInvariant())
        if ($isPass) {
            $passed++
            Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
        } else {
            $failed++
            Write-Host "[FAIL] $($t.Name): Expected='$($t.Expected)' Actual='$sha'" -ForegroundColor Red
        }
    }
    Write-Host "Result: Passed=$passed, Failed=$failed"
}

function Run-Candidate5 {
    Write-Host "`n=== CANDIDATE 5 (3-Tier Multi-Arch Resolution) ===" -ForegroundColor Cyan
    $passed = 0
    $failed = 0
    foreach ($t in $testCases) {
        $sha = ""
        $m = $c5_workflow.Match($t.Text)
        if ($m.Success) {
            $sha = $m.Groups[1].Value
        } else {
            $m2 = $c5_x64.Match($t.Text)
            if ($m2.Success) {
                $sha = $m2.Groups[1].Value
            } else {
                $m3 = $c5_fallback.Match($t.Text)
                if ($m3.Success) {
                    $sha = $m3.Groups[1].Value
                } else {
                    $m4 = $c5_generic.Match($t.Text)
                    if ($m4.Success) {
                        $sha = $m4.Groups[1].Value
                    }
                }
            }
        }
        $isPass = ($sha.ToLowerInvariant() -eq $t.Expected.ToLowerInvariant())
        if ($isPass) {
            $passed++
            Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
        } else {
            $failed++
            Write-Host "[FAIL] $($t.Name): Expected='$($t.Expected)' Actual='$sha'" -ForegroundColor Red
        }
    }
    Write-Host "Result: Passed=$passed, Failed=$failed"
}

Run-Suite "CANDIDATE 1 (Challenger 1 Raw)" $c1_x64 $c1_fallback
Run-Suite "CANDIDATE 4 (Line-Scoped with Strict Dual Boundaries)" $c4_x64 $c4_fallback
Run-Candidate5

