# Test Challenger's exact NormalizeVersion draft

function ChallengerNormalizeVersion([string]$cleaned, [ref]$version) {
    $version.Value = [Version]::new(0, 0, 0, 0)
    $parts = $cleaned.Split('.')
    if ($parts.Length -eq 0 -or $parts.Length -gt 4) { return $false }
    $major = if ($parts.Length -gt 0 -and [int]::TryParse($parts[0], [ref]$m)) { $m } else { 0 }
    $minor = if ($parts.Length -gt 1 -and [int]::TryParse($parts[1], [ref]$n)) { $n } else { 0 }
    $build = if ($parts.Length -gt 2 -and [int]::TryParse($parts[2], [ref]$b)) { $b } else { 0 }
    $rev = if ($parts.Length -gt 3 -and [int]::TryParse($parts[3], [ref]$r)) { $r } else { 0 }
    $version.Value = [Version]::new($major, $minor, $build, $rev)
    return $true
}

$v = [Version]::new(0,0,0,0)
$res = ChallengerNormalizeVersion "invalid" ([ref]$v)
Write-Host "Challenger draft NormalizeVersion('invalid'): res=$res, version=$($v.ToString())"
