$ErrorActionPreference = 'Stop'
$sourceScript = Join-Path $PSScriptRoot 'ACTextureConverter.ps1'
$installRoot = Join-Path $env:LOCALAPPDATA 'ACTextureConverter'
$targetScript = Join-Path $installRoot 'ACTextureConverter.ps1'
$sourceExe = Join-Path $PSScriptRoot 'AC Texture Converter Portable\AC Texture Converter.exe'
$targetExe = Join-Path $installRoot 'AC Texture Converter.exe'
$backupRoot = Join-Path $env:LOCALAPPDATA 'ACTextureConverter-Backups'

try {
    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) { throw "Updated app script is missing: $sourceScript" }
    if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) { throw "AC Texture Converter is not installed at $installRoot. Run Install-ACTextureConverter.bat first." }

    [void][IO.Directory]::CreateDirectory($backupRoot)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupScript = Join-Path $backupRoot "ACTextureConverter-$stamp.ps1"
    $backupExe = Join-Path $backupRoot "AC-Texture-Converter-$stamp.exe"
    $hadExe = Test-Path -LiteralPath $targetExe -PathType Leaf
    Copy-Item -LiteralPath $targetScript -Destination $backupScript
    if ($hadExe) { Copy-Item -LiteralPath $targetExe -Destination $backupExe }

    try {
        Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
        if (Test-Path -LiteralPath $sourceExe -PathType Leaf) { Copy-Item -LiteralPath $sourceExe -Destination $targetExe -Force }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScript -RegisterContextMenu
        if ($LASTEXITCODE -ne 0) { throw "Explorer menu registration failed (exit code $LASTEXITCODE)." }
    } catch {
        Copy-Item -LiteralPath $backupScript -Destination $targetScript -Force
        if ($hadExe) { Copy-Item -LiteralPath $backupExe -Destination $targetExe -Force }
        elseif (Test-Path -LiteralPath $targetExe) { Remove-Item -LiteralPath $targetExe -Force }
        throw
    }

    Write-Host 'AC Texture Converter has been updated and the Explorer menu repaired.' -ForegroundColor Green
    if (Test-Path -LiteralPath $targetExe -PathType Leaf) { Write-Host 'The Explorer menu now launches the Windows executable.' }
    else { Write-Host "Build the portable app first to add its executable: $PSScriptRoot\Build-Portable.ps1" }
    Write-Host "Previous app script backup: $backupScript"
} catch {
    Write-Host "Repair failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host 'Press any key to close this window.'
try { [void][Console]::ReadKey($true) } catch { }
