@echo off
setlocal
cd /d "%~dp0"

echo.
echo Voicebox - Install
echo ==================
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell not found.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-windows.ps1"
set EXIT_CODE=%ERRORLEVEL%

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Install failed with exit code %EXIT_CODE%.
  echo Scroll up for the error details.
  pause
  exit /b %EXIT_CODE%
)

echo.
pause
exit /b 0
