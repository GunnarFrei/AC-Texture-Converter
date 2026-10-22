@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-ACTextureConverter.ps1"
if errorlevel 1 (
  echo.
  echo Repair did not complete successfully.
  pause
)
endlocal
