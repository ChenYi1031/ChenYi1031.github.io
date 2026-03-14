Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$p = Join-Path (Get-Location) "tools\\enrich_posts.ps1"
$lines = Get-Content -LiteralPath $p -Encoding utf8

$out = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
  if ($l -match '=\s*@\"\s*$') {
    $out.Add(($l -replace '=\s*@\"\s*$', '= @'''))
    continue
  }
  if ($l -match '^\"@\s*$') {
    $out.Add("'@")
    continue
  }
  $out.Add($l)
}

($out -join "`n") | Out-File -LiteralPath $p -Encoding utf8 -NoNewline
Write-Host "Converted here-strings in $p"

