# Forensic verification script for test suite assertions
$testsDir = "E:\Programacion\FluentFlyout\tests"
$testFiles = Get-ChildItem -Path $testsDir -Filter "*.ps1"

$findings = @()

foreach ($file in $testFiles) {
    $lines = Get-Content $file.FullName
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1

        # Check for hardcoded literal Actual in Assert-
        if ($line -match 'Assert-(True|False|Equal|Match|NotMatch)') {
            # Check if line itself or next line has -Actual literal
            $combined = $line
            if ($line -match '`$' -and ($i + 1) -lt $lines.Length) {
                $combined += " " + $lines[$i + 1].Trim()
            }
            if ($combined -match '-Actual\s+(\$true|\$false|[0-9]+|"[^"]*"|\x27[^\x27]*\x27)\s+(-Expected|-Pattern|\s*$)') {
                $findings += [PSCustomObject]@{
                    File = $file.Name
                    Line = $lineNum
                    Issue = "Hardcoded -Actual literal"
                    Code = $combined.Trim()
                }
            }
            # Check for tautological Assert-Equal -Actual $x -Expected $x
            if ($combined -match '-Actual\s+(\$\w+)\s+-Expected\s+(\$\w+)') {
                if ($matches[1] -eq $matches[2]) {
                    $findings += [PSCustomObject]@{
                        File = $file.Name
                        Line = $lineNum
                        Issue = "Tautological identical variable comparison"
                        Code = $combined.Trim()
                    }
                }
            }
        }
    }
}

Write-Host "Total findings: $($findings.Count)"
$findings | Format-Table -AutoSize
