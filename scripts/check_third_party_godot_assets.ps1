$ErrorActionPreference = "Stop"

function Assert-PathExists([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "MISSING: $Label -> $Path" -ForegroundColor Red
    return $false
  }
  Write-Host "OK: $Label -> $Path" -ForegroundColor Green
  return $true
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$ok = $true
$ok = (Assert-PathExists "godot\\PolyBlocks\\PixelRenderer\\PixelRenderer.tscn" "PolyBlocks PixelRenderer") -and $ok
$ok = (Assert-PathExists "godot\\assets\\vfx\\effectblocks" "EffectBlocks exported flipbooks") -and $ok

if (-not $ok) {
  Write-Host ""
  Write-Host "These folders are intentionally NOT committed to git (see .gitignore)." -ForegroundColor Yellow
  Write-Host "Restore by re-copying / re-extracting your third-party packs into the paths above." -ForegroundColor Yellow
  exit 2
}

Write-Host ""
Write-Host "Third-party VFX folders look good." -ForegroundColor Cyan





