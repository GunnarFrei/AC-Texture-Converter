param([switch]$Force)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourcePath = Join-Path $PSScriptRoot 'Assets\ACTextureConverter.png'
$iconPath = Join-Path $PSScriptRoot 'Assets\ACTextureConverter.ico'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Icon artwork is missing: $sourcePath" }
if (Test-Path -LiteralPath $iconPath) {
    if (-not $Force) { throw "Icon already exists; use -Force to regenerate it: $iconPath" }
    $iconBackup = Join-Path (Split-Path -Parent $iconPath) ('ACTextureConverter-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ico')
    if (Test-Path -LiteralPath $iconBackup) { throw "Icon backup already exists; nothing was changed: $iconBackup" }
    Copy-Item -LiteralPath $iconPath -Destination $iconBackup
    Remove-Item -LiteralPath $iconPath -Force
}

$sizes = @(256, 64, 48, 32, 16)
$frames = New-Object 'System.Collections.Generic.List[byte[]]'
$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    foreach ($size in $sizes) {
        $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($source, 0, 0, $size, $size)
            } finally { $graphics.Dispose() }
            $stream = New-Object IO.MemoryStream
            try {
                $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
                $frames.Add($stream.ToArray())
            } finally { $stream.Dispose() }
        } finally { $bitmap.Dispose() }
    }
} finally { $source.Dispose() }

$stream = [IO.File]::Open($iconPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$sizes.Count)
        $offset = 6 + (16 * $sizes.Count)
        for ($index = 0; $index -lt $sizes.Count; $index++) {
            $dimensionByte = if ($sizes[$index] -eq 256) { [byte]0 } else { [byte]$sizes[$index] }
            $writer.Write($dimensionByte)
            $writer.Write($dimensionByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$frames[$index].Length)
            $writer.Write([UInt32]$offset)
            $offset += $frames[$index].Length
        }
        foreach ($frame in $frames) { $writer.Write($frame) }
    } finally { $writer.Dispose() }
} finally { $stream.Dispose() }

Write-Host "Windows icon created: $iconPath"
