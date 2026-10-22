# AC Texture Converter

A small Windows utility for converting DDS and common image files to DDS. The GUI uses Microsoft DirectXTex `texconv` as its codec backend. The backend is MIT-licensed and installed separately through `winget`.

## Install

1. Use Windows 10/11 with PowerShell 5.1 and `winget`.
2. When upgrading from DDS Forge, first run `Uninstall-ACTextureConverter.bat`. It removes the old app files and Explorer entry while keeping Texconv and format settings.
3. Double-click `Install-ACTextureConverter.bat`. It installs `Microsoft.DirectXTex.Texconv` if needed, copies `texconv.exe` next to the app, and registers a per-user `.dds` Explorer context-menu entry. Errors stay visible in the PowerShell window.
4. Right-click one or more DDS files and open the **AC Texture Converter** submenu. It contains the app launcher and grouped conversion actions. The cascade is registered for the current Windows `.dds` handler and its fallback file type. On Windows 11, the entry may be under **Show more options**.
5. You can also launch the GUI with `Open-ACTextureConverter.bat`. When the portable launcher has been built, this opens the Windows `.exe`; otherwise it uses the PowerShell script.

## Portable executable

Run `Build-Portable.ps1` to create an `AC Texture Converter Portable` folder. It contains the Windows launcher `.exe`, the app script, `texconv.exe`, and the app icon. Keep the files together. To rebuild an existing package after changing the app or icon, pass `-Rebuild`; the old generated files are saved in `BuildBackups` first. The launcher uses Windows PowerShell 5.1, which is included with Windows 10/11. Run `AC Texture Converter.exe` to open the GUI. The standard installer also copies the launcher into `%LOCALAPPDATA%\ACTextureConverter` when the portable build is present, so `Open-ACTextureConverter.bat` starts the `.exe` after installation.

## Share with other users

Run `Build-Distribution.ps1` to create `AC-Texture-Converter-Windows.zip`. It contains only the app, portable runtime files, installation/repair/removal scripts, and third-party notices; it excludes the local `DDS-Converted` folder. Recipients extract the archive and run `Install-ACTextureConverter.bat`. Texconv is bundled; the installer can use `winget` to install its Microsoft Visual C++ runtime dependency when needed. The portable app requires that runtime to be present on Windows.

To update an existing installation and repair the Explorer menu, run `Repair-ACTextureConverter.bat` from this folder. It backs up the installed app files before updating them and re-registering the menu. When the portable executable is present, the Explorer menu launches it directly. For a clean reinstall, run `Uninstall-ACTextureConverter.bat`, then `Install-ACTextureConverter.bat`.

If `winget` is unavailable, install `Microsoft.DirectXTex.Texconv` separately using the [official texconv instructions](https://github.com/microsoft/DirectXTex/wiki/texconv), or place `texconv.exe` next to `Install-ACTextureConverter.bat` before running the installer.

## Use

The GUI accepts DDS and common image files through **Add files…** or by dragging them onto the main window or file list. The default output list includes BC1, BC2, BC3, both BC7 alpha choices, uncompressed RGBA8, and classic A8L8. BC7 has two explicit choices: **BC7 RGBA (preserve alpha)** and **BC7 (opaque; remove transparency)**. The opaque choice forces alpha to 1 before encoding. The format hint identifies **CSP 0.1.74-preview3 (build 1434)** as the first documented CSP version with BC7 DDS support; verify compatibility with the exact game and loader setup. Use **Settings…** to choose which formats appear in the output list, including optional BC4, BC5, and BC6H; preferences are saved per user in `%APPDATA%\DDSForge\settings.json`. The selected format's hint appears in the main window and when hovering over a format in Settings. Choose a full mip chain, no mipmaps, 4 levels, or 8 levels. Leave **Output folder** blank to save each result beside its source file; any `Backup` folder is created beside that source. If you choose an output folder, converted files and backups go there. Existing outputs are protected by default. Enable **Overwrite existing output files** to replace them after a confirmation prompt; optionally select **Move replaced files to Backup folder** to preserve the old files under `Backup`. Duplicate input filenames targeting the same folder are rejected.

The Explorer context menu is organized into submenus. Open the **AC Texture Converter** submenu to find **Open AC Texture Converter**, which loads the selected DDS files in the GUI. **Overwrite original** contains the enabled format choices and asks for confirmation before replacing source files. **Overwrite with Backup** also asks for confirmation, then moves each original into its source folder's `Backup` subfolder first. The format choices in both groups follow **Settings…**. You can select multiple DDS files before using a command; Explorer runs the selected action once for each file, so overwrite actions ask for confirmation per file.

CLI examples (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\albedo.dds -Format BC7_UNORM -Mipmaps full -OutputDirectory .\out
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\normal.png -Format BC5_UNORM -Mipmaps 1 -OutputDirectory .\out
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\texture.png -Format BC7_OPAQUE
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\grayscale-alpha.png -Format A8L8 -Mipmaps full
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\albedo.png -Format BC7_UNORM -Overwrite
powershell -ExecutionPolicy Bypass -File .\ACTextureConverter.ps1 -InputPath .\albedo.png -Format BC7_UNORM -BackupOriginals
```

Supported CLI formats: `BC1_UNORM`, `BC2_UNORM`, `BC3_UNORM`, `BC4_UNORM`, `BC5_UNORM`, `BC6H_UF16`, `BC7_UNORM`, `R8G8B8A8_UNORM`, and `A8L8`. `BC1_UNORM` produces opaque RGB and ignores source alpha; use BC3 or BC7 RGBA when transparency must be preserved. `-Overwrite` allows replacement of existing outputs; `-BackupOriginals` also moves the previous files into a `Backup` subfolder and implies `-Overwrite`. If `-OutputDirectory` is omitted, output and backup folders are beside each input file. The GUI always asks for confirmation before replacing existing outputs. The GUI's **BC7 (opaque; remove transparency)** choice is also available as `-Format BC7_OPAQUE`; it forces alpha to 1 before encoding. This guarantees an opaque decoded result, but does not force RGB-only BC7 block modes: the encoder may still explicitly encode alpha, even when every decoded alpha value is fully opaque. BC7 uses 16 bytes per 4×4 block whether the selected block mode encodes alpha explicitly or implies alpha as 1. `R8G8B8A8_UNORM` writes an uncompressed 32-bit RGBA DDS. `A8L8` writes a classic uncompressed 16-bit DDS with a legacy DX9 pixel-format header. The luminance channel comes from source red; for A8L8 or R8G8 DDS sources, the existing second channel is preserved as alpha, and ordinary RGBA/image sources use source alpha. `-Mipmaps full` generates a full mip chain, `none` writes only the top level, and a positive number sets the mip count. DDS-to-DDS conversions preserve the source extension's letter case; other image inputs use `.DDS`. BC6H is intended for HDR textures (such as `.hdr`), has no alpha, and is usually not a good choice for standard LDR/RGBA images.

Alpha is preserved by default. BC1 only supports 1-bit transparency; use BC2, BC3, or BC7 for smooth transparency. BC4 stores one channel, and BC5 stores two channels, making it useful for normal maps. Choose the opaque BC7 entry to remove transparency from BC7 output.

The available Assetto Corsa texture-pipeline documentation recommends `AL (8.8, alpha luminance)` for grayscale textures with fine gradients. CSP release notes also mention a newer DDS loader for legacy formats such as L8 and LA88. This supports offering A8L8, though compatibility may depend on the Assetto Corsa/CSP version and texture-loading path. The CSP changelog archive records BC7 DDS support in 0.1.74-preview3, build 1434, published 2021-02-24. Sources: [Assetto Corsa Texturing Guidelines](https://wiki.acmods.cn/en/pipeline/06-texturing-guidelines.html), [CSP 0.1.74-preview3 changelog](https://c1xtz.github.io/csp-logs/0-1-74p3/), [DirectXTex DDS formats](https://github.com/microsoft/DirectXTex/wiki/DDS-I-O-Functions), [CSP note on the vintage texture loader](https://c1xtz.github.io/csp-logs/0-3-0p634/).

## Tests and uninstall

Run the self-tests with `powershell -ExecutionPolicy Bypass -File .\Test-ACTextureConverter.ps1`. To remove AC Texture Converter, double-click `Uninstall-ACTextureConverter.bat`. The separate Texconv package remains installed.

## Limitations

This project folder does not contain PhotoCraft source code. AC Texture Converter is a standalone utility and does not modify PhotoCraft. The context-menu entry is registered for `.dds` files; other supported image formats can be added in the app.
