param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'ACTextureConverter'
$choiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.dds\UserChoice')
$progId = if ($choiceKey) { try { [string]$choiceKey.GetValue('ProgId') } finally { $choiceKey.Dispose() } } else { '' }
if ([string]::IsNullOrWhiteSpace($progId)) {
    $extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('.dds')
    $progId = if ($extensionKey) { try { [string]$extensionKey.GetValue('') } finally { $extensionKey.Dispose() } } else { '' }
}
$validProgId = -not [string]::IsNullOrWhiteSpace($progId) -and -not $progId.StartsWith('\') -and -not $progId.EndsWith('\') -and $progId.Split('\') -notcontains '..'
$key = if ($validProgId) { "HKCU:\Software\Classes\$progId\shell\ACTextureConverter" } else { '' }
$legacyMenuKey = 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell\ACTextureConverter'
$createdRoot = $false
$createdKey = $false

try {
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'Windows has no usable .dds file type identifier.' }
    if (Test-Path -LiteralPath $installRoot) {
        throw "The installation folder already exists; nothing was overwritten: $installRoot. Run Uninstall-ACTextureConverter.bat first or back up/rename the folder."
    }
    $legacyRoot = Join-Path $env:LOCALAPPDATA 'DDSForge'
    $legacyKey = 'HKCU:\Software\Classes\SystemFileAssociations\.dds\shell\DDSForge'
    if ((Test-Path -LiteralPath $legacyRoot) -or (Test-Path -LiteralPath $legacyKey)) {
        throw 'A previous DDS Forge installation was found. Run Uninstall-ACTextureConverter.bat to remove its app files and Explorer entry, then install again. Your Texconv package and format settings are kept.'
    }
    if ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath $legacyMenuKey)) {
        throw "The context-menu entry already exists; nothing was overwritten: $key. Run Uninstall.ps1 first."
    }

    $sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $portableRoot = Join-Path $sourceRoot 'AC Texture Converter Portable'
    $portableExe = Join-Path $sourceRoot 'AC Texture Converter Portable\AC Texture Converter.exe'
    $localTexconv = Join-Path $sourceRoot 'texconv.exe'
    $portableTexconv = Join-Path $portableRoot 'texconv.exe'
    $wingetLink = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\texconv.exe'
    $texconvCommand = Get-Command texconv.exe -ErrorAction SilentlyContinue
    $texconvToBundle = if ($texconvCommand) { $texconvCommand.Source } elseif (Test-Path -LiteralPath $localTexconv) { $localTexconv } elseif (Test-Path -LiteralPath $wingetLink) { $wingetLink } else { $null }
    if (-not $texconvToBundle) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget -and (Test-Path -LiteralPath $portableTexconv -PathType Leaf)) {
            $texconvToBundle = $portableTexconv
            Write-Host 'Texconv will use the bundled copy. Install the Microsoft Visual C++ 2015–2022 x64 runtime if it is not already present.'
        }
        if (-not $winget -and -not $texconvToBundle) { throw 'winget was not found. Install Microsoft DirectXTex Texconv manually or place texconv.exe next to Install.ps1, then run the installer again.' }

        if ($texconvToBundle) { $winget = $null }
        if ($winget) {

        Write-Host "Checking winget: $($winget.Source)"
        try {
            $versionText = & $winget.Source --version 2>&1
            if ($LASTEXITCODE -ne 0) { throw "winget --version exited with code $LASTEXITCODE. $versionText" }
        } catch {
            throw "winget is present but could not be started. Install Texconv using the official instructions or place texconv.exe next to Install.ps1. Details: $($_.Exception.Message)"
        }

        Write-Host 'Installing Microsoft DirectXTex Texconv…'
        try {
            & $winget.Source install --id Microsoft.DirectXTex.Texconv --exact --accept-source-agreements --accept-package-agreements
            $installCode = $LASTEXITCODE
        } catch {
            throw "winget could not complete the Texconv installation: $($_.Exception.Message)"
        }
        if ($installCode -ne 0) { throw "Texconv installation failed (winget exit code $installCode). No app files were installed." }
        $texconvCommand = Get-Command texconv.exe -ErrorAction SilentlyContinue
        if ($texconvCommand) { $texconvToBundle = $texconvCommand.Source }
        elseif (Test-Path -LiteralPath $wingetLink) { $texconvToBundle = $wingetLink }
        elseif (Test-Path -LiteralPath $portableTexconv) { $texconvToBundle = $portableTexconv }
        }
    } else {
        Write-Host 'Texconv is already available.'
    }

    New-Item -ItemType Directory -Path $installRoot | Out-Null
    $createdRoot = $true
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'ACTextureConverter.ps1') -Destination $installRoot
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'Open-ACTextureConverter.bat') -Destination $installRoot
    if (Test-Path -LiteralPath $portableExe -PathType Leaf) {
        Copy-Item -LiteralPath $portableExe -Destination (Join-Path $installRoot 'AC Texture Converter.exe')
    }
    if ($texconvToBundle) { Copy-Item -LiteralPath $texconvToBundle -Destination (Join-Path $installRoot 'texconv.exe') }

    $createdKey = $true
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installRoot 'ACTextureConverter.ps1') -RegisterContextMenu
    if ($LASTEXITCODE -ne 0) { throw "Could not register the Explorer context menu (exit code $LASTEXITCODE)." }

    Write-Host "AC Texture Converter installed: $installRoot" -ForegroundColor Green
    Write-Host 'The entry appears in the Explorer context menu for DDS files (on Windows 11, it may be under “Show more options”).'
    if (-not $NoPause) { Write-Host 'Press any key to close this window.'; try { [void][Console]::ReadKey($true) } catch { } }
} catch {
    Write-Host ''
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($createdKey -and (Test-Path -LiteralPath $key)) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue }
    if ($createdRoot -and (Test-Path -LiteralPath $installRoot)) { Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (-not $NoPause) { Write-Host 'Press any key to close this window.'; try { [void][Console]::ReadKey($true) } catch { } }
    exit 1
}
