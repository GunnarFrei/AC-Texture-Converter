$ErrorActionPreference = 'Stop'
$roots = @(
    @{ Path = (Join-Path $env:LOCALAPPDATA 'ACTextureConverter'); Expected = @('ACTextureConverter.ps1','Open-ACTextureConverter.bat','AC Texture Converter.exe','texconv.exe','LICENSE','ThirdPartyNotices.txt') },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'DDSForge'); Expected = @('DdsForge.ps1','Open-DDSForge.bat','texconv.exe') }
)
foreach ($entry in $roots) {
    if (Test-Path -LiteralPath $entry.Path) {
        $unexpected = @(Get-ChildItem -LiteralPath $entry.Path -Force | Where-Object { $_.Name -notin $entry.Expected })
        if ($unexpected.Count) { throw "The folder contains additional files and was left untouched for safety: $($entry.Path)" }
    }
}
$choiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.dds\UserChoice')
$progId = if ($choiceKey) { try { [string]$choiceKey.GetValue('ProgId') } finally { $choiceKey.Dispose() } } else { '' }
if ([string]::IsNullOrWhiteSpace($progId)) {
    $extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('.dds')
    $progId = if ($extensionKey) { try { [string]$extensionKey.GetValue('') } finally { $extensionKey.Dispose() } } else { '' }
}
$supportedInputExtensions = @('.dds','.png','.tga','.bmp','.jpg','.jpeg','.tif','.tiff','.hdr')
$shellRoots = @($supportedInputExtensions | ForEach-Object { "HKCU:\Software\Classes\SystemFileAssociations\$_\shell" })
$progIdShellRoots = @()
if (-not [string]::IsNullOrWhiteSpace($progId) -and -not $progId.StartsWith('\') -and -not $progId.EndsWith('\') -and $progId.Split('\') -notcontains '..') {
    $progIdShellRoots += "HKCU:\Software\Classes\$progId\shell"
}
$extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('.dds')
if ($extensionKey) {
    try { $fallbackProgId = [string]$extensionKey.GetValue('') }
    finally { $extensionKey.Dispose() }
    if (-not [string]::IsNullOrWhiteSpace($fallbackProgId) -and $fallbackProgId -ne $progId -and -not $fallbackProgId.StartsWith('\') -and -not $fallbackProgId.EndsWith('\') -and $fallbackProgId.Split('\') -notcontains '..') {
        $progIdShellRoots += "HKCU:\Software\Classes\$fallbackProgId\shell"
    }
}
$shellRoots += $progIdShellRoots
$shellRoots = @($shellRoots | Select-Object -Unique)
$keys = @($supportedInputExtensions | ForEach-Object { "HKCU:\Software\Classes\SystemFileAssociations\$_\shell\ACTextureConverter" })
$keys += 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell\DDSForge'
foreach ($shellRoot in $progIdShellRoots) {
    $keys += (Join-Path $shellRoot 'ACTextureConverter')
    $keys += (Join-Path $shellRoot 'DDSForge')
}
foreach ($key in $keys) { if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force } }
foreach ($shellRoot in $shellRoots) {
    if (Test-Path -LiteralPath $shellRoot) {
        Get-ChildItem -LiteralPath $shellRoot | Where-Object { $_.PSChildName.StartsWith('ACTextureConverter_',[StringComparison]::OrdinalIgnoreCase) } | Remove-Item -Recurse -Force
    }
}
$menuDefinitions = @('ACTextureConverter.ContextMenu','ACTextureConverter.ImageContextMenu','ACTextureConverter.ConvertMenu','ACTextureConverter.CopyMenu','ACTextureConverter.OverwriteMenu','ACTextureConverter.OverwriteOriginalMenu','ACTextureConverter.BackupMenu')
foreach ($definition in $menuDefinitions) {
    $definitionPath = "HKCU:\Software\Classes\$definition"
    if (Test-Path -LiteralPath $definitionPath) {
        $owner = (Get-ItemProperty -LiteralPath $definitionPath -Name 'ACTextureConverterOwner' -ErrorAction SilentlyContinue).ACTextureConverterOwner
        if ($owner -eq 'AC Texture Converter') { Remove-Item -LiteralPath $definitionPath -Recurse -Force }
    }
}
$commandStoreRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
if (Test-Path -LiteralPath $commandStoreRoot) {
    Get-ChildItem -LiteralPath $commandStoreRoot | Where-Object { $_.PSChildName.StartsWith('ACTextureConverter.',[StringComparison]::OrdinalIgnoreCase) } | Remove-Item -Recurse -Force
}
foreach ($entry in $roots) { if (Test-Path -LiteralPath $entry.Path) { Remove-Item -LiteralPath $entry.Path -Recurse -Force } }
Write-Host 'AC Texture Converter has been removed. Texconv and user format settings remain installed.'
Write-Host 'Press any key to close this window.'
try { [void][Console]::ReadKey($true) } catch { }

