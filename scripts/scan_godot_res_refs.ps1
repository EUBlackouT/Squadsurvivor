$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Normalize-ResPath([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  if (-not $s.StartsWith("res://")) { return $null }

  # Trim common trailing delimiters from matches like res://foo.png")
  $t = $s.Trim()
  while ($t.Length -gt 0) {
    $last = $t.Substring($t.Length - 1, 1)
    if ($last -in @('"', "'", ")", "]", "}", ",", ";")) {
      $t = $t.Substring(0, $t.Length - 1)
      continue
    }
    break
  }

  if ($t -eq "res://") { return $null }
  return $t
}

$root = Get-RepoRoot
Set-Location $root

$godotRoot = Join-Path $root "godot"
if (-not (Test-Path -LiteralPath $godotRoot)) {
  Write-Host "MISSING: godot folder -> $godotRoot" -ForegroundColor Red
  exit 2
}

$files = Get-ChildItem -LiteralPath $godotRoot -Recurse -File | Where-Object {
  $_.Name -eq "project.godot" -or $_.Extension -in ".tscn",".tres",".gd",".json",".gdshader"
}

# Match until common delimiters (quotes, whitespace, close-parens, etc).
# This avoids capturing call suffixes like `").instantiate()`.
$rx = [regex]::new('res://[^\s"''\)\]\},;<>]+')

$paths = New-Object "System.Collections.Generic.HashSet[string]"
foreach ($f in $files) {
  $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $txt) { continue }
  foreach ($m in $rx.Matches($txt)) {
    $p = Normalize-ResPath $m.Value
    if ($null -ne $p) { [void]$paths.Add($p) }
  }
}

$missing = New-Object "System.Collections.Generic.List[string]"
foreach ($p in $paths) {
  $rel = $p.Substring(6) -replace "/", "\"
  $full = Join-Path $godotRoot $rel
  if (-not (Test-Path -LiteralPath $full)) {
    $missing.Add($p)
  }
}

if ($missing.Count -eq 0) {
  Write-Host ("OK: no missing res:// references found (" + $paths.Count + " unique paths scanned).") -ForegroundColor Green
  exit 0
}

Write-Host ("MISSING: " + $missing.Count + " res:// references (showing up to 120):") -ForegroundColor Red
$missing | Sort-Object | Select-Object -First 120 | ForEach-Object { Write-Host (" - " + $_) }
exit 2


