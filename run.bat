@echo off
setlocal
cd /d "%~dp0"

if not exist "backend\venv\Scripts\python.exe" (
  echo Python venv not found. Run install.bat first.
  pause
  exit /b 1
)

where bun >nul 2>&1
if errorlevel 1 (
  echo ERROR: Bun not found. Install Bun from https://bun.sh
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; ^
   Set-Location '%CD%'; ^
   $python = Join-Path (Get-Location) 'backend\venv\Scripts\python.exe'; ^
   & bun run setup:dev; ^
   if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; ^
   $backendJob = $null; ^
   try { ^
     $null = Invoke-WebRequest -Uri 'http://127.0.0.1:17493/health' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; ^
     Write-Host 'Backend already running on http://localhost:17493'; ^
   } catch { ^
     Write-Host 'Starting backend on http://localhost:17493 ...'; ^
     $backendJob = Start-Process -PassThru -NoNewWindow -FilePath $python -ArgumentList @('-m','uvicorn','backend.main:app','--reload','--port','17493'); ^
     Start-Sleep -Seconds 2; ^
   }; ^
   Write-Host 'Starting Tauri desktop app...'; ^
   try { ^
     Set-Location 'tauri'; ^
     & bun run tauri dev; ^
     exit $LASTEXITCODE; ^
   } finally { ^
     if ($backendJob) { ^
       taskkill /PID $backendJob.Id /T /F 2>$null | Out-Null; ^
     } ^
   }"

set EXIT_CODE=%ERRORLEVEL%
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
