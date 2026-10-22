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
if ($source -match '\$rootCommand\s*=' -or $source -notmatch 'Set-ContextLeaf \$rootChildren ''03_Open'' ''Open AC Texture Converter'' ''-OpenWith''') {
    throw 'Explorer parent must remain a cascade, with the app launcher as a child item.'
}
if ($source -notmatch "SetValue\('ExtendedSubCommandsKey', 'ACTextureConverter\.ContextMenu'") {
    throw 'Explorer parent must point to a separate cascading menu definition using a registry string value.'
}
if (-not $source.Contains("New-ContextGroup `$rootChildren '02_OverwriteOriginal' 'Overwrite original' 'ACTextureConverter.OverwriteOriginalMenu'")) {
    throw 'The overwrite submenu must use its own noncanonical shell verb ID.'
}
if (-not $source.Contains("New-ContextGroup `$rootChildren '01_Backup' 'Overwrite with Backup'") -or -not $source.Contains("Set-ContextLeaf `$rootChildren '03_Open' 'Open AC Texture Converter' '-OpenWith'")) {
    throw 'Explorer entries must use explicit IDs to put conversions above the app launcher.'
}
if ($source.Contains("Convert to copy in DDS-Converted") -or $source.Contains('$copyChildren')) {
    throw 'The Explorer copy-to-folder submenu must not be registered.'
}
if ($source -notmatch "SetValue\('MultiSelectModel', 'Document'" -or $source -notmatch '-InputPath `\"%1`\"') {
    throw 'Explorer commands must pass the selected file through the documented %1 placeholder.'
}
if ($source -match '\\ExtendedSubCommandsKey\\Shell' -or $source -notmatch 'function New-MenuDefinition') {
    throw 'Explorer subcommands must be registered at the separate menu definition path.'
}
if ($source -notmatch 'Software\\Classes\\\$progId\\shell') {
    throw 'Explorer cascades must be registered under the .dds ProgID shell key.'
}
$contextFunction = ([regex]::Match($source, '(?s)function Set-ExplorerContextMenu.*?\n}\nLoad-FormatSettings')).Value
if ($contextFunction -notmatch "'AC Texture Converter\.exe'" -or $contextFunction -notmatch '\$UseExecutable.*\$Executable.*\$ScriptArguments') {
    throw 'Explorer commands must use the installed executable when it is present.'
}
$installer = Get-Content -LiteralPath (Join-Path $root 'Install.ps1') -Raw
$repair = Get-Content -LiteralPath (Join-Path $root 'Repair-ACTextureConverter.ps1') -Raw
$uninstaller = Get-Content -LiteralPath (Join-Path $root 'Uninstall-ACTextureConverter.ps1') -Raw
$launcherBat = Get-Content -LiteralPath (Join-Path $root 'Open-ACTextureConverter.bat') -Raw
$portableBuilder = Get-Content -LiteralPath (Join-Path $root 'Build-Portable.ps1') -Raw
if ($installer -notmatch 'AC Texture Converter Portable\\AC Texture Converter\.exe' -or $installer -notmatch "\$portableRoot 'texconv\.exe'" -or $installer -notmatch '\$portableTexconv' -or $installer -notmatch "'AC Texture Converter\.exe'") {
    throw 'The installer must use and copy the launcher and texconv included in the distribution.'
}
if ($repair -notmatch 'AC Texture Converter Portable\\AC Texture Converter\.exe' -or $repair -notmatch 'Copy-Item .*\$sourceExe.*\$targetExe' -or $repair -notmatch '\-RegisterContextMenu') {
    throw 'The repair tool must update the executable and re-register Explorer commands.'
}
if ($uninstaller -notmatch "'AC Texture Converter\.exe'") {
    throw 'The uninstaller safety allowlist must include the portable launcher.'
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
