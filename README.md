# AC Texture Converter

A Windows tool for converting DDS textures and common image files for Assetto Corsa modding workflows.

## Features and formats

- Convert individual files or batches with the GUI, drag and drop, command line, or the DDS Explorer context menu.
- Generate mipmaps and choose how transparency is handled.
- Choose common AC formats: BC1 (opaque RGB), BC3, BC7 RGBA, opaque BC7, A8L8 (grayscale plus alpha), and uncompressed RGBA8.
- Enable additional formats in Settings: BC2, BC4, BC5, and BC6H.
- Save beside the source or to another folder. Existing files are protected by default; optional overwrite and backup controls are available.

BC7 DDS support is documented for Custom Shaders Patch (CSP) from version 0.1.74-preview3 (build 1434). Earlier CSP versions may not support it. A8L8 is a legacy luminance-plus-alpha DDS format; compatibility can depend on the Assetto Corsa and CSP versions and the texture loading path.

## Install

1. Download [AC-Texture-Converter-Windows-with-icon.zip](AC-Texture-Converter-Windows-with-icon.zip) and extract it.
2. Run `Install-ACTextureConverter.bat` and follow the prompts. The installer sets up the app and its per-user DDS Explorer context menu.
3. Right-click a DDS file to open the AC Texture Converter menu. On Windows 11, it may be under **Show more options**. You can also start the app with `Open-ACTextureConverter.bat`.

To remove the app, run `Uninstall-ACTextureConverter.bat`.

## Licenses

The bundled Microsoft DirectXTex `texconv.exe` is licensed under the MIT License. Its full notice is in [ThirdPartyNotices.txt](ThirdPartyNotices.txt).

The AC Texture Converter project does not currently include a separate license for its own source code.

