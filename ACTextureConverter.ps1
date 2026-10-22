param(
    [string[]]$InputPath = @(),
    [string]$Format = 'BC7_UNORM',
    [string]$OutputDirectory = '',
    [string]$Mipmaps = 'full',
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
    'BC7_UNORM' = "High-quality RGB/RGBA with preserved alpha.`r`nDocumented CSP support: 0.1.74-preview3 (build 1434) or newer; verify your target setup."
    'BC7_OPAQUE' = "High-quality opaque BC7; alpha is forced to 1 before compression.`r`nDocumented CSP support: 0.1.74-preview3 (build 1434) or newer; verify your target setup."
    'R8G8B8A8_UNORM' = 'Uncompressed 32-bit RGBA; avoids block artifacts but creates larger files.'
    'A8L8' = 'Legacy grayscale plus alpha: luminance comes from R; an existing A8L8/R8G8 source keeps its second channel as alpha. Use where the AC material expects AL 8.8.'
}
$script:SettingsPath = Join-Path (Join-Path $env:APPDATA 'DDSForge') 'settings.json'
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
    $progIdMenu = "HKCU:\Software\Classes\$(Get-DdsProgId)\shell\ACTextureConverter"
    $legacyMenu = 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell\ACTextureConverter'
    if ((Test-Path -LiteralPath $progIdMenu) -or (Test-Path -LiteralPath $legacyMenu)) { Set-ExplorerContextMenu }
}

function Set-ExplorerContextMenu([string]$TargetScript = '') {
    $progId = Get-DdsProgId
    $shellRelative = "Software\Classes\$progId\shell"
    $shellRoots = @((Get-DdsProgIds | ForEach-Object { "HKCU:\Software\Classes\$_\shell" }) + 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell' | Select-Object -Unique)
    foreach ($shellPath in $shellRoots) {
        foreach ($existing in @(Get-ChildItem -LiteralPath $shellPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'ACTextureConverter' -or $_.PSChildName.StartsWith('ACTextureConverter_',[StringComparison]::OrdinalIgnoreCase) })) {
            Remove-Item -LiteralPath $existing.PSPath -Recurse -Force
        }
    }
    # Remove entries from the previous SubCommands/CommandStore implementation.
    $commandStoreRelative = 'Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell'
    $commandStorePath = "HKCU:\$commandStoreRelative"
    foreach ($existing in @(Get-ChildItem -LiteralPath $commandStorePath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName.StartsWith('ACTextureConverter.',[StringComparison]::OrdinalIgnoreCase) })) {
        Remove-Item -LiteralPath $existing.PSPath -Recurse -Force
    }
    # Remove old definitions too, so the retired copy submenu cannot linger.
    $menuDefinitions = @('ACTextureConverter.ContextMenu','ACTextureConverter.CopyMenu','ACTextureConverter.OverwriteMenu','ACTextureConverter.OverwriteOriginalMenu','ACTextureConverter.BackupMenu')
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
    $launcherPath = Join-Path (Split-Path -Parent $scriptPath) 'AC Texture Converter.exe'
    $useExecutable = Test-Path -LiteralPath $launcherPath -PathType Leaf
    function Set-ContextLeaf([string]$ParentPath, [string]$Id, [string]$Label, [string]$ScriptArguments, [string]$Executable, [bool]$UseExecutable) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$ParentPath\$Id")
        $key.SetValue('MUIVerb', $Label, [Microsoft.Win32.RegistryValueKind]::String)
        # A registry shell command gets one selected path through %1. Document
        # lets Explorer invoke it once per file when several DDS files are selected.
        $key.SetValue('MultiSelectModel', 'Document', [Microsoft.Win32.RegistryValueKind]::String)
        $commandKey = $key.CreateSubKey('command')
        if ($UseExecutable) { $commandLine = "`"$Executable`" $ScriptArguments -InputPath `"%1`"" }
        else { $commandLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" $ScriptArguments -InputPath `"%1`"" }
        $commandKey.SetValue('', $commandLine, [Microsoft.Win32.RegistryValueKind]::String)
        $commandKey.Dispose()
        $key.Dispose()
    }
    function New-MenuDefinition([string]$Name) {
        $definitionPath = "Software\Classes\$Name"
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($definitionPath)
        $key.SetValue('ACTextureConverterOwner', 'AC Texture Converter', [Microsoft.Win32.RegistryValueKind]::String)
        $key.Dispose()
        $shellDefinitionPath = "$definitionPath\shell"
        [void][Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($shellDefinitionPath)
        return $shellDefinitionPath
    }
    function New-ContextGroup([string]$ParentPath, [string]$Id, [string]$Label, [string]$MenuDefinition) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$ParentPath\$Id")
        $key.SetValue('MUIVerb', $Label, [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('ExtendedSubCommandsKey', $MenuDefinition, [Microsoft.Win32.RegistryValueKind]::String)
        $key.Dispose()
        return New-MenuDefinition $MenuDefinition
    }

    $rootPath = "$shellRelative\ACTextureConverter"
    $rootKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($rootPath)
    $rootKey.SetValue('MUIVerb', 'AC Texture Converter', [Microsoft.Win32.RegistryValueKind]::String)
    $rootKey.SetValue('ExtendedSubCommandsKey', 'ACTextureConverter.ContextMenu', [Microsoft.Win32.RegistryValueKind]::String)
    $rootKey.Dispose()
    $rootChildren = New-MenuDefinition 'ACTextureConverter.ContextMenu'
    # Prefix the internal verb IDs because Explorer enumerates these subcommands
    # by registry key name and ignores the shell order metadata for this cascade.
    $backupChildren = New-ContextGroup $rootChildren '01_Backup' 'Overwrite with Backup' 'ACTextureConverter.BackupMenu'
    $overwriteChildren = New-ContextGroup $rootChildren '02_OverwriteOriginal' 'Overwrite original' 'ACTextureConverter.OverwriteOriginalMenu'
    Set-ContextLeaf $rootChildren '03_Open' 'Open AC Texture Converter' '-OpenWith' $launcherPath $useExecutable
    foreach ($entry in $script:Formats.GetEnumerator()) {
        $formatId = $entry.Value -replace '[^A-Za-z0-9_]', '_'
        $formatName = $entry.Key
        Set-ContextLeaf $overwriteChildren $formatId $formatName "-ShellMode Overwrite -Format $($entry.Value)" $launcherPath $useExecutable
        Set-ContextLeaf $backupChildren $formatId $formatName "-ShellMode Backup -Format $($entry.Value)" $launcherPath $useExecutable
    }
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

function Resolve-A8L8InputSwizzle([string]$FourCC, [uint32]$DxgiFormat, [uint32]$PixelFlags, [uint32]$BitsPerPixel, [uint32]$RedMask, [uint32]$AlphaMask) {
    # DirectXTex loads legacy A8L8 and DXGI R8G8_UNORM as R/G, where G carries alpha.
    if (($FourCC -eq 'DX10' -and $DxgiFormat -eq 49) -or (($PixelFlags -band 0x20000) -ne 0 -and $BitsPerPixel -eq 16 -and $RedMask -eq 0xFF -and $AlphaMask -eq 0xFF00)) { return 'rg' }
    # RGBA and ordinary image inputs carry alpha in A.
    return 'ra'
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

function Invoke-Conversion([string[]]$Files, [string]$DxgiFormat, [string]$OutDir, [string]$MipSetting, [bool]$OverwriteExisting = $false, [bool]$BackupExisting = $false, [bool]$PerSourceSubfolder = $false) {
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
        $swizzle = Resolve-TexconvSwizzle $DxgiFormat $forceOpaque
        if ($DxgiFormat -eq 'A8L8') { $swizzle = Get-A8L8InputSwizzle $file }
        $jobs += [pscustomobject]@{ Input = $file; OutputDirectory = $fileOutDir; OutputFile = $outputFile; Swizzle = $swizzle }
    }
    $texconvFormat = if ($DxgiFormat -eq 'A8L8') { 'R8G8_UNORM' } else { $DxgiFormat }
    foreach ($group in @($jobs | Group-Object OutputDirectory, Swizzle)) {
        $groupJobs = @($group.Group)
        $outputDirectory = $groupJobs[0].OutputDirectory
        $stageDir = Join-Path $outputDirectory ('.DDSForge-tmp-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stageDir)
        try {
            $texconvArgs = @('-nologo', '-f', $texconvFormat, '-m', $mipCount, '-ft', 'dds', '-o', $stageDir)
            if ($DxgiFormat -eq 'A8L8') { $texconvArgs += '-dx9' }
            $swizzle = [string]$groupJobs[0].Swizzle
            if ($swizzle) { $texconvArgs += '--swizzle'; $texconvArgs += $swizzle }
            $texconvArgs += '-y'
            $texconvArgs += @($groupJobs | ForEach-Object { $_.Input })
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
    $form.Size = New-Object Drawing.Size(680, 560)
    $form.MinimumSize = New-Object Drawing.Size(600, 540)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)

    $title = New-Object Windows.Forms.Label
$title.Text = 'AC Texture Converter'
    $title.Font = New-Object Drawing.Font('Segoe UI Semibold', 19)
    $title.Location = New-Object Drawing.Point(22, 16); $title.Size = New-Object Drawing.Size(400, 36)
    $sub = New-Object Windows.Forms.Label
    $sub.Text = 'Drop DDS or image files here, generate mipmaps, and preserve transparency.'
    $sub.Location = New-Object Drawing.Point(24, 54); $sub.Size = New-Object Drawing.Size(610, 24)

    $list = New-Object Windows.Forms.ListBox
    $list.Location = New-Object Drawing.Point(24, 92); $list.Size = New-Object Drawing.Size(490, 160)
    $list.Anchor = 'Top,Left,Right'
    $list.AllowDrop = $true
    $InitialFiles | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object { [void]$list.Items.Add($_) }
    $add = New-Object Windows.Forms.Button; $add.Text = 'Add files…'; $add.Location = New-Object Drawing.Point(530, 92); $add.Size = New-Object Drawing.Size(105, 32)
    $remove = New-Object Windows.Forms.Button; $remove.Text = 'Remove'; $remove.Location = New-Object Drawing.Point(530, 132); $remove.Size = New-Object Drawing.Size(105, 32)
    $clear = New-Object Windows.Forms.Button; $clear.Text = 'Clear'; $clear.Location = New-Object Drawing.Point(530, 172); $clear.Size = New-Object Drawing.Size(105, 32)

    $fmtLabel = New-Object Windows.Forms.Label; $fmtLabel.Text = 'Output format'; $fmtLabel.Location = New-Object Drawing.Point(24, 270); $fmtLabel.Size = New-Object Drawing.Size(90, 22)
    $format = New-Object Windows.Forms.ComboBox; $format.Location = New-Object Drawing.Point(120, 266); $format.Size = New-Object Drawing.Size(315, 28); $format.DropDownStyle = 'DropDownList'
    foreach ($name in $script:Formats.Keys) { [void]$format.Items.Add($name) }; $format.SelectedItem = 'BC7 RGBA (preserve alpha)'
    $settingsButton = New-Object Windows.Forms.Button; $settingsButton.Text = 'Settings…'; $settingsButton.Location = New-Object Drawing.Point(450, 265); $settingsButton.Size = New-Object Drawing.Size(90, 29)
    $formatHint = New-Object Windows.Forms.Label; $formatHint.Location = New-Object Drawing.Point(120, 297); $formatHint.Size = New-Object Drawing.Size(515, 38); $formatHint.ForeColor = [Drawing.Color]::FromArgb(85, 85, 85)
    $updateFormatHint = { $selected = $script:Formats[$format.SelectedItem]; $formatHint.Text = $script:FormatHints[$selected] }
    $format.add_SelectedIndexChanged($updateFormatHint)
    & $updateFormatHint
    $mipLabel = New-Object Windows.Forms.Label; $mipLabel.Text = 'Mipmaps'; $mipLabel.Location = New-Object Drawing.Point(24, 344); $mipLabel.Size = New-Object Drawing.Size(90, 22)
    $mips = New-Object Windows.Forms.ComboBox; $mips.Location = New-Object Drawing.Point(120, 340); $mips.Size = New-Object Drawing.Size(190, 28); $mips.DropDownStyle = 'DropDownList'
    @('Full chain','None','4 levels','8 levels') | ForEach-Object { [void]$mips.Items.Add($_) }; $mips.SelectedIndex = 0
    $outLabel = New-Object Windows.Forms.Label; $outLabel.Text = 'Output folder'; $outLabel.Location = New-Object Drawing.Point(24, 385); $outLabel.Size = New-Object Drawing.Size(90, 22)
    $outLabelToolTip = New-Object Windows.Forms.ToolTip; $outLabelToolTip.SetToolTip($outLabel, 'Leave blank to save each converted file beside its source file.')
    $outBox = New-Object Windows.Forms.TextBox; $outBox.Location = New-Object Drawing.Point(120, 381); $outBox.Size = New-Object Drawing.Size(395, 25); $outBox.Anchor = 'Top,Left,Right'; $outBox.Text = 'Source folder'; $outBox.ForeColor = [Drawing.Color]::Gray
    $outBox.Add_Enter({ if ($outBox.Text -eq 'Source folder') { $outBox.Clear(); $outBox.ForeColor = [Drawing.SystemColors]::WindowText } })
    $outBox.Add_Leave({ if ([string]::IsNullOrWhiteSpace($outBox.Text)) { $outBox.Text = 'Source folder'; $outBox.ForeColor = [Drawing.Color]::Gray } })
    $browse = New-Object Windows.Forms.Button; $browse.Text = '…'; $browse.Location = New-Object Drawing.Point(530, 378); $browse.Size = New-Object Drawing.Size(105, 30)
    $overwrite = New-Object Windows.Forms.CheckBox; $overwrite.Text = 'Overwrite existing output files'; $overwrite.Location = New-Object Drawing.Point(120, 414); $overwrite.Size = New-Object Drawing.Size(230, 24)
    $backup = New-Object Windows.Forms.CheckBox; $backup.Text = 'Move replaced files to Backup folder'; $backup.Location = New-Object Drawing.Point(360, 414); $backup.Size = New-Object Drawing.Size(275, 24); $backup.Enabled = $false
    $overwrite.Add_CheckedChanged({ $backup.Enabled = $overwrite.Checked; if (-not $overwrite.Checked) { $backup.Checked = $false } })
    $status = New-Object Windows.Forms.Label; $status.Text = 'Ready'; $status.Location = New-Object Drawing.Point(24, 472); $status.Size = New-Object Drawing.Size(400, 24); $status.Anchor = 'Bottom,Left,Right'
    $go = New-Object Windows.Forms.Button; $go.Text = 'Convert'; $go.Location = New-Object Drawing.Point(492, 465); $go.Size = New-Object Drawing.Size(143, 38); $go.Anchor = 'Bottom,Right'; $go.BackColor = [Drawing.Color]::FromArgb(35, 105, 190); $go.ForeColor = [Drawing.Color]::White

    $fileDragEnter = {
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy }
        else { $e.Effect = [Windows.Forms.DragDropEffects]::None }
    }
    $fileDrop = {
        param($sender, $e)
        $supportedExtensions = @('.dds','.png','.tga','.bmp','.jpg','.jpeg','.tif','.tiff','.hdr')
        $added = 0
        foreach ($file in [string[]]$e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
            if ((Test-Path -LiteralPath $file -PathType Leaf) -and ([IO.Path]::GetExtension($file).ToLowerInvariant() -in $supportedExtensions) -and -not $list.Items.Contains($file)) {
                [void]$list.Items.Add($file)
                $added++
            }
        }
        if ($added -gt 0) { $status.Text = "Added $added file(s)." }
        else { $status.Text = 'No new supported files were added.' }
    }
    $form.AllowDrop = $true
    $form.Add_DragEnter($fileDragEnter); $form.Add_DragDrop($fileDrop)
    $list.Add_DragEnter($fileDragEnter); $list.Add_DragDrop($fileDrop)

    $add.Add_Click({ $dialog = New-Object Windows.Forms.OpenFileDialog; $dialog.Filter = 'DDS files (*.dds)|*.dds|Supported images|*.dds;*.png;*.tga;*.bmp;*.jpg;*.jpeg;*.tif;*.tiff;*.hdr|All files (*.*)|*.*'; $dialog.Multiselect = $true; if ($dialog.ShowDialog() -eq 'OK') { foreach ($f in $dialog.FileNames) { if (-not $list.Items.Contains($f)) { [void]$list.Items.Add($f) } } } })
    $remove.Add_Click({ while ($list.SelectedIndices.Count -gt 0) { $list.Items.RemoveAt($list.SelectedIndices[0]) } })
    $clear.Add_Click({ $list.Items.Clear() })
    $browse.Add_Click({ $dialog = New-Object Windows.Forms.FolderBrowserDialog; if ($dialog.ShowDialog() -eq 'OK') { $outBox.Text = $dialog.SelectedPath } })
    $go.Add_Click({
        try {
            $go.Enabled = $false; $status.Text = 'Converting…'; $form.Refresh()
            if ($list.Items.Count -eq 0) { throw 'Add at least one file.' }
            $mipArg = switch ($mips.SelectedIndex) { 1 { 'none' } 2 { '4' } 3 { '8' } default { 'full' } }
            $selectedFormat = $script:Formats[$format.SelectedItem]
            $resolvedOutDir = if ([string]::IsNullOrWhiteSpace($outBox.Text) -or $outBox.Text -eq 'Source folder') { '' } else { [IO.Path]::GetFullPath($outBox.Text) }
            $plannedOutputs = @($list.Items | ForEach-Object { Get-OutputDdsPath ([string]$_) (Resolve-OutputDirectory ([string]$_) $resolvedOutDir) })
            $existingOutputs = @($plannedOutputs | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
            if ($existingOutputs.Count -gt 0) {
                if (-not $overwrite.Checked) { throw 'One or more output files already exist. Enable overwrite or choose a different output folder.' }
                $names = ($existingOutputs | ForEach-Object { [IO.Path]::GetFileName($_) } | Select-Object -Unique | Select-Object -First 12) -join "`r`n"
                $more = if ($existingOutputs.Count -gt 12) { "`r`n…and $($existingOutputs.Count - 12) more." } else { '' }
                $backupNotice = if ($backup.Checked) { "`r`n`r`nThe existing files will first be moved into the Backup subfolder." } else { '' }
                $answer = [Windows.Forms.MessageBox]::Show("These output files already exist and will be replaced:`r`n`r`n$names$more$backupNotice`r`n`r`nContinue?", 'Confirm overwrite', 'YesNo', 'Warning')
                if ($answer -ne [Windows.Forms.DialogResult]::Yes) { $status.Text = 'Conversion cancelled.'; return }
            }
            $n = Invoke-Conversion @($list.Items) $selectedFormat $resolvedOutDir $mipArg $overwrite.Checked $backup.Checked
            $status.Text = "Created $n file(s) successfully."
[Windows.Forms.MessageBox]::Show("Created $n DDS file(s).", 'AC Texture Converter', 'OK', 'Information') | Out-Null
        } catch { $status.Text = 'Conversion failed.'; [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AC Texture Converter', 'OK', 'Error') | Out-Null }
        finally { $go.Enabled = $true }
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
    $form.Controls.AddRange(@($title,$sub,$list,$add,$remove,$clear,$fmtLabel,$format,$settingsButton,$formatHint,$mipLabel,$mips,$outLabel,$outBox,$browse,$overwrite,$backup,$status,$go))
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
    & $assert ((Resolve-A8L8InputSwizzle '' 0 0 0 0 0) -eq 'ra') 'RGBA inputs source A for A8L8 alpha'
    & $assert ((Resolve-A8L8InputSwizzle '' 0 0x20001 16 0xFF 0xFF00) -eq 'rg') 'legacy A8L8 sources preserve their second channel'
    & $assert ((Resolve-A8L8InputSwizzle 'DX10' 49 0 0 0 0) -eq 'rg') 'DXGI R8G8 sources preserve their second channel'
    & $assert (-not [string]::IsNullOrWhiteSpace((Get-DdsProgId))) '.dds shell ProgID is resolved'
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
        if (-not $InputPath.Count) { throw 'No DDS files were passed from Explorer.' }
        foreach ($path in $InputPath) {
            if ([IO.Path]::GetExtension($path) -ine '.dds') { throw "The context menu only supports DDS files: $path" }
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

