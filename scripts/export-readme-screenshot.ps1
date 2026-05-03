# Crops the journal region at native pixel size (no downscale) -> docs/screenshot.jpg
param(
  [string] $Source = $env:JOURNAL_SCREENSHOT_SRC
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Source -or -not (Test-Path $Source)) {
  throw "Set `$Source or env JOURNAL_SCREENSHOT_SRC to your full screenshot image path (.png or .jpg)."
}
$dest = Join-Path $root 'docs\screenshot.jpg'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Source)
try {
  $iw = $img.Width
  $ih = $img.Height
  $cw = [Math]::Max(320, [int]($iw * 0.42))
  $ch = [Math]::Max(240, [int]($ih * 0.62))
  $cx = [int](($iw - $cw) / 2)
  $cy = [int]([Math]::Max(0, ($ih - $ch) / 2 - $ih * 0.05))

  $bmp = New-Object System.Drawing.Bitmap $cw, $ch
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $srcRect = New-Object System.Drawing.Rectangle $cx, $cy, $cw, $ch
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $cw, $ch), $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()

  if (Test-Path $dest) { Remove-Item $dest -Force }
  $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $enc = New-Object System.Drawing.Imaging.EncoderParameters 1
  $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]92)
  $bmp.Save($dest, $jpegCodec, $enc)
  $bmp.Dispose()
  Write-Host "Wrote $dest ($cw x $ch px, no resize, JPEG 92)"
}
finally {
  $img.Dispose()
}
