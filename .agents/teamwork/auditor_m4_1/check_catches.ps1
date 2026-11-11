# Check try/catch blocks in tests
$testsDir = "E:\Programacion\FluentFlyout\tests"
$testFiles = Get-ChildItem -Path $testsDir -Filter "*.ps1"

Write-Host "=== Inspecting catch blocks in tests ==="
foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw
    $matches = [regex]::Matches($content, 'catch\s*\{([^}]*)\}')
    foreach ($m in $matches) {
        $catchBody = $m.Groups[1].Value.Trim()
        Write-Host "File: $($file.Name)"
        Write-Host "Catch: $catchBody"
        Write-Host "----------------------------------"
    }
}
