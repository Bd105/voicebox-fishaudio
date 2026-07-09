#Requires -Version 5.1
<#
.SYNOPSIS
  Voicebox Windows run - mirrors just dev without requiring just.
#>
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
  $Root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
  if (-not (Test-Path (Join-Path $Root "backend\venv\Scripts\python.exe"))) {
    if (Test-Path (Join-Path (Get-Location) "backend\venv\Scripts\python.exe")) {
      $Root = (Get-Location).Path
    } else {
      throw "Python venv not found. Run install.bat first."
    }
  }

  Set-Location $Root

  if (-not (Get-Command "bun" -ErrorAction SilentlyContinue)) {
    throw "Bun not found. Install Bun from https://bun.sh"
  }

  function Get-LastExit {
    if (Test-Path variable:LASTEXITCODE) { return $LASTEXITCODE }
    return 0
  }

  $python = Join-Path $Root "backend\venv\Scripts\python.exe"

  Write-Host "Preparing Tauri dev sidecars..."
  & bun run setup:dev
  $code = Get-LastExit
  if ($code -ne 0) { throw "setup:dev failed (exit $code)" }

  $backendJob = $null
  try {
    $null = Invoke-WebRequest -Uri "http://127.0.0.1:17493/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
    Write-Host "Backend already running on http://localhost:17493"
  } catch {
    Write-Host "Starting backend on http://localhost:17493 ..."
    $backendJob = Start-Process -PassThru -NoNewWindow -FilePath $python -ArgumentList @(
      "-m", "uvicorn", "backend.main:app", "--reload", "--port", "17493"
    )
    Start-Sleep -Seconds 2
  }

  Write-Host "Starting Tauri desktop app..."
  try {
    Set-Location (Join-Path $Root "tauri")
    & bun run tauri dev
    exit (Get-LastExit)
  } finally {
    if ($null -ne $backendJob) {
      taskkill /PID $backendJob.Id /T /F 2>$null | Out-Null
    }
  }
} catch {
  Write-Host ""
  Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
