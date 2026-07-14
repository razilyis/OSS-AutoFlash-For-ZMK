# scripts/macos/icon.svg と同じデザインを System.Drawing で描画し、
# windows/AutoFlash/Assets/AppIcon.ico と TrayIcon.ico を生成する。
# (SVG レンダラー不要で再生成できるようにするためのスクリプト)
#Requires -Version 7
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot '..\..\windows\AutoFlash\Assets'
New-Item -ItemType Directory -Force $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = 2 * $r
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconBitmap([int]$size) {
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $s = $size / 1024.0
    $g.ScaleTransform($s, $s)

    # 背景(角丸 + 対角グラデーション)
    $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Point]::new(0, 0), [System.Drawing.Point]::new(1024, 1024),
        [System.Drawing.ColorTranslator]::FromHtml('#2b2f77'),
        [System.Drawing.ColorTranslator]::FromHtml('#171a3d'))
    $g.FillPath($bgBrush, (New-RoundedRectPath 0 0 1024 1024 220))

    $light = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#e7e9f5'))
    $dark = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#171a3d'))

    # chip body
    $g.FillPath($light, (New-RoundedRectPath 292 292 440 440 36))
    $g.FillPath($dark, (New-RoundedRectPath 352 352 320 320 18))

    # chip pins
    $pins = @(
        @(220, 380, 60, 28), @(220, 460, 60, 28), @(220, 540, 60, 28), @(220, 620, 60, 28),
        @(744, 380, 60, 28), @(744, 460, 60, 28), @(744, 540, 60, 28), @(744, 620, 60, 28),
        @(380, 220, 28, 60), @(460, 220, 28, 60), @(540, 220, 28, 60), @(620, 220, 28, 60),
        @(380, 744, 28, 60), @(460, 744, 28, 60), @(540, 744, 28, 60), @(620, 744, 28, 60)
    )
    foreach ($p in $pins) {
        $g.FillPath($light, (New-RoundedRectPath $p[0] $p[1] $p[2] $p[3] 8))
    }

    # flash bolt
    $bolt = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(566, 372), [System.Drawing.PointF]::new(452, 566),
        [System.Drawing.PointF]::new(520, 566), [System.Drawing.PointF]::new(470, 662),
        [System.Drawing.PointF]::new(600, 468), [System.Drawing.PointF]::new(528, 468)
    )
    $boltPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $boltPath.AddPolygon($bolt)
    $g.FillPath([System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#ffcf3a')), $boltPath)
    $pen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#171a3d'), 10)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($pen, $boltPath)

    $g.Dispose()
    return $bmp
}

function Write-Ico([string]$path, $entries) {
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    $writer.Write([uint16]0)                 # reserved
    $writer.Write([uint16]1)                 # type: icon
    $writer.Write([uint16]$entries.Count)
    $offset = 6 + 16 * $entries.Count
    foreach ($e in $entries) {
        $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
        $writer.Write([byte]$dim)            # width (0 = 256)
        $writer.Write([byte]$dim)            # height
        $writer.Write([byte]0)               # color count
        $writer.Write([byte]0)               # reserved
        $writer.Write([uint16]1)             # planes
        $writer.Write([uint16]32)            # bit count
        $writer.Write([uint32]$e.Data.Length)
        $writer.Write([uint32]$offset)
        $offset += $e.Data.Length
    }
    foreach ($e in $entries) { $writer.Write($e.Data) }
    $writer.Flush()
    [System.IO.File]::WriteAllBytes($path, $stream.ToArray())
}

$entries = foreach ($size in 256, 64, 48, 32, 24, 16) {
    $bmp = New-IconBitmap $size
    $ms = [System.IO.MemoryStream]::new()
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    @{ Size = $size; Data = $ms.ToArray() }
}

Write-Ico (Join-Path $outDir 'AppIcon.ico') $entries
Copy-Item (Join-Path $outDir 'AppIcon.ico') (Join-Path $outDir 'TrayIcon.ico') -Force
Write-Host "Generated: $outDir\AppIcon.ico, TrayIcon.ico"
