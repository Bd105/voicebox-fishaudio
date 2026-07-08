@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo Voicebox - Install
echo ==================
echo.

where python >nul 2>&1
if errorlevel 1 (
  echo ERROR: Python not found.
  echo Install Python 3.11 or 3.12 from https://www.python.org/downloads/
  exit /b 1
)

where bun >nul 2>&1
if errorlevel 1 (
  echo ERROR: Bun not found.
  echo Install Bun from https://bun.sh
  exit /b 1
)

if not exist "backend\venv" (
  echo Creating Python virtual environment...
  python -m venv backend\venv
  if errorlevel 1 (
    echo ERROR: Failed to create virtual environment.
    exit /b 1
  )
)

set "PYTHON=backend\venv\Scripts\python.exe"
set "PIP=backend\venv\Scripts\pip.exe"

echo Upgrading pip...
"%PYTHON%" -m pip install --upgrade pip -q
if errorlevel 1 exit /b 1

echo Detecting GPU and installing PyTorch...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$gpus = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name; ^
   Write-Host ('Detected GPUs: ' + ($gpus -join ', ')); ^
   $hasNvidia = @($gpus | Where-Object { $_ -match 'NVIDIA' }).Count -gt 0; ^
   $hasIntelArc = @($gpus | Where-Object { $_ -match 'Arc' }).Count -gt 0; ^
   $pip = '%PIP%'; ^
   if ($hasNvidia) { ^
     Write-Host 'NVIDIA GPU detected - installing PyTorch with CUDA support...'; ^
     & $pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128; ^
     if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } ^
   } elseif ($hasIntelArc) { ^
     Write-Host 'Intel Arc GPU detected - installing PyTorch with XPU support...'; ^
     & $pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/xpu; ^
     if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; ^
     & $pip install intel-extension-for-pytorch --index-url https://download.pytorch.org/whl/xpu; ^
     if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } ^
   } else { ^
     Write-Host 'No NVIDIA or Intel Arc GPU detected - using CPU-only PyTorch from requirements.txt.'; ^
   }"
if errorlevel 1 exit /b 1

echo Installing Python dependencies...
"%PIP%" install -r backend\requirements.txt
if errorlevel 1 exit /b 1

echo Installing engine packages...
"%PIP%" install --no-deps chatterbox-tts
if errorlevel 1 exit /b 1
"%PIP%" install --no-deps hume-tada
if errorlevel 1 exit /b 1
"%PIP%" install git+https://github.com/QwenLM/Qwen3-TTS.git
if errorlevel 1 exit /b 1
"%PIP%" install pyinstaller ruff pytest pytest-asyncio -q
if errorlevel 1 exit /b 1

echo Installing JavaScript dependencies...
call bun install
if errorlevel 1 exit /b 1

echo Preparing Tauri dev sidecars...
call bun run setup:dev
if errorlevel 1 exit /b 1

echo.
echo Setup complete!
echo Run run.bat to start the backend and desktop app.
echo.
exit /b 0
