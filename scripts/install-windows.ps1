#Requires -Version 5.1
<#
.SYNOPSIS
  Voicebox Windows install - mirrors just setup without requiring just.
#>
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

try {
  # $PSScriptRoot is ...\scripts when invoked via install.bat
  $Root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
  if (-not (Test-Path (Join-Path $Root "backend\requirements.txt"))) {
    if (Test-Path (Join-Path (Get-Location) "backend\requirements.txt")) {
      $Root = (Get-Location).Path
    } else {
      throw "Could not find repo root (backend\requirements.txt missing). Run install.bat from the Voicebox repo root."
    }
  }

  Set-Location $Root
  Write-Host ""
  Write-Host "Voicebox - Install"
  Write-Host "=================="
  Write-Host "Repo: $Root"
  Write-Host ""

  function Get-LastExit {
    if (Test-Path variable:LASTEXITCODE) { return $LASTEXITCODE }
    return 0
  }

  function Assert-Ok {
    param([string]$Label)
    $code = Get-LastExit
    if ($code -ne 0) { throw "$Label failed (exit $code)" }
  }

  function Find-BunPath {
    $cmd = Get-Command "bun" -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
      (Join-Path $env:USERPROFILE ".bun\bin\bun.exe"),
      (Join-Path $env:LOCALAPPDATA "bun\bin\bun.exe"),
      (Join-Path $env:ProgramFiles "bun\bin\bun.exe"),
      (Join-Path ${env:ProgramFiles(x86)} "bun\bin\bun.exe")
    )
    foreach ($path in $candidates) {
      if ($path -and (Test-Path $path)) { return $path }
    }
    return $null
  }

  function Ensure-Bun {
    $bunPath = Find-BunPath
    if ($bunPath) {
      $bunDir = Split-Path -Parent $bunPath
      if ($env:Path -notlike ("*" + $bunDir + "*")) {
        $env:Path = $bunDir + ";" + $env:Path
      }
      Write-Host ("Found Bun: " + $bunPath)
      return $bunPath
    }

    Write-Host "Bun not found. Installing Bun from https://bun.sh ..."
    Write-Host "(This downloads and installs Bun for the current user.)"
    try {
      # Official Windows installer from bun.sh
      Invoke-RestMethod -Uri "https://bun.sh/install.ps1" | Invoke-Expression
    } catch {
      throw ("Automatic Bun install failed: " + $_.Exception.Message + ". Install manually from https://bun.sh then re-run install.bat.")
    }

    # Installer typically puts bun in %USERPROFILE%\.bun\bin
    $bunHome = Join-Path $env:USERPROFILE ".bun\bin"
    if (Test-Path $bunHome) {
      $env:Path = $bunHome + ";" + $env:Path
    }
    # Also refresh from Machine/User PATH in case installer updated it
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machinePath -or $userPath) {
      $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
    }

    $bunPath = Find-BunPath
    if (-not $bunPath) {
      throw "Bun was installed but bun.exe was not found. Close this window, open a new terminal, and re-run install.bat. Or install from https://bun.sh"
    }
    Write-Host ("Installed Bun: " + $bunPath)
    return $bunPath
  }

  function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
      throw "$Name not found. $Hint"
    }
  }

  function Resolve-Python {
    # Prefer the py launcher (avoids the Windows Store python stub).
    $candidates = @(
      @{ Cmd = "py"; Args = @("-3.12") },
      @{ Cmd = "py"; Args = @("-3.11") },
      @{ Cmd = "py"; Args = @("-3") },
      @{ Cmd = "python"; Args = @() },
      @{ Cmd = "python3"; Args = @() }
    )
    foreach ($c in $candidates) {
      $cmd = Get-Command $c.Cmd -ErrorAction SilentlyContinue
      if (-not $cmd) { continue }
      try {
        $versionArgs = @($c.Args) + @("-c", "import sys; print('%d.%d' % (sys.version_info.major, sys.version_info.minor))")
        $ver = & $c.Cmd @versionArgs 2>$null
        if (-not $ver) { continue }
        $ver = "$ver".Trim()
        if ($ver -notmatch '^\d+\.\d+$') { continue }
        $minor = [int]($ver.Split(".")[1])
        if ($minor -gt 13) {
          Write-Host "Warning: Python $ver detected. ML packages may not be compatible. Prefer 3.11 or 3.12."
        }
        return @{ Cmd = $c.Cmd; Args = @($c.Args); Version = $ver }
      } catch {
        continue
      }
    }
    throw "Python 3.11+ not found. Install from https://www.python.org/downloads/ and enable Add python.exe to PATH."
  }

  Assert-Command "git" "Install Git from https://git-scm.com/download/win"
  $BunExe = Ensure-Bun

  $py = Resolve-Python
  $pyLabel = $py.Cmd
  if ($py.Args.Count -gt 0) { $pyLabel = "$($py.Cmd) $($py.Args -join ' ')" }
  Write-Host "Using Python $($py.Version) via $pyLabel"
  Write-Host ""

  $venvDir = Join-Path $Root "backend\venv"
  $venvPython = Join-Path $venvDir "Scripts\python.exe"

  if (-not (Test-Path $venvPython)) {
    Write-Host "Creating Python virtual environment..."
    & $py.Cmd @($py.Args + @("-m", "venv", $venvDir))
    Assert-Ok "Creating virtual environment"
    if (-not (Test-Path $venvPython)) {
      throw "venv created but python.exe missing at $venvPython"
    }
  } else {
    Write-Host "Reusing existing venv: $venvDir"
  }

  Write-Host "Upgrading pip..."
  & $venvPython -m pip install --upgrade pip -q
  Assert-Ok "pip upgrade"

  # GPU-aware PyTorch (same logic as justfile setup-python on Windows)
  Write-Host "Detecting GPU..."
  $gpus = @()
  try {
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name)
  } catch {
    Write-Host "Could not query GPUs ($($_.Exception.Message)); assuming CPU."
  }
  if ($gpus.Count -gt 0) {
    Write-Host ("Detected GPUs: " + ($gpus -join ", "))
  } else {
    Write-Host "Detected GPUs: (none)"
  }

  $hasNvidia = @($gpus | Where-Object { $_ -match "NVIDIA" }).Count -gt 0
  $hasIntelArc = @($gpus | Where-Object { $_ -match "Arc" }).Count -gt 0

  if ($hasNvidia) {
    Write-Host "NVIDIA GPU detected - installing PyTorch with CUDA support..."
    & $venvPython -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
    Assert-Ok "CUDA PyTorch install"
  } elseif ($hasIntelArc) {
    Write-Host "Intel Arc GPU detected - installing PyTorch with XPU support..."
    & $venvPython -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/xpu
    Assert-Ok "XPU PyTorch install"
    & $venvPython -m pip install intel-extension-for-pytorch --index-url https://download.pytorch.org/whl/xpu
    Assert-Ok "intel-extension-for-pytorch install"
  } else {
    Write-Host "No NVIDIA or Intel Arc GPU detected - CPU PyTorch will come from requirements.txt."
  }

  Write-Host "Installing Python dependencies from backend\requirements.txt..."
  Write-Host "(This can take several minutes.)"
  & $venvPython -m pip install -r (Join-Path $Root "backend\requirements.txt")
  Assert-Ok "requirements.txt install"

  Write-Host "Installing engine packages..."
  & $venvPython -m pip install --no-deps chatterbox-tts
  Assert-Ok "chatterbox-tts install"
  & $venvPython -m pip install --no-deps hume-tada
  Assert-Ok "hume-tada install"
  & $venvPython -m pip install "git+https://github.com/QwenLM/Qwen3-TTS.git"
  Assert-Ok "Qwen3-TTS install (needs Git + network)"
  & $venvPython -m pip install pyinstaller ruff pytest pytest-asyncio -q
  Assert-Ok "dev tooling install"

  Write-Host "Installing JavaScript dependencies (bun install)..."
  & $BunExe install
  Assert-Ok "bun install"

  Write-Host "Preparing Tauri dev sidecars..."
  if (-not (Get-Command "rustc" -ErrorAction SilentlyContinue)) {
    Write-Host "Warning: rustc not found. Sidecar placeholders may use a fallback triple."
    Write-Host "Install Rust from https://rustup.rs for full Tauri desktop builds."
  }
  & $BunExe run setup:dev
  Assert-Ok "setup:dev"

  Write-Host ""
  Write-Host "Setup complete!"
  Write-Host "Run run.bat to start the backend and desktop app."
  Write-Host ""
  exit 0
} catch {
  Write-Host ""
  Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  if ($_.ScriptStackTrace) {
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
  }
  exit 1
}
