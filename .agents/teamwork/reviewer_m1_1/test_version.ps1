$tests = @(
    @('v2.15.0', 'v2.16.0', $true),
    @('2.15.0', '2.16.0', $true),
    @('v2.16.0', 'v2.16.0', $false),
    @('v2.17.0', 'v2.16.0', $false),
    @('v2.16.0-beta1', 'v2.16.0', $false),
    @('v2.15.0-beta1', 'v2.16.0', $true),
    @('invalid', 'v2.16.0', $false)
)
foreach ($t in $tests) {
    $c = $t[0]
    $n = $t[1]
    $exp = $t[2]
    $cleanC = if ([string]::IsNullOrWhiteSpace($c)) { '0.0.0.0' } else { $v = $c.Trim().TrimStart('v','V'); $idx = $v.IndexOf('-'); if ($idx -ge 0) { $v.Substring(0, $idx) } else { $v } }
    $cleanN = if ([string]::IsNullOrWhiteSpace($n)) { '0.0.0.0' } else { $v = $n.Trim().TrimStart('v','V'); $idx = $v.IndexOf('-'); if ($idx -ge 0) { $v.Substring(0, $idx) } else { $v } }
    $res = $false
    $v1 = [version]'0.0.0.0'
    $v2 = [version]'0.0.0.0'
    if ([version]::TryParse($cleanC, [ref]$v1) -and [version]::TryParse($cleanN, [ref]$v2)) {
        $res = ($v2 -gt $v1)
    }
    Write-Output "$c vs $n -> $res (Expected: $exp)"
}
