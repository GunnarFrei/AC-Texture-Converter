param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
$packageRoot = Join-Path $sourceRoot 'AC Texture Converter Portable'
$launcherSource = Join-Path $sourceRoot 'Launcher\ACTextureConverterLauncher.cs'
$iconBuilder = Join-Path $sourceRoot 'Create-AppIcon.ps1'
$iconPath = Join-Path $sourceRoot 'Assets\ACTextureConverter.ico'
$appScript = Join-Path $sourceRoot 'ACTextureConverter.ps1'
$projectLicense = Join-Path $sourceRoot 'LICENSE'
$thirdPartyNotices = Join-Path $sourceRoot 'ThirdPartyNotices.txt'
$targetScript = Join-Path $packageRoot 'ACTextureConverter.ps1'
$targetExe = Join-Path $packageRoot 'AC Texture Converter.exe'
$targetTexconv = Join-Path $packageRoot 'texconv.exe'

if ((Test-Path -LiteralPath $packageRoot) -and -not $Rebuild) {
    throw "The output folder already exists; nothing was changed: $packageRoot"
}
if (-not (Test-Path -LiteralPath $appScript -PathType Leaf)) { throw "App script not found: $appScript" }
foreach ($licenseFile in @($projectLicense,$thirdPartyNotices)) {
    if (-not (Test-Path -LiteralPath $licenseFile -PathType Leaf)) { throw "License notice not found: $licenseFile" }
}
if (-not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) { throw "Launcher source not found: $launcherSource" }
if ($Rebuild) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconBuilder -Force
    if ($LASTEXITCODE -ne 0) { throw "Icon generation failed (exit code $LASTEXITCODE)." }
} elseif (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $iconBuilder
    if ($LASTEXITCODE -ne 0) { throw "Icon generation failed (exit code $LASTEXITCODE)." }
}

$texconvCommand = Get-Command texconv.exe -ErrorAction SilentlyContinue
$localTexconv = Join-Path $sourceRoot 'texconv.exe'
$texconvPath = if ($texconvCommand) { $texconvCommand.Source } elseif (Test-Path -LiteralPath $localTexconv) { $localTexconv } else { $null }
if (-not $texconvPath -or -not (Test-Path -LiteralPath $texconvPath -PathType Leaf)) {
    throw 'Texconv was not found. Install Microsoft DirectXTex Texconv or place texconv.exe beside Build-Portable.ps1.'
}

$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $compiler) { throw 'The .NET Framework C# compiler was not found.' }

$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('ACTC-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildRoot | Out-Null
try {
    $builtExe = Join-Path $buildRoot 'AC Texture Converter.exe'
    $compileArgs = @(
        '/nologo', '/target:winexe', '/platform:x64', '/optimize+',
        "/out:`"$builtExe`"", "/win32icon:`"$iconPath`"", "/reference:System.Windows.Forms.dll", "/reference:System.dll",
        "`"$launcherSource`""
    )
    & $compiler @compileArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
        throw "Launcher compilation failed (exit code $LASTEXITCODE)."
    }

    if (Test-Path -LiteralPath $packageRoot) {
        $allowed = @('AC Texture Converter.exe','ACTextureConverter.ps1','README.txt','texconv.exe','ACTextureConverter.ico','LICENSE','ThirdPartyNotices.txt')
        $unexpected = @(Get-ChildItem -LiteralPath $packageRoot -Force | Where-Object { $_.Name -notin $allowed })
        if ($unexpected.Count) { throw "The output folder contains additional items and was left untouched: $packageRoot" }
        $backupRoot = Join-Path $sourceRoot ('BuildBackups\Portable-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        if (Test-Path -LiteralPath $backupRoot) { throw "Build backup already exists; nothing was changed: $backupRoot" }
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $packageRoot -Force | Copy-Item -Destination $backupRoot -Recurse
    } else {
        New-Item -ItemType Directory -Path $packageRoot | Out-Null
    }

    Copy-Item -LiteralPath $appScript -Destination $targetScript -Force
    Copy-Item -LiteralPath $texconvPath -Destination $targetTexconv -Force
    Copy-Item -LiteralPath $iconPath -Destination (Join-Path $packageRoot 'ACTextureConverter.ico') -Force
    Copy-Item -LiteralPath $projectLicense -Destination (Join-Path $packageRoot 'LICENSE') -Force
    Copy-Item -LiteralPath $thirdPartyNotices -Destination (Join-Path $packageRoot 'ThirdPartyNotices.txt') -Force
    Copy-Item -LiteralPath $builtExe -Destination $targetExe -Force

    $readme = @'
AC Texture Converter v0.9.1 - Portable build

Run "AC Texture Converter.exe" to open the app. Drop DDS or supported image files onto the window, or use Add files.

Keep this folder together: the executable starts ACTextureConverter.ps1, and texconv.exe performs the texture conversion. Windows PowerShell 5.1 and the Microsoft Visual C++ 2015-2022 x64 runtime are required.

AC Texture Converter is licensed under MIT; see LICENSE. Texconv is also MIT-licensed; see ThirdPartyNotices.txt.

The portable copy does not install an Explorer menu entry. To use the existing Explorer integration, run the project's Install-ACTextureConverter.bat. That installation remains separate from this portable folder.
'@
    Set-Content -LiteralPath (Join-Path $packageRoot 'README.txt') -Value $readme -Encoding UTF8
    Write-Host "Portable package created: $packageRoot"
    Write-Host 'To check the launcher, run: & "AC Texture Converter.exe" -SelfTest'
}
catch {
    Write-Error $_
    throw "Portable package creation did not complete. Review the output folder and any backup before removing anything: $packageRoot"
}
finally {
    if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
}

