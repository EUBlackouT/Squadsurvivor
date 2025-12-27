Param(
    [Parameter(Mandatory=$true)][string]$CharacterId,
    [Parameter(Mandatory=$true)][string]$Name,
    [switch]$AsPlayer,
    [switch]$AsProjectile
)

$ErrorActionPreference = 'Stop'

$root = Get-Location
$base = Join-Path $root "client\assets\ai_ready\pixellab\$CharacterId"
if (Test-Path $base) { Remove-Item -Recurse -Force $base }
New-Item -ItemType Directory -Force -Path $base | Out-Null

$zip = Join-Path $base 'char.zip'
$uri = "https://api.pixellab.ai/mcp/characters/$CharacterId/download"
curl.exe -fSL $uri -o $zip

$unz = Join-Path $base 'unzipped'
Expand-Archive -LiteralPath $zip -DestinationPath $unz -Force

$walk = $null
if ($AsPlayer -or ($Name -eq 'player') -or $AsProjectile) {
  $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-8-frames' } | Select-Object -First 1
  if (-not $walk) { $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-8' } | Select-Object -First 1 }
  if (-not $walk -and -not $AsProjectile) { Write-Error "walking-8-frames/walking-8 not found in archive for $CharacterId"; exit 1 }
} else {
  $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-4-frames' } | Select-Object -First 1
  if (-not $walk) { $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-4' } | Select-Object -First 1 }
  # Fallback: some PixelLab archives only include walking-8-frames; take first 4 frames for enemies
  if (-not $walk) { $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-8-frames' } | Select-Object -First 1 }
  if (-not $walk) { $walk = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'walking-8' } | Select-Object -First 1 }
  if (-not $walk) { Write-Error "walking-4-frames/walking-4 (or 8-frame fallback) not found in archive for $CharacterId"; exit 1 }
}

$isPlayer = $AsPlayer -or ($Name -eq 'player')
if ($isPlayer) {
  $dest = Join-Path $root "client\assets\sprites\player\animations\walking-8-frames"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
} elseif ($AsProjectile) {
  $destRoot = Join-Path $root "client\assets\sprites\projectiles\$Name"
  $dest = Join-Path $destRoot "animations\walking-8-frames"
  $destRot = Join-Path $destRoot "rotations"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  if (Test-Path $destRot) { Remove-Item -Recurse -Force $destRot }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  New-Item -ItemType Directory -Force -Path $destRot | Out-Null
} else {
  $dest = Join-Path $root "client\assets\sprites\enemies\$Name\animations\walking-4-frames"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
}

# Copy per direction
$dirs = @('east','north-east','north','north-west','west','south-west','south','south-east')
if ($walk) {
  foreach($d in $dirs){
    $srcDir = Join-Path $walk.FullName $d
    if(Test-Path $srcDir){
      $dDst = Join-Path $dest $d
      if(Test-Path $dDst){ Remove-Item -Recurse -Force $dDst }
      New-Item -ItemType Directory -Force -Path $dDst | Out-Null
      $files = Get-ChildItem -File $srcDir -Filter *.png | Sort-Object Name
      if($isPlayer -or $AsProjectile){
        # Player/Projectile: first 8 frames
        $take = [Math]::Min(8, $files.Count)
        for($i=0; $i -lt $take; $i++){
          $out = Join-Path $dDst ("frame_" + ('{0:D3}' -f $i) + '.png')
          Copy-Item $files[$i].FullName $out -Force
        }
      } else {
        # Enemies: first 4 frames only
        $take = [Math]::Min(4, $files.Count)
        for($i=0; $i -lt $take; $i++){
          $out = Join-Path $dDst ("frame_" + ('{0:D3}' -f $i) + '.png')
          Copy-Item $files[$i].FullName $out -Force
        }
      }
    }
  }
} elseif ($AsProjectile) {
  # Synthesize frames from rotations
  $rot = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'rotations' } | Select-Object -First 1
  foreach($d in $dirs){
    $src = Join-Path $rot.FullName ($d + '.png')
    if (Test-Path $src) {
      $dDst = Join-Path $dest $d
      if(Test-Path $dDst){ Remove-Item -Recurse -Force $dDst }
      New-Item -ItemType Directory -Force -Path $dDst | Out-Null
      for($i=0; $i -lt 8; $i++){
        $out = Join-Path $dDst ("frame_" + ('{0:D3}' -f $i) + '.png')
        Copy-Item $src $out -Force
      }
    }
  }
}
Write-Output "Imported $Name frames to $dest"

# For projectiles: also copy rotations if present
if ($AsProjectile) {
  $rot = Get-ChildItem -Recurse -Directory $unz | Where-Object { $_.Name -eq 'rotations' } | Select-Object -First 1
  if ($rot) {
    $dirs = @('east','north-east','north','north-west','west','south-west','south','south-east')
    foreach($d in $dirs){
      $src = Join-Path $rot.FullName ($d + '.png')
      if (Test-Path $src) {
        Copy-Item $src (Join-Path $destRot ($d + '.png')) -Force
      }
    }
    Write-Output "Imported $Name rotations to $destRot"
  }
}


