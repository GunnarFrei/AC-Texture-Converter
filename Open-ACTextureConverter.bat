@echo off
if exist "%~dp0AC Texture Converter.exe" (
    start "" "%~dp0AC Texture Converter.exe" %*
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ACTextureConverter.ps1" %*
