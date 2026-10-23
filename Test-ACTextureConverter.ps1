$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($file.Name): $($errors[0].Message)" }
}
& (Join-Path $root 'ACTextureConverter.ps1') -SelfTest
$source = Get-Content -LiteralPath (Join-Path $root 'ACTextureConverter.ps1') -Raw
$contextFunction = ([regex]::Match($source, '(?s)function Set-ExplorerContextMenu.*?\n}\nLoad-FormatSettings')).Value
if ($contextFunction -notmatch 'shellex\\ContextMenuHandlers\\ACTextureConverter' -or $contextFunction -notmatch '91A658F4-E8EC-4C52-8AD8-51D0FB40561D' -or $contextFunction -notmatch 'ACTextureConverterShellExtension\.dll') {
    throw 'Explorer must register the selection-aware COM context menu handler.'
}
$shellExtension = Get-Content -LiteralPath (Join-Path $root 'Launcher\ACTextureConverterShellExtension.cs') -Raw
if ($shellExtension -notmatch 'IDataObject' -or $shellExtension -notmatch 'DragQueryFile' -or $shellExtension -notmatch 'File\.WriteAllLines\(selectionFile, selectedPaths' -or $shellExtension -notmatch 'InputListFile' -or $shellExtension -notmatch 'AddFormatSubmenu') {
    throw 'The Explorer handler must build submenus and write the full selection list for one app launch.'
}
$app = Get-Content -LiteralPath (Join-Path $root 'ACTextureConverter.ps1') -Raw
if ($app -notmatch 'InputListFile' -or $app -notmatch 'ReadAllLines\(\$listPath') {
    throw 'The app must read every path from the Explorer selection list.'
}
$installer = Get-Content -LiteralPath (Join-Path $root 'Install.ps1') -Raw
$repair = Get-Content -LiteralPath (Join-Path $root 'Repair-ACTextureConverter.ps1') -Raw
$uninstaller = Get-Content -LiteralPath (Join-Path $root 'Uninstall-ACTextureConverter.ps1') -Raw
$launcherBat = Get-Content -LiteralPath (Join-Path $root 'Open-ACTextureConverter.bat') -Raw
$portableBuilder = Get-Content -LiteralPath (Join-Path $root 'Build-Portable.ps1') -Raw
if ($installer -notmatch 'AC Texture Converter Portable\\AC Texture Converter\.exe' -or $installer -notmatch 'ACTextureConverterShellExtension\.dll' -or $installer -notmatch "\$portableRoot 'texconv\.exe'" -or $installer -notmatch '\$portableTexconv' -or $installer -notmatch "'AC Texture Converter\.exe'") {
    throw 'The installer must copy the app, Explorer handler, and bundled texconv.'
}
if ($repair -notmatch 'AC Texture Converter Portable\\AC Texture Converter\.exe' -or $repair -notmatch 'ACTextureConverterShellExtension\.dll' -or $repair -notmatch '\-RegisterContextMenu') {
    throw 'The repair tool must update the executable and Explorer handler.'
}
if ($uninstaller -notmatch "'AC Texture Converter\.exe'" -or $uninstaller -notmatch "'ACTextureConverterShellExtension\.dll'") {
    throw 'The uninstaller safety allowlist must include the portable app and Explorer handler.'
}
if ($launcherBat -notmatch 'if exist .*AC Texture Converter\.exe' -or $launcherBat -notmatch 'ACTextureConverter\.ps1') {
    throw 'The launcher batch file must prefer the executable and keep a PowerShell fallback.'
}
if ($portableBuilder -notmatch '/win32icon:' -or -not (Test-Path -LiteralPath (Join-Path $root 'Assets\ACTextureConverter.ico') -PathType Leaf)) {
    throw 'The portable executable must be built with the app icon.'
}
Write-Output 'Explorer menu structure checks: OK'
Write-Output 'Installer and launcher checks: OK'
Write-Output 'PowerShell syntax checks: OK'

