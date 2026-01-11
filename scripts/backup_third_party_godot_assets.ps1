$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$polyBlocks = "godot\\PolyBlocks"
$effectblocks = "godot\\assets\\vfx\\effectblocks"

if (-not (Test-Path -LiteralPath $polyBlocks)) {
  Write-Host "Missing: $polyBlocks (nothing to back up)" -ForegroundColor Yellow
  exit 2
}
if (-not (Test-Path -LiteralPath $effectblocks)) {
  Write-Host "Missing: $effectblocks (nothing to back up)" -ForegroundColor Yellow
  exit 2
}

New-Item -ItemType Directory -Force -Path "tmp" | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outZip = "tmp\\third_party_godot_assets_$stamp.zip"

Write-Host "Creating backup: $outZip" -ForegroundColor Cyan
Compress-Archive -Force -Path $polyBlocks, $effectblocks -DestinationPath $outZip
Write-Host "Done." -ForegroundColor Green



