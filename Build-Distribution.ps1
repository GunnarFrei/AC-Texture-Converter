param(
    [string]$DistributionFolderName = 'AC Texture Converter Distribution with Icon',
    [string]$ArchiveName = 'AC-Texture-Converter-Windows-with-icon.zip'
)
$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
$portableRoot = Join-Path $sourceRoot 'AC Texture Converter Portable'
$distributionRoot = Join-Path $sourceRoot $DistributionFolderName
$archivePath = Join-Path $sourceRoot $ArchiveName

if (-not (Test-Path -LiteralPath (Join-Path $portableRoot 'AC Texture Converter.exe') -PathType Leaf)) {
    throw "Build the portable app first by running Build-Portable.ps1."
}
if (Test-Path -LiteralPath $distributionRoot) { throw "Output folder already exists; nothing was changed: $distributionRoot" }
if (Test-Path -LiteralPath $archivePath) { throw "Archive already exists; nothing was changed: $archivePath" }

$required = @(
    'Install-ACTextureConverter.bat','Install.ps1','ACTextureConverter.ps1',
    'Open-ACTextureConverter.bat','Repair-ACTextureConverter.bat','Repair-ACTextureConverter.ps1',
    'Uninstall-ACTextureConverter.bat','Uninstall-ACTextureConverter.ps1','README.md','ThirdPartyNotices.txt'
)
foreach ($name in $required) {
    $path = Join-Path $sourceRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required distribution file is missing: $path" }
}
foreach ($name in @('AC Texture Converter.exe','ACTextureConverter.ps1','README.txt','texconv.exe','ACTextureConverter.ico')) {
    $path = Join-Path $portableRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Portable package file is missing: $path" }
}

New-Item -ItemType Directory -Path $distributionRoot | Out-Null
try {
    foreach ($name in $required) { Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination $distributionRoot }
    Copy-Item -LiteralPath $portableRoot -Destination $distributionRoot -Recurse
    Compress-Archive -LiteralPath $distributionRoot -DestinationPath $archivePath -CompressionLevel Optimal
    Write-Host "Distribution folder created: $distributionRoot"
    Write-Host "Windows distribution archive created: $archivePath"
    Write-Host 'Users can extract the archive and run Install-ACTextureConverter.bat.'
}
catch {
    Write-Error $_
    throw "Distribution packaging failed. Review the new output folder before removing anything: $distributionRoot"
}
