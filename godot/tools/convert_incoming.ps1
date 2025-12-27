Param(
    [string]$InDir = "assets/_incoming",
    [string]$OutDir = "assets/structures",
    [int]$FrameSize = 256,
    [int]$TargetFrames = 8,
    [int]$InnerPad = 3
)

Set-StrictMode -Version Latest
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path) | Out-Null
Set-Location ..\ | Out-Null

if (-not (Test-Path $InDir)) {
    throw "Incoming folder not found: $(Resolve-Path .)\$InDir"
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

Add-Type -AssemblyName System.Drawing

function Get-FramesCount([int]$w) {
    foreach($c in 8,6,4,1){ if(($w % $c) -eq 0){ return $c } }
    return 1
}

function Sample-BG([System.Drawing.Bitmap]$bmp){
    $sx=[Math]::Max(1,[Math]::Min(16, [int]($bmp.Width/20)))
    $sy=[Math]::Max(1,[Math]::Min(16, [int]($bmp.Height/20)))
    $r=0;$g=0;$b=0;$n=0
    for($y=0;$y -lt $sy;$y++){
        for($x=0;$x -lt $sx;$x++){
            $c=$bmp.GetPixel($x,$y)
            $r+=$c.R; $g+=$c.G; $b+=$c.B; $n++
        }
    }
    if($n -eq 0){ return [System.Drawing.Color]::FromArgb(255,0,0,0) }
    return [System.Drawing.Color]::FromArgb(255,[int]($r/$n),[int]($g/$n),[int]($b/$n))
}

function ColorKey-ToAlpha([System.Drawing.Bitmap]$bmp, [System.Drawing.Color]$key, [double]$tol){
    $tol2=$tol*$tol*255*255
    for($y=0;$y -lt $bmp.Height;$y++){
        for($x=0;$x -lt $bmp.Width;$x++){
            $c=$bmp.GetPixel($x,$y)
            $dr=[double]$c.R - $key.R
            $dg=[double]$c.G - $key.G
            $db=[double]$c.B - $key.B
            if(($dr*$dr + $dg*$dg + $db*$db) -le $tol2){
                $bmp.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(0,$c.R,$c.G,$c.B))
            }
        }
    }
}

function Get-AlphaBounds([System.Drawing.Bitmap]$bmp, [int]$x0,[int]$y0,[int]$w,[int]$h){
    $minx=[int]::MaxValue; $miny=[int]::MaxValue; $maxx=-1; $maxy=-1
    for($y=$y0;$y -lt ($y0+$h);$y++){
        for($x=$x0;$x -lt ($x0+$w);$x++){
            $a=$bmp.GetPixel($x,$y).A
            if($a -gt 3){
                if($x -lt $minx){ $minx=$x }
                if($y -lt $miny){ $miny=$y }
                if($x -gt $maxx){ $maxx=$x }
                if($y -gt $maxy){ $maxy=$y }
            }
        }
    }
    if($maxx -lt $minx -or $maxy -lt $miny){ return @{X=$x0;Y=$y0;W=$w;H=$h} }
    return @{X=$minx;Y=$miny;W=($maxx-$minx+1);H=($maxy-$miny+1)}
}

function Get-BottomCenterX([System.Drawing.Bitmap]$bmp, $b){
    $ystart=$b.Y + [int]([Math]::Floor($b.H*0.8))
    if($ystart -gt ($b.Y+$b.H-1)){ $ystart=$b.Y }
    $xmin=[int]::MaxValue; $xmax=-1
    for($y=$ystart;$y -le ($b.Y+$b.H-1);$y++){
        for($x=$b.X;$x -lt ($b.X+$b.W);$x++){
            if($bmp.GetPixel($x,$y).A -gt 3){
                if($x -lt $xmin){ $xmin=$x }
                if($x -gt $xmax){ $xmax=$x }
            }
        }
    }
    if($xmax -lt $xmin){ return $b.X + [int]([Math]::Round($b.W*0.5)) }
    return [int]([Math]::Round(($xmin+$xmax)/2.0))
}

$files=Get-ChildItem $InDir -File -Filter *.png
if($files.Count -eq 0){ throw "No PNGs found in $InDir" }

foreach($f in $files){
    $bmp=[System.Drawing.Bitmap]::new($f.FullName)
    $frames=Get-FramesCount $bmp.Width
    $cellW=[int]($bmp.Width/$frames)
    $cellH=$bmp.Height

    $bg=Sample-BG $bmp
    ColorKey-ToAlpha $bmp $bg 0.10

    $bounds=@(); $centers=@()
    for($i=0;$i -lt $frames;$i++){
        $rX=$i*$cellW
        $b=Get-AlphaBounds $bmp $rX 0 $cellW $cellH
        $bounds+=$b
        $centers+=(Get-BottomCenterX $bmp $b)
    }

    $sorted = $centers | Sort-Object
    if($sorted.Count -eq 0){ $sorted=@(0) }
    if(($sorted.Count % 2) -eq 1){
        $pivotX=$sorted[[int]([math]::Floor($sorted.Count/2))]
    } else {
        $pivotX=[int]([math]::Round(($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2.0))
    }

    $outBmp=[System.Drawing.Bitmap]::new($FrameSize*$TargetFrames, $FrameSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g=[System.Drawing.Graphics]::FromImage($outBmp)
    $g.Clear([System.Drawing.Color]::FromArgb(0,0,0,0))

    function Map-Index([int]$i,[int]$frames){
        switch($frames){
            8 { return $i }
            6 { $map=@(0,1,1,2,3,4,5,5); return $map[$i] }
            4 { $map=@(0,0,1,1,2,2,3,3); return $map[$i] }
            default { return 0 }
        }
    }

    for($i=0;$i -lt $TargetFrames;$i++){
        $si=Map-Index $i $frames
        $b=$bounds[$si]
        $sub=[System.Drawing.Rectangle]::new($b.X,$b.Y,$b.W,$b.H)
        $centerWithinBounds = $centers[$si] - $b.X
        $destX=[int]([Math]::Round(($i*$FrameSize)+$FrameSize*0.5 - $centerWithinBounds))
        $destY=$FrameSize - $InnerPad - $b.H
        $destX=[Math]::Max($i*$FrameSize+$InnerPad, [Math]::Min(($i+1)*$FrameSize-$InnerPad-$b.W, $destX))
        $destY=[Math]::Max($InnerPad, [Math]::Min($FrameSize-$InnerPad-$b.H, $destY))
        $dst=[System.Drawing.Rectangle]::new($destX,$destY,$b.W,$b.H)
        $g.DrawImage($bmp, $dst, $sub, [System.Drawing.GraphicsUnit]::Pixel)
    }

    $g.Dispose()
    $baseName = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $sanitized = ($baseName -replace '[^A-Za-z0-9_-]','_').ToLower()
    $outPath=Join-Path $OutDir ($sanitized + '_sheet.png')
    if (Test-Path $outPath) { Remove-Item -Force $outPath }
    $outBmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $outBmp.Dispose()
    $bmp.Dispose()
    Write-Host \"Converted: $($f.Name) -> $outPath\"
}

Write-Host 'Done. Outputs:'
Get-ChildItem $OutDir -Filter '*_sheet.png' | Select-Object Name,Length | Format-Table -AutoSize


