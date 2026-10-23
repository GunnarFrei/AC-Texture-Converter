param(
    [string[]]$InputPath = @(),
    [string]$Format = 'BC7_UNORM',
    [string]$OutputDirectory = '',
    [string]$Mipmaps = 'full',
    [string]$InputListFile = '',
    [switch]$Overwrite,
    [switch]$BackupOriginals,
    [switch]$OpenWith,
    [ValidateSet('Copy','Overwrite','Backup')][string]$ShellMode = '',
    [switch]$RegisterContextMenu,
    [string]$ContextMenuTargetScript = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

class ACTextureListComparer : System.Collections.IComparer {
    [int]$Column
    [bool]$Ascending
    ACTextureListComparer([int]$column, [bool]$ascending) { $this.Column = $column; $this.Ascending = $ascending }
    [int] Compare([object]$x, [object]$y) {
        $left = [string]$x.SubItems[$this.Column].Text
        $right = [string]$y.SubItems[$this.Column].Text
        if ($this.Column -eq 2 -and $left -match '^(\d+)\s*[×x]\s*(\d+)$') {
            $leftWidth = [long]$Matches[1]; $leftHeight = [long]$Matches[2]
            if ($right -match '^(\d+)\s*[×x]\s*(\d+)$') {
                $rightWidth = [long]$Matches[1]; $rightHeight = [long]$Matches[2]
            $leftArea = $leftWidth * $leftHeight
            $rightArea = $rightWidth * $rightHeight
            if ($leftArea -lt $rightArea) { $result = -1 } elseif ($leftArea -gt $rightArea) { $result = 1 }
            elseif ($leftWidth -lt $rightWidth) { $result = -1 } elseif ($leftWidth -gt $rightWidth) { $result = 1 }
            elseif ($leftHeight -lt $rightHeight) { $result = -1 } elseif ($leftHeight -gt $rightHeight) { $result = 1 }
            else { $result = 0 }
            if ($this.Ascending) { return $result }
            return -$result
            }
        }
        if ($this.Column -eq 3) {
            $leftSize = [long]$x.SubItems[3].Tag
            $rightSize = [long]$y.SubItems[3].Tag
            if ($leftSize -lt $rightSize) { $result = -1 } elseif ($leftSize -gt $rightSize) { $result = 1 } else { $result = 0 }
            if ($this.Ascending) { return $result }
            return -$result
        }
        if ($this.Column -eq 4) {
            $leftDate = [long]$x.SubItems[4].Tag
            $rightDate = [long]$y.SubItems[4].Tag
            if ($leftDate -lt $rightDate) { $result = -1 } elseif ($leftDate -gt $rightDate) { $result = 1 } else { $result = 0 }
            if ($this.Ascending) { return $result }
            return -$result
        }
        $result = [string]::Compare($left, $right, [StringComparison]::CurrentCultureIgnoreCase)
        if ($this.Ascending) { return $result }
        return -$result
    }
}

if (-not [string]::IsNullOrWhiteSpace($InputListFile)) {
    $listPath = [IO.Path]::GetFullPath($InputListFile)
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { throw "The Explorer selection list is missing: $listPath" }
    try {
        $InputPath = @([IO.File]::ReadAllLines($listPath, (New-Object System.Text.UTF8Encoding($false))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } finally {
        Remove-Item -LiteralPath $listPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $InputPath.Count) { throw 'The Explorer selection list contains no file paths.' }
}

$script:BaseFormats = [ordered]@{
    'BC1 (DXT1, opaque RGB; ignores alpha)' = 'BC1_UNORM'
    'BC2 (DXT3, alpha)' = 'BC2_UNORM'
    'BC3 (DXT5, alpha)' = 'BC3_UNORM'
    'BC7 RGBA (preserve alpha)' = 'BC7_UNORM'
    'BC7 (opaque; remove transparency)' = 'BC7_OPAQUE'
    'Uncompressed RGBA8 (32-bit)' = 'R8G8B8A8_UNORM'
    'A8L8 (R=luminance, A=alpha)' = 'A8L8'
}
$script:OptionalFormats = [ordered]@{
    'BC4 (grayscale/channel)' = 'BC4_UNORM'
    'BC5 (normal maps/RG)' = 'BC5_UNORM'
    'BC6H (HDR, no alpha)' = 'BC6H_UF16'
}
$script:FormatHints = @{
    'BC1_UNORM' = 'Opaque RGB at a small file size. Source alpha is ignored; use BC3 for transparency.'
    'BC2_UNORM' = 'Explicit 4-bit alpha; mainly for legacy workflows. BC3 is usually more versatile.'
    'BC3_UNORM' = 'DXT5 general-purpose format with interpolated alpha; a strong legacy AC choice.'
    'BC4_UNORM' = 'Single-channel grayscale or data masks; not a color texture format.'
    'BC5_UNORM' = 'Two-channel data, commonly XY normal maps. Use only when the material shader expects this layout.'
    'BC6H_UF16' = 'HDR RGB without alpha; for HDR environment or lighting textures, not typical car textures.'
    'BC7_UNORM' = "High-quality lossy RGB/RGBA compression. It can retain alpha and usually handles smooth gradients and alpha detail better than BC1/BC3, but is not pixel-exact.`r`nRequires CSP 0.1.74-preview3 (build 1434) or newer."
    'BC7_OPAQUE' = "High-quality lossy opaque BC7; source alpha is removed before compression. Usually handles smooth color gradients better than BC1/BC3, but is not pixel-exact.`r`nRequires CSP 0.1.74-preview3 (build 1434) or newer."
    'R8G8B8A8_UNORM' = 'Uncompressed 32-bit RGBA; avoids block artifacts but creates larger files.'
    'A8L8' = 'Legacy grayscale plus alpha: luminance comes from R; an existing A8L8/R8G8 source keeps its second channel as alpha. Use where the AC material expects AL 8.8.'
}
$script:SettingsPath = Join-Path (Join-Path $env:APPDATA 'DDSForge') 'settings.json'
$script:SupportedInputExtensions = @('.dds','.png','.tga','.bmp','.jpg','.jpeg','.tif','.tiff','.hdr')
$script:SupportedImageInputExtensions = @($script:SupportedInputExtensions | Where-Object { $_ -ne '.dds' })
$script:EnabledFormats = @($script:BaseFormats.Values)
$script:Formats = [ordered]@{}

function Set-FormatList {
    $script:Formats = [ordered]@{}
    foreach ($entry in $script:BaseFormats.GetEnumerator()) { if ($script:EnabledFormats -contains $entry.Value) { $script:Formats[$entry.Key] = $entry.Value } }
    foreach ($entry in $script:OptionalFormats.GetEnumerator()) { if ($script:EnabledFormats -contains $entry.Value) { $script:Formats[$entry.Key] = $entry.Value } }
}

function Get-DdsProgId {
    $choiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.dds\UserChoice')
    if ($choiceKey) {
        try { $progId = [string]$choiceKey.GetValue('ProgId') }
        finally { $choiceKey.Dispose() }
    }
    if ([string]::IsNullOrWhiteSpace($progId)) {
        $extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('.dds')
        if ($extensionKey) {
            try { $progId = [string]$extensionKey.GetValue('') }
            finally { $extensionKey.Dispose() }
        }
    }
    if ([string]::IsNullOrWhiteSpace($progId) -or $progId.StartsWith('\') -or $progId.EndsWith('\') -or $progId.Split('\') -contains '..') {
        throw 'Windows has no usable .dds association identifier.'
    }
    return $progId
}

function Get-DdsProgIds {
    $progIds = @()
    try { $progIds += Get-DdsProgId } catch { }
    $extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('.dds')
    if ($extensionKey) {
        try { $fallback = [string]$extensionKey.GetValue('') }
        finally { $extensionKey.Dispose() }
        if (-not [string]::IsNullOrWhiteSpace($fallback) -and $fallback -notin $progIds) { $progIds += $fallback }
    }
    return $progIds
}

function Get-ContextMenuTargets {
    $targets = @($script:SupportedInputExtensions | ForEach-Object {
        [pscustomobject]@{ ShellPath = "HKCU:\Software\Classes\SystemFileAssociations\$_\shell"; IsDds = ($_ -eq '.dds') }
    })
    foreach ($progId in (Get-DdsProgIds)) {
        $targets += [pscustomobject]@{ ShellPath = "HKCU:\Software\Classes\$progId\shell"; IsDds = $true }
    }
    return @($targets | Group-Object ShellPath | ForEach-Object { $_.Group[0] })
}

function Get-ContextMenuShellPaths {
    return @(Get-ContextMenuTargets | ForEach-Object { $_.ShellPath })
}

function Load-FormatSettings {
    $script:EnabledFormats = @($script:BaseFormats.Values)
    if (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf) {
        try {
            $settings = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
            if ($null -ne $settings.enabledFormats) {
                $requested = @($settings.enabledFormats)
                $available = @($script:BaseFormats.Values) + @($script:OptionalFormats.Values)
                $script:EnabledFormats = @($requested | Where-Object { $_ -in $available } | Select-Object -Unique)
            } elseif ($null -ne $settings.enabledOptionalFormats) {
                $requested = @($settings.enabledOptionalFormats)
                $script:EnabledFormats = @($script:BaseFormats.Values) + @($requested | Where-Object { $_ -in $script:OptionalFormats.Values } | Select-Object -Unique)
            }
        } catch {
            $script:EnabledFormats = @($script:BaseFormats.Values)
        }
    }
    Set-FormatList
}

function Save-FormatSettings([string[]]$SelectedFormats) {
    $available = @($script:BaseFormats.Values) + @($script:OptionalFormats.Values)
    $valid = @($SelectedFormats | Where-Object { $_ -in $available } | Select-Object -Unique)
    if (-not $valid.Count) { throw 'Select at least one output format.' }
    $parent = Split-Path -Parent $script:SettingsPath
    [void][IO.Directory]::CreateDirectory($parent)
    $json = @{ enabledFormats = $valid } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($script:SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    $script:EnabledFormats = $valid
    Set-FormatList
    $menuInstalled = @(Get-ContextMenuShellPaths | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'ACTextureConverter') }).Count -gt 0
    if ($menuInstalled) { Set-ExplorerContextMenu }
}

function Set-ExplorerContextMenu([string]$TargetScript = '') {
    $menuTargets = @(Get-ContextMenuTargets)
    foreach ($target in $menuTargets) {
        $shellPath = $target.ShellPath
        foreach ($existing in @(Get-ChildItem -LiteralPath $shellPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'ACTextureConverter' -or $_.PSChildName.StartsWith('ACTextureConverter_',[StringComparison]::OrdinalIgnoreCase) })) {
            Remove-Item -LiteralPath $existing.PSPath -Recurse -Force
        }
        $associationPath = $shellPath -replace '\\shell$',''
        $handlerPath = Join-Path $associationPath 'shellex\ContextMenuHandlers\ACTextureConverter'
        if (Test-Path -LiteralPath $handlerPath) {
            $handlerOwner = (Get-ItemProperty -LiteralPath $handlerPath -Name 'ACTextureConverterOwner' -ErrorAction SilentlyContinue).ACTextureConverterOwner
            $handlerClsid = (Get-ItemProperty -LiteralPath $handlerPath -ErrorAction SilentlyContinue).'(default)'
            if ($handlerOwner -ne 'AC Texture Converter' -and $handlerClsid -ne '{91A658F4-E8EC-4C52-8AD8-51D0FB40561D}') {
                throw "Refusing to replace an unrelated Explorer handler: $handlerPath"
            }
            Remove-Item -LiteralPath $handlerPath -Recurse -Force
        }
    }
    # Remove entries from the previous SubCommands/CommandStore implementation.
    $commandStoreRelative = 'Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
    $commandStorePath = "HKCU:\$commandStoreRelative"
    foreach ($existing in @(Get-ChildItem -LiteralPath $commandStorePath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName.StartsWith('ACTextureConverter.',[StringComparison]::OrdinalIgnoreCase) })) {
        Remove-Item -LiteralPath $existing.PSPath -Recurse -Force
    }
    # Remove old definitions too, so the retired copy submenu cannot linger.
    $menuDefinitions = @('ACTextureConverter.ContextMenu','ACTextureConverter.ImageContextMenu','ACTextureConverter.ConvertMenu','ACTextureConverter.CopyMenu','ACTextureConverter.OverwriteMenu','ACTextureConverter.OverwriteOriginalMenu','ACTextureConverter.BackupMenu')
    foreach ($definition in $menuDefinitions) {
        $definitionPath = "HKCU:\Software\Classes\$definition"
        if (Test-Path -LiteralPath $definitionPath) {
            $owner = (Get-ItemProperty -LiteralPath $definitionPath -Name 'ACTextureConverterOwner' -ErrorAction SilentlyContinue).ACTextureConverterOwner
            if ($owner -ne 'AC Texture Converter') { throw "Refusing to replace an unrelated Explorer menu definition: $definitionPath" }
            Remove-Item -LiteralPath $definitionPath -Recurse -Force
        }
    }
    $scriptPath = if ([string]::IsNullOrWhiteSpace($TargetScript)) { Join-Path $PSScriptRoot 'ACTextureConverter.ps1' } else { [IO.Path]::GetFullPath($TargetScript) }
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "The context-menu target script does not exist: $scriptPath" }
    $installRoot = Split-Path -Parent $scriptPath
    $extensionDll = Join-Path $installRoot 'ACTextureConverterShellExtension.dll'
    if (-not (Test-Path -LiteralPath $extensionDll -PathType Leaf)) { throw "The Explorer integration is missing: $extensionDll. Rebuild or repair the installation." }

    $clsid = '{91A658F4-E8EC-4C52-8AD8-51D0FB40561D}'
    $clsidPath = "Software\Classes\CLSID\$clsid"
    $existingClass = "HKCU:\$clsidPath"
    if (Test-Path -LiteralPath $existingClass) {
        $owner = (Get-ItemProperty -LiteralPath $existingClass -Name 'ACTextureConverterOwner' -ErrorAction SilentlyContinue).ACTextureConverterOwner
        if ($owner -ne 'AC Texture Converter') { throw "Refusing to replace an unrelated COM class: $existingClass" }
        Remove-Item -LiteralPath $existingClass -Recurse -Force
    }
    $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($extensionDll)
    $classKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($clsidPath)
    $classKey.SetValue('', 'AC Texture Converter Explorer Integration', [Microsoft.Win32.RegistryValueKind]::String)
    $classKey.SetValue('ACTextureConverterOwner', 'AC Texture Converter', [Microsoft.Win32.RegistryValueKind]::String)
    $classKey.Dispose()
    $inprocKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$clsidPath\InprocServer32")
    $inprocKey.SetValue('', 'mscoree.dll', [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.SetValue('ThreadingModel', 'Both', [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.SetValue('Class', 'ACTextureConverter.ShellExtension', [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.SetValue('Assembly', $assemblyName.FullName, [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.SetValue('RuntimeVersion', 'v4.0.30319', [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.SetValue('CodeBase', ([Uri]$extensionDll).AbsoluteUri, [Microsoft.Win32.RegistryValueKind]::String)
    $inprocKey.Dispose()
    foreach ($target in $menuTargets | Where-Object { $_.ShellPath -like 'HKCU:\Software\Classes\SystemFileAssociations\*' }) {
        $associationPath = $target.ShellPath -replace '\\shell$',''
        $handlerPath = "$associationPath\shellex\ContextMenuHandlers\ACTextureConverter"
        $handlerKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($handlerPath.Substring('HKCU:\'.Length))
        $handlerKey.SetValue('', $clsid, [Microsoft.Win32.RegistryValueKind]::String)
        $handlerKey.SetValue('ACTextureConverterOwner', 'AC Texture Converter', [Microsoft.Win32.RegistryValueKind]::String)
        $handlerKey.Dispose()
    }
    if (-not ('ACTextureConverter.ShellNotify' -as [type])) {
        Add-Type -Namespace ACTextureConverter -Name ShellNotify -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(uint eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
    }
    [ACTextureConverter.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}
Load-FormatSettings

function Find-Texconv {
    $near = Join-Path $PSScriptRoot 'texconv.exe'
    if (Test-Path -LiteralPath $near) { return $near }
    $cmd = Get-Command texconv.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Quote-Argument([string]$Value) {
    '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Resolve-MipCount([string]$MipSetting) {
    if ($MipSetting -eq 'full') { return '0' }
    if ($MipSetting -eq 'none') { return '1' }
    if ($MipSetting -match '^\d+$' -and [int]$MipSetting -ge 1) { return $MipSetting }
    throw 'Mipmaps must be full, none, or a positive number.'
}

function Resolve-OutputDirectory([string]$InputFile, [string]$ConfiguredDirectory, [bool]$SafeCopyOutput = $false) {
    if ($SafeCopyOutput) { return Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InputFile))) 'DDS-Converted' }
    if ([string]::IsNullOrWhiteSpace($ConfiguredDirectory)) {
        return [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InputFile))
    }
    return [IO.Path]::GetFullPath($ConfiguredDirectory)
}

function Get-OutputDdsPath([string]$InputFile, [string]$OutputDirectory) {
    $extension = [IO.Path]::GetExtension($InputFile)
    if ($extension -ine '.dds') { $extension = '.dds' }
    return Join-Path $OutputDirectory (([IO.Path]::GetFileNameWithoutExtension($InputFile)) + $extension)
}

function Resolve-TexconvSwizzle([string]$DxgiFormat, [bool]$ForceOpaque = $false) {
    if ($ForceOpaque -or $DxgiFormat -eq 'BC1_UNORM') { return 'rgb1' }
    return ''
}

function Test-ExpandA8L8Luminance([string]$DxgiFormat, [bool]$IsA8L8Source) {
    return ($IsA8L8Source -and $DxgiFormat -in @('BC1_UNORM','BC2_UNORM','BC3_UNORM','BC6H_UF16','BC7_UNORM','R8G8B8A8_UNORM'))
}

function Resolve-A8L8InputSwizzle([string]$FourCC, [uint32]$DxgiFormat, [uint32]$PixelFlags, [uint32]$BitsPerPixel, [uint32]$RedMask, [uint32]$AlphaMask) {
    # DirectXTex loads legacy A8L8 and DXGI R8G8_UNORM as R/G, where G carries alpha.
    if (($FourCC -eq 'DX10' -and $DxgiFormat -eq 49) -or (($PixelFlags -band 0x20000) -ne 0 -and $BitsPerPixel -eq 16 -and $RedMask -eq 0xFF -and $AlphaMask -eq 0xFF00)) { return 'rg' }
    # RGBA and ordinary image inputs carry alpha in A.
    return 'ra'
}

$script:DdsFormatCache = @{}
function Get-InputFormatInfo([string]$InputFile) {
    $extension = [IO.Path]::GetExtension($InputFile).TrimStart('.').ToUpperInvariant()
    if ($extension -ne 'DDS') { return [pscustomobject]@{ Label = $extension; Detail = "$extension image" } }
    try {
        $fileInfo = Get-Item -LiteralPath $InputFile -ErrorAction Stop
        $cacheKey = "$InputFile|$($fileInfo.Length)|$($fileInfo.LastWriteTimeUtc.Ticks)"
        if ($script:DdsFormatCache.ContainsKey($cacheKey)) { return $script:DdsFormatCache[$cacheKey] }
        $stream = [IO.File]::Open($InputFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            if ($stream.Length -lt 128) { throw 'DDS header is incomplete.' }
            $header = New-Object byte[] 148
            $read = $stream.Read($header, 0, $header.Length)
        } finally { $stream.Dispose() }
        if ([Text.Encoding]::ASCII.GetString($header, 0, 4) -ne 'DDS ') { throw 'DDS magic is missing.' }
        $fourCC = [Text.Encoding]::ASCII.GetString($header, 84, 4)
        $pixelFlags = [BitConverter]::ToUInt32($header, 80)
        $bits = [BitConverter]::ToUInt32($header, 88)
        $red = [BitConverter]::ToUInt32($header, 92)
        $green = [BitConverter]::ToUInt32($header, 96)
        $blue = [BitConverter]::ToUInt32($header, 100)
        $alpha = [BitConverter]::ToUInt32($header, 104)
        $label = $null
        $detail = $null
        if ($fourCC -eq 'DX10') {
            if ($read -lt 148) { throw 'DDS DX10 header is incomplete.' }
            $dxgi = [BitConverter]::ToUInt32($header, 128)
            $dxgiNames = @{
                10='R16G16B16A16_FLOAT'; 11='R16G16B16A16_UNORM'; 24='R10G10B10A2_UNORM';
                28='R8G8B8A8_UNORM'; 29='R8G8B8A8_UNORM_SRGB'; 49='R8G8_UNORM'; 61='R8_UNORM';
                71='BC1_UNORM'; 72='BC1_UNORM_SRGB'; 74='BC2_UNORM'; 75='BC2_UNORM_SRGB';
                77='BC3_UNORM'; 78='BC3_UNORM_SRGB'; 80='BC4_UNORM'; 81='BC4_SNORM';
                83='BC5_UNORM'; 84='BC5_SNORM'; 87='B8G8R8A8_UNORM'; 88='B8G8R8X8_UNORM';
                95='BC6H_UF16'; 96='BC6H_SF16'; 98='BC7_UNORM'; 99='BC7_UNORM_SRGB'
            }
            $detail = if ($dxgiNames.ContainsKey([int]$dxgi)) { $dxgiNames[[int]$dxgi] } else { "DXGI format $dxgi" }
            $label = switch ($dxgi) {
                { $_ -in 71,72 } { 'BC1'; break } { $_ -in 74,75 } { 'BC2'; break }
                { $_ -in 77,78 } { 'BC3'; break } 80 { 'BC4'; break } 81 { 'BC4 SNORM'; break }
                83 { 'BC5'; break } 84 { 'BC5 SNORM'; break } { $_ -in 95,96 } { 'BC6H'; break }
                { $_ -in 98,99 } { 'BC7'; break } 49 { 'R8G8'; break } 61 { 'R8'; break }
                { $_ -in 28,29 } { 'A8B8G8R8'; break } 87 { 'A8R8G8B8'; break } 88 { 'X8R8G8B8'; break }
                default { $detail }
            }
            if ($dxgi -in 72,75,78,29,99) { $detail += ' (sRGB)' }
        } elseif (($pixelFlags -band 0x4) -ne 0) {
            $legacy = @{
                'DXT1'=@('BC1','BC1 / DXT1'); 'DXT2'=@('BC2','BC2 / DXT2 (premultiplied alpha)');
                'DXT3'=@('BC2','BC2 / DXT3'); 'DXT4'=@('BC3','BC3 / DXT4 (premultiplied alpha)');
                'DXT5'=@('BC3','BC3 / DXT5'); 'ATI1'=@('BC4','BC4 / ATI1'); 'BC4U'=@('BC4','BC4 UNORM');
                'BC4S'=@('BC4 SNORM','BC4 SNORM'); 'ATI2'=@('BC5','BC5 / ATI2'); 'BC5U'=@('BC5','BC5 UNORM');
                'BC5S'=@('BC5 SNORM','BC5 SNORM'); 'BC6H'=@('BC6H','BC6H'); 'BC7 '=@('BC7','BC7');
                'A8L8'=@('A8L8','A8L8 (8-bit luminance + 8-bit alpha)')
            }
            if ($legacy.ContainsKey($fourCC)) { $label = $legacy[$fourCC][0]; $detail = $legacy[$fourCC][1] }
            else { $label = $fourCC.Trim(); $detail = "DDS FourCC $($fourCC.Trim())" }
        } elseif ($bits -eq 16 -and $red -eq 0xFF -and $alpha -eq 0xFF00) {
            $label = 'A8L8'; $detail = 'A8L8 (8-bit luminance + 8-bit alpha)'
        } elseif ($bits -eq 32 -and $red -eq 0xFF -and $green -eq 0xFF00 -and $blue -eq 0xFF0000 -and $alpha -eq 0xFF000000) {
            $label = 'A8B8G8R8'; $detail = 'Uncompressed 32-bit 8.8.8.8; R8G8B8A8 byte order'
        } elseif ($bits -eq 32 -and $red -eq 0xFF0000 -and $green -eq 0xFF00 -and $blue -eq 0xFF -and $alpha -eq 0xFF000000) {
            $label = 'A8R8G8B8'; $detail = 'Uncompressed 32-bit 8.8.8.8; B8G8R8A8 byte order'
        } elseif ($bits -eq 24) {
            $label = 'R8G8B8'; $detail = 'Uncompressed 24-bit RGB'
        } elseif ($bits -eq 32 -and $alpha -ne 0) {
            $label = 'A8R8G8B8'; $detail = 'Uncompressed 32-bit 8.8.8.8 (channel masks not recognized)'
        } elseif (($pixelFlags -band 0x20000) -ne 0) {
            $label = "L$bits"; $detail = "Uncompressed $bits-bit luminance"
        } elseif (($pixelFlags -band 0x2) -ne 0) {
            $label = "A$bits"; $detail = "Uncompressed $bits-bit alpha"
        } else {
            $label = "RGB$bits"; $detail = "Uncompressed $bits-bit RGB"
        }
        $result = [pscustomobject]@{ Label = $label; Detail = $detail }
        $script:DdsFormatCache[$cacheKey] = $result
        return $result
    } catch {
        return [pscustomobject]@{ Label = 'DDS?'; Detail = "Could not read DDS format: $($_.Exception.Message)" }
    }
}

$script:ResolutionCache = @{}
function Get-InputResolutionInfo([string]$InputFile) {
    try {
        $fileInfo = Get-Item -LiteralPath $InputFile -ErrorAction Stop
        $cacheKey = "$InputFile|$($fileInfo.Length)|$($fileInfo.LastWriteTimeUtc.Ticks)"
        if ($script:ResolutionCache.ContainsKey($cacheKey)) { return $script:ResolutionCache[$cacheKey] }
        $extension = [IO.Path]::GetExtension($InputFile).ToLowerInvariant()
        $width = 0; $height = 0
        if ($extension -eq '.dds') {
            $stream = [IO.File]::Open($InputFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                if ($stream.Length -lt 128) { throw 'DDS header is incomplete.' }
                $header = New-Object byte[] 128
                [void]$stream.Read($header, 0, $header.Length)
            } finally { $stream.Dispose() }
            if ([Text.Encoding]::ASCII.GetString($header, 0, 4) -ne 'DDS ') { throw 'DDS magic is missing.' }
            $height = [int][BitConverter]::ToUInt32($header, 12)
            $width = [int][BitConverter]::ToUInt32($header, 16)
        } elseif ($extension -eq '.tga') {
            $header = New-Object byte[] 18
            $stream = [IO.File]::Open($InputFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { if ($stream.Read($header, 0, $header.Length) -lt 18) { throw 'TGA header is incomplete.' } } finally { $stream.Dispose() }
            $width = [int][BitConverter]::ToUInt16($header, 12)
            $height = [int][BitConverter]::ToUInt16($header, 14)
        } elseif ($extension -eq '.hdr') {
            $reader = New-Object IO.StreamReader($InputFile, [Text.Encoding]::ASCII, $true, 4096, $false)
            try {
                for ($lineIndex = 0; $lineIndex -lt 80; $lineIndex++) {
                    $line = $reader.ReadLine()
                    if ($null -eq $line) { break }
                    if ($line -match '^\s*[+-]Y\s+(\d+)\s+[+-]X\s+(\d+)\s*$') { $height = [int]$Matches[1]; $width = [int]$Matches[2]; break }
                }
            } finally { $reader.Dispose() }
        } else {
            $image = [Drawing.Image]::FromFile($InputFile)
            try { $width = [int]$image.Width; $height = [int]$image.Height } finally { $image.Dispose() }
        }
        if ($width -le 0 -or $height -le 0) { throw 'Image dimensions could not be read.' }
        $aligned = (($width % 4) -eq 0 -and ($height % 4) -eq 0)
        $note = if ($aligned) { 'Both dimensions align to 4×4 blocks.' } else { 'Not aligned to 4×4 BC compression blocks; check compatibility with your target pipeline.' }
        $result = [pscustomobject]@{ Text = "$width × $height"; Width = $width; Height = $height; Known = $true; IsBlockAligned = $aligned; Detail = $note }
        $script:ResolutionCache[$cacheKey] = $result
        return $result
    } catch {
        return [pscustomobject]@{ Text = 'Unknown'; Width = 0; Height = 0; Known = $false; IsBlockAligned = $false; Detail = "Could not read image dimensions: $($_.Exception.Message)" }
    }
}

function Get-AssettoCorsaInputStatus([string]$InputFile, $FormatInfo) {
    $extension = [IO.Path]::GetExtension($InputFile).ToLowerInvariant()
    if ($extension -eq '.dds') {
        switch -Regex ($FormatInfo.Label) {
            '^(BC1|BC2|BC3|A8L8|A8R8G8B8|A8B8G8R8|X8R8G8B8|R8G8B8)$' { return [pscustomobject]@{ Status = 'AC compatible'; Color = [Drawing.Color]::Empty; Detail = 'DDS format is usable in the AC texture workflow; 8.8.8.8 is recommended for sensitive gradients and alpha.' } }
            '^BC7$' { return [pscustomobject]@{ Status = 'CSP required'; Color = [Drawing.Color]::Plum; Detail = 'Requires Custom Shaders Patch 0.1.74-preview3 (build 1434) or newer.' } }
            default { return [pscustomobject]@{ Status = 'Check format'; Color = [Drawing.Color]::Khaki; Detail = 'This DDS format is not listed in the standard AC texture guidelines; check game/CSP support.' } }
        }
    }
    if ($extension -in @('.png','.jpg','.jpeg')) {
        return [pscustomobject]@{ Status = 'DDS recommended'; Color = [Drawing.Color]::LightSkyBlue; Detail = 'The AC editor can use this image type, but DDS is recommended for in-game textures.' }
    }
    if ($extension -in @('.tga','.bmp','.tif','.tiff','.hdr')) {
        $detail = if ($extension -eq '.tga') { 'TGA may import/export in the editor but can crash the game on load. Convert to DDS.' } else { 'This image type is not listed as supported for AC textures. Convert to DDS.' }
        return [pscustomobject]@{ Status = 'Convert to DDS'; Color = [Drawing.Color]::LightCoral; Detail = $detail }
    }
    return [pscustomobject]@{ Status = 'Check format'; Color = [Drawing.Color]::Empty; Detail = 'Compatibility is not classified.' }
}

function Add-InputFileRow($ListView, [string]$InputFile) {
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($InputFile)
    foreach ($existing in $ListView.Items) { if ([string]$existing.Tag -ieq $fullPath) { return $false } }
    $info = Get-InputFormatInfo $fullPath
    $resolution = Get-InputResolutionInfo $fullPath
    $compatibility = Get-AssettoCorsaInputStatus $fullPath $info
    $fileItem = Get-Item -LiteralPath $fullPath
    $fileSize = [long]$fileItem.Length
    if ($fileSize -lt 1KB) { $fileSizeText = "$fileSize B" }
    elseif ($fileSize -lt 1MB) { $fileSizeText = ([Math]::Round($fileSize / 1KB, 1)).ToString('0.0', [Globalization.CultureInfo]::CurrentCulture) + ' KB' }
    elseif ($fileSize -lt 1GB) { $fileSizeText = ([Math]::Round($fileSize / 1MB, 1)).ToString('0.0', [Globalization.CultureInfo]::CurrentCulture) + ' MB' }
    else { $fileSizeText = ([Math]::Round($fileSize / 1GB, 1)).ToString('0.0', [Globalization.CultureInfo]::CurrentCulture) + ' GB' }
    $row = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileName($fullPath))
    [void]$row.SubItems.Add($info.Label)
    [void]$row.SubItems.Add($resolution.Text)
    $sizeSubItem = $row.SubItems.Add($fileSizeText)
    $sizeSubItem.Tag = $fileSize
    $dateSubItem = $row.SubItems.Add($fileItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    $dateSubItem.Tag = [long]$fileItem.LastWriteTime.Ticks
    [void]$row.SubItems.Add($fullPath)
    [void]$row.SubItems.Add($compatibility.Status)
    $row.Tag = $fullPath
    $row.UseItemStyleForSubItems = $false
    $row.ToolTipText = "$fullPath`r`nFormat: $($info.Detail)`r`nResolution: $($resolution.Detail)`r`n$($compatibility.Detail)"
    if ($compatibility.Color -ne [Drawing.Color]::Empty) { $row.BackColor = $compatibility.Color }
    if ($resolution.Known -and -not $resolution.IsBlockAligned) { $row.SubItems[2].BackColor = [Drawing.Color]::LightCoral }
    [void]$ListView.Items.Add($row)
    return $true
}

function Get-DroppedSupportedFilePaths([string]$DroppedPath) {
    $supportedExtensions = $script:SupportedInputExtensions
    $path = [IO.Path]::GetFullPath($DroppedPath)
    if ([IO.File]::Exists($path)) {
        if ([IO.Path]::GetExtension($path).ToLowerInvariant() -in $supportedExtensions) { return ,$path }
        return @()
    }
    if (-not [IO.Directory]::Exists($path)) { return @() }

    $results = New-Object 'System.Collections.Generic.List[string]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $pending.Push($path)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        if (-not $visited.Add($directory)) { continue }
        try {
            foreach ($file in [IO.Directory]::GetFiles($directory)) {
                if ([IO.Path]::GetExtension($file).ToLowerInvariant() -in $supportedExtensions) { $results.Add($file) }
            }
        } catch { }
        try {
            foreach ($child in [IO.Directory]::GetDirectories($directory)) {
                try {
                    if (([IO.File]::GetAttributes($child) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $pending.Push($child) }
                } catch { }
            }
        } catch { }
    }
    return $results.ToArray()
}

function Get-A8L8InputSwizzle([string]$InputFile) {
    if ([IO.Path]::GetExtension($InputFile) -ine '.dds') { return 'ra' }
    $stream = [IO.File]::OpenRead($InputFile)
    try {
        if ($stream.Length -lt 128) { return 'ra' }
        $header = New-Object byte[] 148
        $read = $stream.Read($header, 0, $header.Length)
        $fourCC = [Text.Encoding]::ASCII.GetString($header, 84, 4)
        $dxgiFormat = if ($fourCC -eq 'DX10' -and $read -ge 148) { [BitConverter]::ToUInt32($header, 128) } else { [uint32]0 }
        $pixelFlags = [BitConverter]::ToUInt32($header, 80)
        $bitsPerPixel = [BitConverter]::ToUInt32($header, 88)
        $redMask = [BitConverter]::ToUInt32($header, 92)
        $alphaMask = [BitConverter]::ToUInt32($header, 104)
        return Resolve-A8L8InputSwizzle $fourCC $dxgiFormat $pixelFlags $bitsPerPixel $redMask $alphaMask
    } finally { $stream.Dispose() }
}

function Convert-AllZeroAlphaTgaToPng([string]$InputFile, [string]$OutputFile) {
    # DirectXTex treats some TGA files whose entire alpha plane is zero as opaque.
    # Decode these explicitly and pass them through PNG, which preserves zero alpha.
    $bytes = [IO.File]::ReadAllBytes($InputFile)
    if ($bytes.Length -lt 18 -or $bytes[1] -ne 0 -or $bytes[16] -ne 32 -or ($bytes[17] -band 0x0F) -ne 8 -or $bytes[2] -notin @(2,10)) { return $false }
    $width = [int][BitConverter]::ToUInt16($bytes, 12)
    $height = [int][BitConverter]::ToUInt16($bytes, 14)
    if ($width -le 0 -or $height -le 0) { return $false }
    $pixelCount = [long]$width * $height
    $sourcePixels = New-Object byte[] ([long]$pixelCount * 4)
    $sourceIndex = 18 + [int]$bytes[0]
    $pixelIndex = 0
    if ($bytes[2] -eq 2) {
        $requiredBytes = $sourceIndex + ($pixelCount * 4)
        if ($requiredBytes -gt $bytes.Length) { return $false }
        [Array]::Copy($bytes, $sourceIndex, $sourcePixels, 0, $pixelCount * 4)
    } else {
        while ($pixelIndex -lt $pixelCount) {
            if ($sourceIndex -ge $bytes.Length) { return $false }
            $packet = [int]$bytes[$sourceIndex]
            $sourceIndex++
            $count = ($packet -band 0x7F) + 1
            if (($pixelIndex + $count) -gt $pixelCount) { return $false }
            if ($packet -band 0x80) {
                if (($sourceIndex + 4) -gt $bytes.Length) { return $false }
                for ($n = 0; $n -lt $count; $n++) { [Array]::Copy($bytes, $sourceIndex, $sourcePixels, $pixelIndex * 4, 4); $pixelIndex++ }
                $sourceIndex += 4
            } else {
                $byteCount = $count * 4
                if (($sourceIndex + $byteCount) -gt $bytes.Length) { return $false }
                [Array]::Copy($bytes, $sourceIndex, $sourcePixels, $pixelIndex * 4, $byteCount)
                $sourceIndex += $byteCount
                $pixelIndex += $count
            }
        }
    }
    for ($n = 3; $n -lt $sourcePixels.Length; $n += 4) { if ($sourcePixels[$n] -ne 0) { return $false } }

    $topOrigin = ($bytes[17] -band 0x20) -ne 0
    $rightOrigin = ($bytes[17] -band 0x10) -ne 0
    $bgra = New-Object byte[] ($pixelCount * 4)
    for ($sourcePixel = 0; $sourcePixel -lt $pixelCount; $sourcePixel++) {
        $row = [int][Math]::Floor($sourcePixel / $width)
        $column = $sourcePixel % $width
        $x = if ($rightOrigin) { $width - 1 - $column } else { $column }
        $y = if ($topOrigin) { $row } else { $height - 1 - $row }
        $targetPixel = ($y * $width) + $x
        [Array]::Copy($sourcePixels, $sourcePixel * 4, $bgra, $targetPixel * 4, 4)
    }

    $bitmap = New-Object Drawing.Bitmap($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $rectangle = New-Object Drawing.Rectangle(0, 0, $width, $height)
        $bitmapData = $bitmap.LockBits($rectangle, [Drawing.Imaging.ImageLockMode]::WriteOnly, $bitmap.PixelFormat)
        try { [Runtime.InteropServices.Marshal]::Copy($bgra, 0, $bitmapData.Scan0, $bgra.Length) }
        finally { $bitmap.UnlockBits($bitmapData) }
        $bitmap.Save($OutputFile, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
    return $true
}

function Invoke-Conversion([string[]]$Files, [string]$DxgiFormat, [string]$OutDir, [string]$MipSetting, [bool]$OverwriteExisting = $false, [bool]$BackupExisting = $false, [bool]$PerSourceSubfolder = $false, [int]$MaxDimension = 0) {
    $texconv = Find-Texconv
    if (-not $texconv) { throw 'texconv.exe was not found. Install Microsoft DirectXTex Texconv (see README).' }
    $forceOpaque = $DxgiFormat -eq 'BC7_OPAQUE'
    if ($forceOpaque) { $DxgiFormat = 'BC7_UNORM' }
    if ($DxgiFormat -notin @('BC1_UNORM','BC2_UNORM','BC3_UNORM','BC4_UNORM','BC5_UNORM','BC6H_UF16','BC7_UNORM','R8G8B8A8_UNORM','A8L8')) { throw "Unsupported format: $DxgiFormat" }
    if ($BackupExisting) { $OverwriteExisting = $true }
    $mipCount = Resolve-MipCount $MipSetting
    $files = @($Files | ForEach-Object { (Resolve-Path -LiteralPath $_ -ErrorAction Stop).Path })
    if (-not $files.Count) { throw 'No input files selected.' }
    $seenOutputs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $jobs = @()
    foreach ($file in $files) {
        $fileOutDir = Resolve-OutputDirectory $file $OutDir $PerSourceSubfolder
        [void][IO.Directory]::CreateDirectory($fileOutDir)
        $outputFile = Get-OutputDdsPath $file $fileOutDir
        if (-not $seenOutputs.Add($outputFile)) { throw "Input files share an output name. Nothing was overwritten: $outputFile" }
        if ((Test-Path -LiteralPath $outputFile -PathType Leaf) -and -not $OverwriteExisting) { throw "The output already exists. Enable overwrite to replace it: $outputFile" }
        if (Test-Path -LiteralPath $outputFile -PathType Container) { throw "An output folder already exists with the target filename: $outputFile" }
        $a8l8Source = (Get-A8L8InputSwizzle $file) -eq 'rg'
        $expandA8L8Luminance = Test-ExpandA8L8Luminance $DxgiFormat $a8l8Source
        $swizzle = Resolve-TexconvSwizzle $DxgiFormat $forceOpaque
        if ($DxgiFormat -eq 'A8L8') { $swizzle = Get-A8L8InputSwizzle $file }
        $resizeWidth = 0; $resizeHeight = 0
        if ($MaxDimension -gt 0) {
            $resolution = Get-InputResolutionInfo $file
            if ($resolution.Known -and [Math]::Max($resolution.Width, $resolution.Height) -gt $MaxDimension) {
                $scale = $MaxDimension / [double][Math]::Max($resolution.Width, $resolution.Height)
                $resizeWidth = [Math]::Max(1, [int][Math]::Round($resolution.Width * $scale))
                $resizeHeight = [Math]::Max(1, [int][Math]::Round($resolution.Height * $scale))
            }
        }
        $jobs += [pscustomobject]@{ Input = $file; OutputDirectory = $fileOutDir; OutputFile = $outputFile; Swizzle = $swizzle; ExpandA8L8Luminance = $expandA8L8Luminance; ResizeWidth = $resizeWidth; ResizeHeight = $resizeHeight }
    }
    $texconvFormat = if ($DxgiFormat -eq 'A8L8') { 'R8G8_UNORM' } else { $DxgiFormat }
    foreach ($group in @($jobs | Group-Object OutputDirectory, Swizzle, ExpandA8L8Luminance, ResizeWidth, ResizeHeight)) {
        $groupJobs = @($group.Group)
        $outputDirectory = $groupJobs[0].OutputDirectory
        $stageDir = Join-Path $outputDirectory ('.DDSForge-tmp-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stageDir)
        try {
            $texconvInputs = @()
            foreach ($job in $groupJobs) {
                $inputForTexconv = $job.Input
                if ([IO.Path]::GetExtension($job.Input) -ieq '.tga') {
                    $intermediate = Join-Path $stageDir ([IO.Path]::GetFileNameWithoutExtension($job.Input) + '.png')
                    if (Convert-AllZeroAlphaTgaToPng $job.Input $intermediate) { $inputForTexconv = $intermediate }
                }
                $texconvInputs += $inputForTexconv
            }
            $texconvArgs = @('-nologo', '-f', $texconvFormat, '-m', $mipCount, '-ft', 'dds', '-o', $stageDir)
            if ($groupJobs[0].ResizeWidth -gt 0 -and $groupJobs[0].ResizeHeight -gt 0) {
                $texconvArgs += @('-w', [string]$groupJobs[0].ResizeWidth, '-h', [string]$groupJobs[0].ResizeHeight)
            }
            if ($DxgiFormat -eq 'A8L8') { $texconvArgs += '-dx9' }
            if ($groupJobs[0].ExpandA8L8Luminance) { $texconvArgs += '-xlum' }
            $swizzle = [string]$groupJobs[0].Swizzle
            if ($swizzle) { $texconvArgs += '--swizzle'; $texconvArgs += $swizzle }
            $texconvArgs += '-y'
            $texconvArgs += $texconvInputs
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $texconv
            $psi.Arguments = (($texconvArgs | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [Diagnostics.Process]::Start($psi)
            $proc.WaitForExit()
            if ($proc.ExitCode -ne 0) { throw "texconv exited with error code $($proc.ExitCode)." }
            foreach ($job in $groupJobs) {
                $stagedFile = Join-Path $stageDir ([IO.Path]::GetFileName($job.OutputFile))
                if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf)) { throw "texconv did not create the expected output file: $stagedFile" }
            }
            foreach ($job in $groupJobs) {
                $outputFile = $job.OutputFile
                $stagedFile = Join-Path $stageDir ([IO.Path]::GetFileName($outputFile))
                if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                    if ($BackupExisting) {
                        $backupDir = Join-Path $outputDirectory 'Backup'
                        [void][IO.Directory]::CreateDirectory($backupDir)
                $backupFile = Join-Path $backupDir ([IO.Path]::GetFileName($outputFile))
                if (Test-Path -LiteralPath $backupFile) {
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
                    $baseName = [IO.Path]::GetFileNameWithoutExtension($outputFile)
                    $extension = [IO.Path]::GetExtension($outputFile)
                    $backupFile = Join-Path $backupDir ("$baseName-$timestamp$extension")
                    $suffix = 1
                    while (Test-Path -LiteralPath $backupFile) {
                        $backupFile = Join-Path $backupDir ("$baseName-$timestamp-$suffix$extension")
                        $suffix++
                    }
                }
                        [IO.File]::Move($outputFile, $backupFile)
                        [IO.File]::Move($stagedFile, $outputFile)
                    } else {
                        $disposableBackup = Join-Path $stageDir ([Guid]::NewGuid().ToString('N') + '.bak')
                        [IO.File]::Replace($stagedFile, $outputFile, $disposableBackup)
                        [IO.File]::Delete($disposableBackup)
                    }
                } else {
                    [IO.File]::Move($stagedFile, $outputFile)
                }
            }
        } finally {
            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    return $files.Count
}

function Show-MainWindow([string[]]$InitialFiles) {
    if (-not ('DdsForge.NativeWindow' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace DdsForge {
    public static class NativeWindow {
        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
'@
    }
    $form = New-Object Windows.Forms.Form
$form.Text = 'AC Texture Converter'
    $form.Size = New-Object Drawing.Size(680, 580)
    $form.MinimumSize = New-Object Drawing.Size(600, 560)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)

    $title = New-Object Windows.Forms.Label
$title.Text = 'AC Texture Converter'
    $title.Font = New-Object Drawing.Font('Segoe UI Semibold', 19)
    $title.Location = New-Object Drawing.Point(22, 16); $title.Size = New-Object Drawing.Size(400, 36)
    $sub = New-Object Windows.Forms.Label
    $sub.Text = 'Drop DDS or image files here, generate mipmaps, and preserve transparency.'
    $sub.Location = New-Object Drawing.Point(24, 54); $sub.Size = New-Object Drawing.Size(610, 24)

    $list = New-Object Windows.Forms.ListView
    $list.Location = New-Object Drawing.Point(24, 92); $list.Size = New-Object Drawing.Size(490, 160)
    $list.Anchor = 'Top,Left'
    $list.View = [Windows.Forms.View]::Details
    $list.FullRowSelect = $true; $list.MultiSelect = $true; $list.HideSelection = $false; $list.GridLines = $true; $list.ShowItemToolTips = $true
    [void]$list.Columns.Add('File name', 135)
    [void]$list.Columns.Add('Input format', 95)
    [void]$list.Columns.Add('Resolution', 75)
    [void]$list.Columns.Add('File size', 75)
    [void]$list.Columns.Add('Modified', 125)
    [void]$list.Columns.Add('File path', 250)
    [void]$list.Columns.Add('AC compatibility', 105)
    $list.AllowColumnReorder = $true
    $list.AllowDrop = $true
    $InitialFiles | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object { [void](Add-InputFileRow $list $_) }
    $sortState = @{ Column = -1; Ascending = $true }
    $headerNames = @('File name','Input format','Resolution','File size','Modified','File path','AC compatibility')
    $list.Add_ColumnClick({
        param($sender, $e)
        if ($sortState.Column -eq $e.Column) { $sortState.Ascending = -not $sortState.Ascending } else { $sortState.Column = $e.Column; $sortState.Ascending = $true }
        $sender.ListViewItemSorter = New-Object ACTextureListComparer([int]$e.Column, [bool]$sortState.Ascending)
        $sender.Sort()
        for ($column = 0; $column -lt $headerNames.Count; $column++) { $sender.Columns[$column].Text = $headerNames[$column] }
        $arrow = if ($sortState.Ascending) { ' ▲' } else { ' ▼' }
        $sender.Columns[$e.Column].Text = $headerNames[$e.Column] + $arrow
        & $updateCompatibilityColumnWidth
        & $updateContentColumnWidths
    })
    $add = New-Object Windows.Forms.Button; $add.Text = 'Add files…'; $add.Location = New-Object Drawing.Point(530, 92); $add.Size = New-Object Drawing.Size(105, 32); $add.Anchor = 'Top,Left'
    $reload = New-Object Windows.Forms.Button; $reload.Text = 'Reload files'; $reload.Location = New-Object Drawing.Point(530, 132); $reload.Size = New-Object Drawing.Size(105, 32); $reload.Anchor = 'Top,Left'
    $remove = New-Object Windows.Forms.Button; $remove.Text = 'Remove'; $remove.Location = New-Object Drawing.Point(530, 172); $remove.Size = New-Object Drawing.Size(105, 32); $remove.Anchor = 'Top,Left'
    $clear = New-Object Windows.Forms.Button; $clear.Text = 'Clear'; $clear.Location = New-Object Drawing.Point(530, 212); $clear.Size = New-Object Drawing.Size(105, 32); $clear.Anchor = 'Top,Left'
    $convertButtonState = @{ IsConverting = $false }
    $updateConvertButtonText = {
        if ($list.SelectedItems.Count -gt 0) { $go.Text = 'Convert selected' } else { $go.Text = 'Convert all' }
        $go.Enabled = ($list.Items.Count -gt 0 -and -not $convertButtonState.IsConverting)
    }
    $list.Add_ItemSelectionChanged({ & $updateConvertButtonText })

    $fmtLabel = New-Object Windows.Forms.Label; $fmtLabel.Text = 'Output format'; $fmtLabel.Location = New-Object Drawing.Point(24, 270); $fmtLabel.Size = New-Object Drawing.Size(90, 22)
    $format = New-Object Windows.Forms.ComboBox; $format.Location = New-Object Drawing.Point(120, 266); $format.Size = New-Object Drawing.Size(315, 28); $format.DropDownStyle = 'DropDownList'
    foreach ($name in $script:Formats.Keys) { [void]$format.Items.Add($name) }; $format.SelectedItem = 'BC7 RGBA (preserve alpha)'
    $settingsButton = New-Object Windows.Forms.Button; $settingsButton.Text = 'Settings…'; $settingsButton.Location = New-Object Drawing.Point(450, 265); $settingsButton.Size = New-Object Drawing.Size(90, 29)
    $formatHint = New-Object Windows.Forms.Label; $formatHint.Location = New-Object Drawing.Point(120, 297); $formatHint.Size = New-Object Drawing.Size(515, 54); $formatHint.ForeColor = [Drawing.Color]::FromArgb(85, 85, 85)
    $updateFormatHint = { $selected = $script:Formats[$format.SelectedItem]; $formatHint.Text = $script:FormatHints[$selected] }
    $format.add_SelectedIndexChanged($updateFormatHint)
    & $updateFormatHint
    $mipLabel = New-Object Windows.Forms.Label; $mipLabel.Text = 'Mipmaps'; $mipLabel.Location = New-Object Drawing.Point(24, 360); $mipLabel.Size = New-Object Drawing.Size(90, 22)
    $mips = New-Object Windows.Forms.ComboBox; $mips.Location = New-Object Drawing.Point(120, 356); $mips.Size = New-Object Drawing.Size(190, 28); $mips.DropDownStyle = 'DropDownList'
    @('Full chain','None','4 levels','8 levels') | ForEach-Object { [void]$mips.Items.Add($_) }; $mips.SelectedIndex = 0
    $resizeEnabled = New-Object Windows.Forms.CheckBox; $resizeEnabled.Text = 'Limit resolution'; $resizeEnabled.Location = New-Object Drawing.Point(330, 358); $resizeEnabled.Size = New-Object Drawing.Size(112, 22)
    $maxDimension = New-Object Windows.Forms.ComboBox; $maxDimension.Location = New-Object Drawing.Point(445, 356); $maxDimension.Size = New-Object Drawing.Size(100, 28); $maxDimension.DropDownStyle = 'DropDownList'
    @('4096 px','2048 px','1024 px','512 px','256 px') | ForEach-Object { [void]$maxDimension.Items.Add($_) }; $maxDimension.SelectedItem = '2048 px'; $maxDimension.Enabled = $false
    $resizeToolTip = New-Object Windows.Forms.ToolTip; $resizeToolTip.AutoPopDelay = 12000; $resizeToolTip.InitialDelay = 450; $resizeToolTip.ReshowDelay = 150; $resizeToolTip.ShowAlways = $true
    $resizeToolTip.SetToolTip($resizeEnabled, 'Reduces images whose longest side exceeds the selected pixel limit. The aspect ratio is preserved, and smaller images are not enlarged.')
    $resizeToolTip.SetToolTip($maxDimension, 'Maximum length of the image''s longest side, in pixels.')
    $resizeEnabled.Add_CheckedChanged({ $maxDimension.Enabled = $resizeEnabled.Checked })
    $outLabel = New-Object Windows.Forms.Label; $outLabel.Text = 'Output folder'; $outLabel.Location = New-Object Drawing.Point(24, 401); $outLabel.Size = New-Object Drawing.Size(90, 22)
    $outLabelToolTip = New-Object Windows.Forms.ToolTip; $outLabelToolTip.SetToolTip($outLabel, 'Source folder saves each DDS beside its source image. Choose another folder to keep converted files separate.')
    $outBox = New-Object Windows.Forms.TextBox; $outBox.Location = New-Object Drawing.Point(120, 397); $outBox.Size = New-Object Drawing.Size(395, 25); $outBox.Anchor = 'Top,Left'; $outBox.Text = 'Source folder'; $outBox.ForeColor = [Drawing.Color]::Gray
    $outBox.Add_Enter({ if ($outBox.Text -eq 'Source folder') { $outBox.Clear(); $outBox.ForeColor = [Drawing.SystemColors]::WindowText } })
    $outBox.Add_Leave({ if ([string]::IsNullOrWhiteSpace($outBox.Text)) { $outBox.Text = 'Source folder'; $outBox.ForeColor = [Drawing.Color]::Gray } })
    $browse = New-Object Windows.Forms.Button; $browse.Text = '…'; $browse.Location = New-Object Drawing.Point(530, 394); $browse.Size = New-Object Drawing.Size(45, 30); $browse.Anchor = 'Top,Left'
    $sourceFolderButton = New-Object Windows.Forms.Button; $sourceFolderButton.Text = 'Source'; $sourceFolderButton.Location = New-Object Drawing.Point(580, 394); $sourceFolderButton.Size = New-Object Drawing.Size(55, 30); $sourceFolderButton.Anchor = 'Top,Left'
    $overwrite = New-Object Windows.Forms.CheckBox; $overwrite.Text = 'Overwrite existing destination files'; $overwrite.Location = New-Object Drawing.Point(120, 430); $overwrite.Size = New-Object Drawing.Size(255, 24)
    $overwriteToolTip = New-Object Windows.Forms.ToolTip; $overwriteToolTip.SetToolTip($overwrite, 'In Source folder mode, this can replace existing source DDS files. With another folder, only matching files already in that destination are replaced; the source files stay untouched.')
    $backup = New-Object Windows.Forms.CheckBox; $backup.Text = 'Move replaced files to Backup folder'; $backup.Location = New-Object Drawing.Point(380, 430); $backup.Size = New-Object Drawing.Size(255, 24); $backup.Enabled = $false
    $backupToolTip = New-Object Windows.Forms.ToolTip; $backupToolTip.AutoPopDelay = 12000; $backupToolTip.InitialDelay = 450; $backupToolTip.ReshowDelay = 150; $backupToolTip.ShowAlways = $true
    $backupToolTip.SetToolTip($backup, 'A Backup subfolder is created inside the selected output folder, or inside each source folder when Source folder is selected. Replaced files are moved there.')
    $updateOverwriteLabel = { if ([string]::IsNullOrWhiteSpace($outBox.Text) -or $outBox.Text -eq 'Source folder') { $overwrite.Text = 'Overwrite files in source folder' } else { $overwrite.Text = 'Overwrite files in output folder' } }
    $outBox.Add_TextChanged({ & $updateOverwriteLabel })
    & $updateOverwriteLabel
    $overwrite.Add_CheckedChanged({ $backup.Enabled = $overwrite.Checked; if (-not $overwrite.Checked) { $backup.Checked = $false } })
    $updateCompatibilityColumnWidth = {
        $column = $list.Columns[6]
        $widest = [Windows.Forms.TextRenderer]::MeasureText($column.Text, $list.Font).Width
        foreach ($item in $list.Items) {
            if ($item.SubItems.Count -gt 6) {
                $textWidth = [Windows.Forms.TextRenderer]::MeasureText([string]$item.SubItems[6].Text, $list.Font).Width
                if ($textWidth -gt $widest) { $widest = $textWidth }
            }
        }
        $column.Width = [Math]::Max(105, $widest + 24)
    }
    $updateContentColumnWidths = {
        foreach ($columnIndex in @(1, 2, 3, 4)) {
            $column = $list.Columns[$columnIndex]
            $widest = [Windows.Forms.TextRenderer]::MeasureText($column.Text, $list.Font).Width
            foreach ($item in $list.Items) {
                if ($item.SubItems.Count -gt $columnIndex) {
                    $textWidth = [Windows.Forms.TextRenderer]::MeasureText([string]$item.SubItems[$columnIndex].Text, $list.Font).Width
                    if ($textWidth -gt $widest) { $widest = $textWidth }
                }
            }
            $column.Width = [Math]::Max(60, $widest + 24)
        }
    }
    $totalSize = New-Object Windows.Forms.Label; $totalSize.Location = New-Object Drawing.Point(24, 462); $totalSize.Size = New-Object Drawing.Size(420, 22); $totalSize.Anchor = 'Bottom,Left'; $totalSize.ForeColor = [Drawing.Color]::FromArgb(75, 75, 75)
    $updateTotalSize = {
        [long]$totalBytes = 0
        foreach ($item in $list.Items) { $totalBytes += [long]$item.SubItems[3].Tag }
        if ($totalBytes -lt 1KB) { $totalText = "$totalBytes B" }
        elseif ($totalBytes -lt 1MB) { $totalText = ([Math]::Round($totalBytes / 1KB, 1)).ToString('0.0', [Globalization.CultureInfo]::CurrentCulture) + ' KB' }
        elseif ($totalBytes -lt 1GB) { $totalText = ([Math]::Round($totalBytes / 1MB, 1)).ToString('0.0', [Globalization.CultureInfo]::CurrentCulture) + ' MB' }
        else { $totalText = ([Math]::Round($totalBytes / 1GB, 2)).ToString('0.00', [Globalization.CultureInfo]::CurrentCulture) + ' GB' }
        $totalSize.Text = "Total file size ($($list.Items.Count) files): $totalText"
        & $updateCompatibilityColumnWidth
        & $updateContentColumnWidths
    }
    & $updateTotalSize
    $status = New-Object Windows.Forms.Label; $status.Text = 'Ready'; $status.Location = New-Object Drawing.Point(24, 492); $status.Size = New-Object Drawing.Size(400, 24); $status.Anchor = 'Bottom,Left'
    $go = New-Object Windows.Forms.Button; $go.Text = 'Convert all'; $go.Location = New-Object Drawing.Point(470, 485); $go.Size = New-Object Drawing.Size(165, 38); $go.Anchor = 'Bottom,Right'; $go.BackColor = [Drawing.Color]::FromArgb(35, 105, 190); $go.ForeColor = [Drawing.Color]::White
    $mainToolTip = New-Object Windows.Forms.ToolTip
    $mainToolTip.AutoPopDelay = 12000; $mainToolTip.InitialDelay = 450; $mainToolTip.ReshowDelay = 150; $mainToolTip.ShowAlways = $true
    $mainToolTip.SetToolTip($list, 'Drop supported files or folders here. Hover a file row to see its full path and file details.')
    $mainToolTip.SetToolTip($add, 'Choose DDS or supported image files. Multiple files can be selected at once.')
    $mainToolTip.SetToolTip($reload, 'Refresh file details and remove files that no longer exist.')
    $mainToolTip.SetToolTip($remove, 'Remove the selected rows from this conversion list. The files on disk are not changed.')
    $mainToolTip.SetToolTip($clear, 'Remove every row from the conversion list. The files on disk are not changed.')
    $mainToolTip.SetToolTip($format, 'Choose the DDS compression format. Hover the description below for format details.')
    $mainToolTip.SetToolTip($settingsButton, 'Choose which output formats appear in this list.')
    $mainToolTip.SetToolTip($mips, 'Choose how many mipmap levels to create. A full chain continues down to 1×1 pixels.')
    $mainToolTip.SetToolTip($outBox, 'Choose a destination folder, or use Source folder to save each DDS beside its input file.')
    $mainToolTip.SetToolTip($browse, 'Choose an output folder.')
    $mainToolTip.SetToolTip($sourceFolderButton, 'Set the output location to the folder containing each input file.')
    $mainToolTip.SetToolTip($totalSize, 'Sum of the input file sizes currently listed. This is not the predicted size of the converted DDS files.')
    $mainToolTip.SetToolTip($status, 'Shows the current action and the result of the last operation.')
    $mainToolTip.SetToolTip($go, 'Convert the selected rows, or the whole list if nothing is selected, using the chosen output settings.')
    & $updateConvertButtonText

    $baseClientHeight = $form.ClientSize.Height
    $controlsBelowList = @($fmtLabel,$format,$settingsButton,$formatHint,$mipLabel,$mips,$resizeEnabled,$maxDimension,$outLabel,$outBox,$browse,$sourceFolderButton,$overwrite,$backup)
    $controlBaseTops = @()
    foreach ($control in $controlsBelowList) { $controlBaseTops += [pscustomobject]@{ Control = $control; Top = $control.Top } }
    $layoutMainInputs = {
        $rightColumnLeft = [Math]::Max(420, $form.ClientSize.Width - 24 - $add.Width)
        $add.Left = $rightColumnLeft
        $reload.Left = $rightColumnLeft
        $remove.Left = $rightColumnLeft
        $clear.Left = $rightColumnLeft
        $browse.Left = $rightColumnLeft
        $sourceFolderButton.Left = $rightColumnLeft + 50
        $list.Width = [Math]::Max(220, $rightColumnLeft - 16 - $list.Left)
        & $updateCompatibilityColumnWidth
        & $updateContentColumnWidths
        $list.Columns[5].Width = 250
        $list.Columns[0].Width = [Math]::Max(110, $list.ClientSize.Width - $list.Columns[1].Width - $list.Columns[2].Width - $list.Columns[3].Width - $list.Columns[4].Width - $list.Columns[5].Width - $list.Columns[6].Width - 32)
        $outBox.Width = [Math]::Max(180, $rightColumnLeft - 16 - $outBox.Left)
        $verticalDelta = [Math]::Max(-40, $form.ClientSize.Height - $baseClientHeight)
        $list.Height = [Math]::Max(120, 160 + $verticalDelta)
        foreach ($entry in $controlBaseTops) { $entry.Control.Top = $entry.Top + $verticalDelta }
    }
    $form.Add_Resize({ & $layoutMainInputs })
    & $layoutMainInputs

    $fileDragEnter = {
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy }
        else { $e.Effect = [Windows.Forms.DragDropEffects]::None }
    }
    $fileDrop = {
        param($sender, $e)
        $added = 0
        $droppedItems = [string[]]$e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
        foreach ($droppedPath in $droppedItems) {
            foreach ($file in (Get-DroppedSupportedFilePaths $droppedPath)) { if (Add-InputFileRow $list $file) { $added++ } }
        }
        if ($added -gt 0) { $status.Text = "Added $added file(s) from $($droppedItems.Count) dropped item(s)." }
        else { $status.Text = 'No new supported files were added.' }
        & $updateTotalSize
        & $updateConvertButtonText
    }
    $form.AllowDrop = $true
    $form.Add_DragEnter($fileDragEnter); $form.Add_DragDrop($fileDrop)
    $list.Add_DragEnter($fileDragEnter); $list.Add_DragDrop($fileDrop)

    $add.Add_Click({ $dialog = New-Object Windows.Forms.OpenFileDialog; $dialog.Filter = 'DDS files (*.dds)|*.dds|Supported images|*.dds;*.png;*.tga;*.bmp;*.jpg;*.jpeg;*.tif;*.tiff;*.hdr|All files (*.*)|*.*'; $dialog.Multiselect = $true; if ($dialog.ShowDialog() -eq 'OK') { foreach ($f in $dialog.FileNames) { [void](Add-InputFileRow $list $f) }; & $updateTotalSize; & $updateConvertButtonText } })
    $reload.Add_Click({
        try {
            $paths = @($list.Items | ForEach-Object { [string]$_.Tag })
            $selectedPaths = @($list.SelectedItems | ForEach-Object { [string]$_.Tag })
            $previousCount = $paths.Count
            $sorter = $list.ListViewItemSorter
            $script:DdsFormatCache.Clear()
            $script:ResolutionCache.Clear()
            $list.BeginUpdate()
            try {
                $list.Items.Clear()
                foreach ($path in $paths) { [void](Add-InputFileRow $list $path) }
                if ($sorter) { $list.ListViewItemSorter = $sorter; $list.Sort() }
                foreach ($item in $list.Items) { if ($selectedPaths -contains [string]$item.Tag) { $item.Selected = $true } }
            } finally { $list.EndUpdate() }
            if ($list.Items.Count -lt $previousCount) { $status.Text = "Reloaded $($list.Items.Count) of $previousCount file(s); missing files were removed." }
            else { $status.Text = "Reloaded $($list.Items.Count) file(s)." }
            & $updateTotalSize
            & $updateConvertButtonText
        } catch { $status.Text = 'Reload failed.'; [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AC Texture Converter', 'OK', 'Error') | Out-Null }
    })
    $remove.Add_Click({ foreach ($row in @($list.SelectedItems)) { $list.Items.Remove($row) }; & $updateTotalSize; & $updateConvertButtonText })
    $clear.Add_Click({ $list.Items.Clear(); & $updateTotalSize; & $updateConvertButtonText })
    $browse.Add_Click({ $dialog = New-Object Windows.Forms.FolderBrowserDialog; if ($outBox.Text -and $outBox.Text -ne 'Source folder' -and (Test-Path -LiteralPath $outBox.Text -PathType Container)) { $dialog.SelectedPath = $outBox.Text }; if ($dialog.ShowDialog() -eq 'OK') { $outBox.Text = $dialog.SelectedPath; $outBox.ForeColor = [Drawing.SystemColors]::WindowText } })
    $sourceFolderButton.Add_Click({ $outBox.Text = 'Source folder'; $outBox.ForeColor = [Drawing.Color]::Gray })
    $go.Add_Click({
        try {
            $convertButtonState.IsConverting = $true; & $updateConvertButtonText; $status.Text = 'Converting…'; $form.Refresh()
            if ($list.Items.Count -eq 0) { throw 'Add at least one file.' }
            $mipArg = switch ($mips.SelectedIndex) { 1 { 'none' } 2 { '4' } 3 { '8' } default { 'full' } }
            $resizeCap = if ($resizeEnabled.Checked) { [int](([string]$maxDimension.SelectedItem) -replace '\D','') } else { 0 }
            $selectedFormat = $script:Formats[$format.SelectedItem]
            $resolvedOutDir = if ([string]::IsNullOrWhiteSpace($outBox.Text) -or $outBox.Text -eq 'Source folder') { '' } else { [IO.Path]::GetFullPath($outBox.Text) }
            $selectedRows = @($list.SelectedItems)
            if ($selectedRows.Count -gt 0) {
                $inputFiles = @($selectedRows | ForEach-Object { [string]$_.Tag })
            } else {
                $inputFiles = @($list.Items | ForEach-Object { [string]$_.Tag })
            }
            $plannedOutputs = @($inputFiles | ForEach-Object { Get-OutputDdsPath $_ (Resolve-OutputDirectory $_ $resolvedOutDir) })
            $existingOutputs = @($plannedOutputs | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
            if ($existingOutputs.Count -gt 0) {
                if (-not $overwrite.Checked) { throw 'One or more output files already exist. Enable overwrite or choose a different output folder.' }
                $names = ($existingOutputs | ForEach-Object { [IO.Path]::GetFileName($_) } | Select-Object -Unique | Select-Object -First 12) -join "`r`n"
                $more = if ($existingOutputs.Count -gt 12) { "`r`n…and $($existingOutputs.Count - 12) more." } else { '' }
                $backupNotice = if ($backup.Checked) { "`r`n`r`nThe existing files will first be moved into the Backup subfolder." } else { '' }
                $answer = [Windows.Forms.MessageBox]::Show("These output files already exist and will be replaced:`r`n`r`n$names$more$backupNotice`r`n`r`nContinue?", 'Confirm overwrite', 'YesNo', 'Warning')
                if ($answer -ne [Windows.Forms.DialogResult]::Yes) { $status.Text = 'Conversion cancelled.'; return }
            }
            $n = Invoke-Conversion $inputFiles $selectedFormat $resolvedOutDir $mipArg $overwrite.Checked $backup.Checked $false $resizeCap
            $status.Text = "Created $n file(s) successfully."
[Windows.Forms.MessageBox]::Show("Created $n DDS file(s).", 'AC Texture Converter', 'OK', 'Information') | Out-Null
        } catch { $status.Text = 'Conversion failed.'; [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AC Texture Converter', 'OK', 'Error') | Out-Null }
        finally { $convertButtonState.IsConverting = $false; & $updateConvertButtonText }
    })
    $settingsButton.Add_Click({
        $dialog = New-Object Windows.Forms.Form
$dialog.Text = 'AC Texture Converter Settings'; $dialog.Size = New-Object Drawing.Size(390, 340); $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false
        $hint = New-Object Windows.Forms.Label; $hint.Text = 'Select the formats to show in Output format.'; $hint.Location = New-Object Drawing.Point(16, 16); $hint.Size = New-Object Drawing.Size(345, 24)
        $checks = New-Object Windows.Forms.CheckedListBox; $checks.Location = New-Object Drawing.Point(18, 48); $checks.Size = New-Object Drawing.Size(335, 180); $checks.CheckOnClick = $true
        $allFormatEntries = @($script:BaseFormats.GetEnumerator()) + @($script:OptionalFormats.GetEnumerator())
        for ($i = 0; $i -lt $allFormatEntries.Count; $i++) { [void]$checks.Items.Add($allFormatEntries[$i].Key, ($script:EnabledFormats -contains $allFormatEntries[$i].Value)) }
        $formatToolTip = New-Object Windows.Forms.ToolTip
        $formatToolTip.AutoPopDelay = 12000; $formatToolTip.InitialDelay = 450; $formatToolTip.ReshowDelay = 150; $formatToolTip.ShowAlways = $true
        $checks.Tag = -1
        $checks.Add_MouseMove({
            param($sender, $e)
            $hoverIndex = $sender.IndexFromPoint($e.Location)
            if ($hoverIndex -ne $sender.Tag) {
                $sender.Tag = $hoverIndex
                if ($hoverIndex -ge 0) {
                    $formatCode = $allFormatEntries[$hoverIndex].Value
                    $description = $script:FormatHints[$formatCode]
                    if ($description) { $formatToolTip.Show($description, $sender, $e.X + 16, $e.Y + 18, 12000) }
                } else { $formatToolTip.Hide($sender) }
            }
        })
        $checks.Add_MouseLeave({ $checks.Tag = -1; $formatToolTip.Hide($checks) })
        $ok = New-Object Windows.Forms.Button; $ok.Text = 'Save'; $ok.DialogResult = [Windows.Forms.DialogResult]::OK; $ok.Location = New-Object Drawing.Point(190, 250); $ok.Size = New-Object Drawing.Size(75, 30)
        $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel; $cancel.Location = New-Object Drawing.Point(278, 250); $cancel.Size = New-Object Drawing.Size(75, 30)
        $dialog.AcceptButton = $ok; $dialog.CancelButton = $cancel; $dialog.Controls.AddRange(@($hint,$checks,$ok,$cancel))
        if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                $selectedFormat = $script:Formats[$format.SelectedItem]
                $selected = @(); foreach ($i in $checks.CheckedIndices) { $selected += $allFormatEntries[[int]$i].Value }
                Save-FormatSettings $selected
                $format.Items.Clear(); foreach ($name in $script:Formats.Keys) { [void]$format.Items.Add($name) }
                $selection = $script:Formats.GetEnumerator() | Where-Object { $_.Value -eq $selectedFormat } | Select-Object -First 1
                $format.SelectedItem = if ($selection) { $selection.Key } else { 'BC7 RGBA (preserve alpha)' }
                & $updateFormatHint
} catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AC Texture Converter Settings', 'OK', 'Error') | Out-Null }
        }
        $formatToolTip.Dispose()
    })
    $form.Controls.AddRange(@($title,$sub,$list,$add,$reload,$remove,$clear,$fmtLabel,$format,$settingsButton,$formatHint,$mipLabel,$mips,$resizeEnabled,$maxDimension,$outLabel,$outBox,$browse,$sourceFolderButton,$overwrite,$backup,$totalSize,$status,$go))
    $form.Add_Shown({
        $consoleWindow = [DdsForge.NativeWindow]::GetConsoleWindow()
        if ($consoleWindow -ne [IntPtr]::Zero -and [DdsForge.NativeWindow]::IsWindowVisible($consoleWindow)) {
            [void][DdsForge.NativeWindow]::ShowWindow($consoleWindow, 6)
        }
    })
    [void]$form.ShowDialog()
}

if ($SelfTest) {
    $script:EnabledFormats = @($script:BaseFormats.Values)
    Set-FormatList
    $assert = { param($ok,$message) if (-not $ok) { throw "Self-test failed: $message" } }
    & $assert ($script:BaseFormats.Contains('Uncompressed RGBA8 (32-bit)')) 'uncompressed RGBA8 is a default format'
    & $assert (-not ($script:Formats.Values -contains 'BC4_UNORM')) 'BC4 is hidden until enabled in settings'
    & $assert (-not ($script:Formats.Values -contains 'BC5_UNORM')) 'BC5 is hidden until enabled in settings'
    & $assert (-not ($script:Formats.Values -contains 'BC6H_UF16')) 'BC6H is hidden until enabled in settings'
    $script:EnabledFormats = @($script:BaseFormats.Values) + @('BC4_UNORM','BC6H_UF16')
    Set-FormatList
    & $assert ($script:Formats.Values -contains 'BC4_UNORM') 'enabled BC4 appears in the output list'
    & $assert ($script:Formats.Values -contains 'BC6H_UF16') 'enabled BC6H appears in the output list'
    & $assert (-not ($script:Formats.Values -contains 'BC5_UNORM')) 'unchecked BC5 remains hidden'
    $script:EnabledFormats = @($script:BaseFormats.Values | Where-Object { $_ -ne 'BC1_UNORM' })
    Set-FormatList
    & $assert (-not ($script:Formats.Values -contains 'BC1_UNORM')) 'a default format can be removed from the output list'
    $script:EnabledFormats = @($script:BaseFormats.Values)
    Set-FormatList
    & $assert ($script:Formats['BC7 RGBA (preserve alpha)'] -eq 'BC7_UNORM') 'BC7 RGBA mapping'
    & $assert ($script:FormatHints['BC7_UNORM'] -match '0\.1\.74-preview3') 'BC7 hint includes the documented CSP minimum version'
    & $assert ($script:FormatHints['A8L8'] -match 'AL 8\.8') 'A8L8 usage hint'
    & $assert ($script:FormatHints['BC5_UNORM'] -match 'shader') 'BC5 compatibility hint'
    & $assert ($script:Formats['BC7 (opaque; remove transparency)'] -eq 'BC7_OPAQUE') 'BC7 opaque mapping'
    & $assert ($script:OptionalFormats['BC4 (grayscale/channel)'] -eq 'BC4_UNORM') 'optional BC4 mapping'
    & $assert ($script:OptionalFormats['BC5 (normal maps/RG)'] -eq 'BC5_UNORM') 'optional BC5 mapping'
    & $assert ($script:OptionalFormats['BC6H (HDR, no alpha)'] -eq 'BC6H_UF16') 'optional BC6H mapping'
    & $assert ($script:Formats['A8L8 (R=luminance, A=alpha)'] -eq 'A8L8') 'A8L8 mapping'
    & $assert ((Resolve-TexconvSwizzle 'BC1_UNORM') -eq 'rgb1') 'BC1 ignores source alpha before compression'
    & $assert ((Resolve-TexconvSwizzle 'BC7_UNORM' $true) -eq 'rgb1') 'opaque BC7 ignores source alpha before compression'
    & $assert ((Resolve-TexconvSwizzle 'BC7_UNORM' $false) -eq '') 'alpha-preserving BC7 leaves source alpha intact'
    & $assert (Test-ExpandA8L8Luminance 'BC7_UNORM' $true) 'A8L8 BC7 expands luminance to RGB while preserving alpha through DirectXTex'
    & $assert (Test-ExpandA8L8Luminance 'BC3_UNORM' $true) 'A8L8 BC3 expands luminance to RGB while preserving alpha through DirectXTex'
    & $assert (Test-ExpandA8L8Luminance 'R8G8B8A8_UNORM' $true) 'A8L8 RGBA8 expands luminance to RGB while preserving alpha through DirectXTex'
    & $assert (Test-ExpandA8L8Luminance 'BC1_UNORM' $true) 'A8L8 BC1 expands luminance before opaque compression'
    & $assert (Test-ExpandA8L8Luminance 'BC7_UNORM' $true) 'A8L8 opaque BC7 expands luminance before opaque compression'
    & $assert (-not (Test-ExpandA8L8Luminance 'BC7_UNORM' $false)) 'ordinary BC7 input conversion does not expand luminance'
    & $assert (-not (Test-ExpandA8L8Luminance 'BC4_UNORM' $true)) 'single-channel BC4 remains a single-channel target'
    & $assert (-not (Test-ExpandA8L8Luminance 'A8L8' $true)) 'A8L8 output retains its native two-channel layout'
    & $assert ((Resolve-A8L8InputSwizzle '' 0 0 0 0 0) -eq 'ra') 'RGBA inputs source A for A8L8 alpha'
    & $assert ((Resolve-A8L8InputSwizzle '' 0 0x20001 16 0xFF 0xFF00) -eq 'rg') 'legacy A8L8 sources preserve their second channel'
    & $assert ((Resolve-A8L8InputSwizzle 'DX10' 49 0 0 0 0) -eq 'rg') 'DXGI R8G8 sources preserve their second channel'
    & $assert (-not [string]::IsNullOrWhiteSpace((Get-DdsProgId))) '.dds shell ProgID is resolved'
    & $assert (@('.dds','.png','.tga','.bmp','.jpg','.jpeg','.tif','.tiff','.hdr' | Where-Object { $_ -notin $script:SupportedInputExtensions }).Count -eq 0) 'Explorer input types match the supported image formats'
    & $assert ((Get-ContextMenuShellPaths) -contains 'HKCU:\Software\Classes\SystemFileAssociations\.png\shell') 'context menu covers supported image extensions'
    $pngMenuTarget = @(Get-ContextMenuTargets | Where-Object { $_.ShellPath -eq 'HKCU:\Software\Classes\SystemFileAssociations\.png\shell' })
    & $assert ($pngMenuTarget.Count -eq 1 -and -not $pngMenuTarget[0].IsDds) 'image inputs receive the image-safe context menu'
    $ddsMenuTarget = @(Get-ContextMenuTargets | Where-Object { $_.ShellPath -eq 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell' })
    & $assert ($ddsMenuTarget.Count -eq 1 -and $ddsMenuTarget[0].IsDds) 'DDS inputs retain DDS overwrite actions'
    & $assert ((Resolve-MipCount 'full') -eq '0') 'full mip chain mapping'
    & $assert ((Resolve-MipCount 'none') -eq '1') 'no mipmaps mapping'
    & $assert ((Resolve-MipCount '8') -eq '8') 'fixed mip count mapping'
    $invalidMipRejected = $false
    try { [void](Resolve-MipCount '0') } catch { $invalidMipRejected = $true }
    & $assert $invalidMipRejected 'zero mip count is rejected as user input'
    & $assert ((Quote-Argument 'C:\A B\x.dds') -eq '"C:\A B\x.dds"') 'argument quoting with spaces'
    & $assert ((Quote-Argument 'C:\a"b.dds') -match '^".*"$') 'argument quoting with quotation marks'
    & $assert ((Resolve-OutputDirectory 'C:\Users\test\Desktop\source.dds' '') -eq 'C:\Users\test\Desktop') 'blank output folder resolves to each source file folder'
    & $assert ((Resolve-OutputDirectory 'C:\Users\test\Desktop\source.dds' 'C:\Users\test\out') -eq 'C:\Users\test\out') 'selected output folder is honored'
    & $assert ((Resolve-OutputDirectory 'C:\Users\test\Desktop\source.dds' '' $true) -eq 'C:\Users\test\Desktop\DDS-Converted') 'safe context conversion uses a separate output folder'
    & $assert ((Get-OutputDdsPath 'C:\Users\test\Desktop\source.dds' 'C:\Users\test\out') -ceq 'C:\Users\test\out\source.dds') 'lowercase DDS extension is preserved'
    & $assert ((Get-OutputDdsPath 'C:\Users\test\Desktop\source.DDS' 'C:\Users\test\out') -ceq 'C:\Users\test\out\source.DDS') 'uppercase DDS extension is preserved'
    & $assert ((Get-OutputDdsPath 'C:\Users\test\Desktop\source.DdS' 'C:\Users\test\out') -ceq 'C:\Users\test\out\source.DdS') 'mixed-case DDS extension is preserved'
    & $assert ((Get-OutputDdsPath 'C:\Users\test\Desktop\source.png' 'C:\Users\test\out') -ceq 'C:\Users\test\out\source.dds') 'non-DDS inputs produce lowercase DDS extension'
    & $assert ($script:Formats.Count -gt 0) 'Explorer format choices follow the enabled output formats'
    Write-Output 'AC Texture Converter self-tests: OK'
    return
}

if ($RegisterContextMenu) {
    try { Set-ExplorerContextMenu $ContextMenuTargetScript; Write-Output 'Explorer context menu registered.'; exit 0 }
    catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
}

if ($ShellMode) {
    try {
        if (-not $InputPath.Count) { throw 'No supported image files were passed from Explorer.' }
        foreach ($path in $InputPath) {
            if ([IO.Path]::GetExtension($path).ToLowerInvariant() -notin $script:SupportedInputExtensions) { throw "The context menu does not support this file type: $path" }
        }
        if ($ShellMode -in @('Overwrite','Backup') -and @($InputPath | Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -ne '.dds' }).Count) {
            throw 'Overwrite and backup menu actions are available for DDS files. Image files can be converted to the DDS-Converted subfolder.'
        }
        $backupMode = $ShellMode -eq 'Backup'
        $overwriteMode = $ShellMode -in @('Overwrite','Backup')
        if ($overwriteMode) {
            $names = @($InputPath | ForEach-Object { [IO.Path]::GetFileName([string]$_) } | Select-Object -First 12) -join "`r`n"
            $more = if ($InputPath.Count -gt 12) { "`r`n…and $($InputPath.Count - 12) more." } else { '' }
            $backupNotice = if ($backupMode) { "`r`n`r`nThe originals will first be moved into a Backup subfolder beside each source file." } else { "`r`n`r`nThis replaces the selected source files without a backup." }
            $answer = [Windows.Forms.MessageBox]::Show("This will convert and replace the selected DDS file(s):`r`n`r`n$names$more$backupNotice`r`n`r`nContinue?", 'Confirm overwrite', 'YesNo', 'Warning')
            if ($answer -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }
        }
        $safeOutput = $ShellMode -eq 'Copy'
        $count = Invoke-Conversion $InputPath $Format '' 'full' $overwriteMode $backupMode $safeOutput
        [Windows.Forms.MessageBox]::Show("Created $count DDS file(s).", 'AC Texture Converter', 'OK', 'Information') | Out-Null
        exit 0
    }
    catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AC Texture Converter', 'OK', 'Error') | Out-Null
        exit 1
    }
}

if ($InputPath.Count -gt 0 -and -not $OpenWith) {
    try {
        if ($BackupOriginals) { $Overwrite = $true }
        $count = Invoke-Conversion $InputPath $Format $OutputDirectory $Mipmaps $Overwrite.IsPresent $BackupOriginals.IsPresent
        Write-Output "Success: $count file(s)."
        exit 0
    }
    catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
}
Show-MainWindow $InputPath
