$ErrorActionPreference = 'Stop'
$sourceScript = Join-Path $PSScriptRoot 'ACTextureConverter.ps1'
$installRoot = Join-Path $env:LOCALAPPDATA 'ACTextureConverter'
$targetScript = Join-Path $installRoot 'ACTextureConverter.ps1'
$sourceExe = Join-Path $PSScriptRoot 'AC Texture Converter Portable\AC Texture Converter.exe'
$targetExe = Join-Path $installRoot 'AC Texture Converter.exe'
$sourceShellExtension = Join-Path $PSScriptRoot 'AC Texture Converter Portable\ACTextureConverterShellExtension.dll'
$targetShellExtension = Join-Path $installRoot 'ACTextureConverterShellExtension.dll'
$sourceLicense = Join-Path $PSScriptRoot 'LICENSE'
$targetLicense = Join-Path $installRoot 'LICENSE'
$sourceNotices = Join-Path $PSScriptRoot 'ThirdPartyNotices.txt'
$targetNotices = Join-Path $installRoot 'ThirdPartyNotices.txt'
$backupRoot = Join-Path $env:LOCALAPPDATA 'ACTextureConverter-Backups'

try {
    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) { throw "Updated app script is missing: $sourceScript" }
    if (-not (Test-Path -LiteralPath $sourceLicense -PathType Leaf)) { throw "Project license is missing: $sourceLicense" }
    if (-not (Test-Path -LiteralPath $sourceNotices -PathType Leaf)) { throw "Third-party notices are missing: $sourceNotices" }
    if (-not (Test-Path -LiteralPath $sourceShellExtension -PathType Leaf)) { throw "The Explorer integration library is missing: $sourceShellExtension" }
    if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) { throw "AC Texture Converter is not installed at $installRoot. Run Install-ACTextureConverter.bat first." }

    [void][IO.Directory]::CreateDirectory($backupRoot)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupScript = Join-Path $backupRoot "ACTextureConverter-$stamp.ps1"
    $backupExe = Join-Path $backupRoot "AC-Texture-Converter-$stamp.exe"
    $backupLicense = Join-Path $backupRoot "LICENSE-$stamp.txt"
    $backupNotices = Join-Path $backupRoot "ThirdPartyNotices-$stamp.txt"
    $backupShellExtension = Join-Path $backupRoot "ACTextureConverterShellExtension-$stamp.dll"
    $hadExe = Test-Path -LiteralPath $targetExe -PathType Leaf
    $hadLicense = Test-Path -LiteralPath $targetLicense -PathType Leaf
    $hadNotices = Test-Path -LiteralPath $targetNotices -PathType Leaf
    $hadShellExtension = Test-Path -LiteralPath $targetShellExtension -PathType Leaf
    Copy-Item -LiteralPath $targetScript -Destination $backupScript
    if ($hadExe) { Copy-Item -LiteralPath $targetExe -Destination $backupExe }
    if ($hadLicense) { Copy-Item -LiteralPath $targetLicense -Destination $backupLicense }
    if ($hadNotices) { Copy-Item -LiteralPath $targetNotices -Destination $backupNotices }
    if ($hadShellExtension) { Copy-Item -LiteralPath $targetShellExtension -Destination $backupShellExtension }

    try {
        Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
        if (Test-Path -LiteralPath $sourceExe -PathType Leaf) { Copy-Item -LiteralPath $sourceExe -Destination $targetExe -Force }
        Copy-Item -LiteralPath $sourceShellExtension -Destination $targetShellExtension -Force
        Copy-Item -LiteralPath $sourceLicense -Destination $targetLicense -Force
        Copy-Item -LiteralPath $sourceNotices -Destination $targetNotices -Force
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScript -RegisterContextMenu
        if ($LASTEXITCODE -ne 0) { throw "Explorer menu registration failed (exit code $LASTEXITCODE)." }
    } catch {
        Copy-Item -LiteralPath $backupScript -Destination $targetScript -Force
        if ($hadExe) { Copy-Item -LiteralPath $backupExe -Destination $targetExe -Force }
        elseif (Test-Path -LiteralPath $targetExe) { Remove-Item -LiteralPath $targetExe -Force }
        if ($hadLicense) { Copy-Item -LiteralPath $backupLicense -Destination $targetLicense -Force }
        elseif (Test-Path -LiteralPath $targetLicense) { Remove-Item -LiteralPath $targetLicense -Force }
        if ($hadNotices) { Copy-Item -LiteralPath $backupNotices -Destination $targetNotices -Force }
        elseif (Test-Path -LiteralPath $targetNotices) { Remove-Item -LiteralPath $targetNotices -Force }
        if ($hadShellExtension) { Copy-Item -LiteralPath $backupShellExtension -Destination $targetShellExtension -Force }
        elseif (Test-Path -LiteralPath $targetShellExtension) { Remove-Item -LiteralPath $targetShellExtension -Force }
        try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScript -RegisterContextMenu } catch { }
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

