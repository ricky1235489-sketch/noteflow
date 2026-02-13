<#
.SYNOPSIS
    NoteFlow 一鍵開發啟動腳本
.DESCRIPTION
    自動啟動後端 API（Python）和前端 Flutter Web，不需要 WSL。
    首次執行會自動安裝依賴。
.USAGE
    .\dev.ps1           # 啟動後端 + 前端
    .\dev.ps1 backend   # 只啟動後端
    .\dev.ps1 frontend  # 只啟動前端
    .\dev.ps1 setup     # 只安裝依賴（不啟動）
#>
param(
    [string]$Mode = "all"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ApiDir = Join-Path $ProjectRoot "noteflow_api"
$AppDir = Join-Path $ProjectRoot "noteflow_app"
$VenvDir = Join-Path $ApiDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$VenvPip = Join-Path $VenvDir "Scripts\pip.exe"

# ── Colors ──
function Write-Step($msg) { Write-Host "`n▸ $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }

# ── Check Prerequisites ──
function Test-Prerequisites {
    Write-Step "檢查開發環境"

    # Python
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Err "找不到 Python。請安裝 Python 3.12+: https://python.org/downloads"
        exit 1
    }
    $pyVer = python --version 2>&1
    Write-OK "Python: $pyVer"

    # Flutter (only if needed)
    if ($Mode -in "all", "frontend") {
        $fl = Get-Command flutter -ErrorAction SilentlyContinue
        if (-not $fl) {
            Write-Err "找不到 Flutter。請安裝: https://docs.flutter.dev/get-started/install"
            exit 1
        }
        $flVer = flutter --version 2>&1 | Select-Object -First 1
        Write-OK "Flutter: $flVer"
    }
}

# ── Setup Backend ──
function Install-Backend {
    Write-Step "設定後端 (Python)"

    if (-not (Test-Path $VenvPython)) {
        Write-Host "  建立虛擬環境..." -ForegroundColor Gray
        python -m venv $VenvDir
        Write-OK "虛擬環境建立完成"
    } else {
        Write-OK "虛擬環境已存在"
    }

    Write-Host "  安裝 Python 依賴..." -ForegroundColor Gray
    & $VenvPip install --quiet --upgrade pip
    & $VenvPip install --quiet -r (Join-Path $ApiDir "requirements.txt")

    # Install optional ML dependencies
    Write-Host "  安裝 AI 模型依賴 (torch + transformers)..." -ForegroundColor Gray
    & $VenvPip install --quiet torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu 2>$null
    & $VenvPip install --quiet transformers 2>$null
    & $VenvPip install --quiet basic-pitch 2>$null
    & $VenvPip install --quiet aiosqlite 2>$null

    Write-OK "後端依賴安裝完成"
}

# ── Setup Frontend ──
function Install-Frontend {
    Write-Step "設定前端 (Flutter)"

    Push-Location $AppDir
    try {
        flutter pub get --no-example 2>$null
        Write-OK "Flutter 依賴安裝完成"
    } finally {
        Pop-Location
    }
}

# ── Start Backend ──
function Start-Backend {
    Write-Step "啟動後端 API (http://localhost:8000)"

    $env:PYTHONPATH = $ApiDir
    Push-Location $ApiDir
    try {
        Start-Process -FilePath $VenvPython `
            -ArgumentList "-m", "uvicorn", "app.main:app", "--reload", "--port", "8000", "--host", "0.0.0.0" `
            -WorkingDirectory $ApiDir `
            -NoNewWindow:$false
        Write-OK "後端已啟動 → http://localhost:8000/docs"
    } finally {
        Pop-Location
    }
}

# ── Start Frontend ──
function Start-Frontend {
    Write-Step "啟動前端 Flutter Web (http://localhost:3000)"

    Push-Location $AppDir
    try {
        Start-Process -FilePath "flutter" `
            -ArgumentList "run", "-d", "chrome", "--web-port", "3000" `
            -WorkingDirectory $AppDir `
            -NoNewWindow:$false
        Write-OK "前端已啟動 → http://localhost:3000"
    } finally {
        Pop-Location
    }
}

# ── Main ──
Write-Host ""
Write-Host "╔══════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║     NoteFlow Dev Environment     ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════╝" -ForegroundColor Magenta

Test-Prerequisites

switch ($Mode) {
    "setup" {
        Install-Backend
        Install-Frontend
        Write-Host "`n✅ 設定完成！執行 .\dev.ps1 啟動開發環境" -ForegroundColor Green
    }
    "backend" {
        Install-Backend
        Start-Backend
    }
    "frontend" {
        Install-Frontend
        Start-Frontend
    }
    "all" {
        Install-Backend
        Install-Frontend
        Start-Backend
        Start-Frontend
        Write-Host ""
        Write-Host "═══════════════════════════════════════" -ForegroundColor Green
        Write-Host " 🎵 NoteFlow 開發環境已啟動！" -ForegroundColor Green
        Write-Host ""
        Write-Host "   後端 API:  http://localhost:8000/docs" -ForegroundColor White
        Write-Host "   前端 App:  http://localhost:3000" -ForegroundColor White
        Write-Host ""
        Write-Host "   按 Ctrl+C 或關閉終端視窗停止" -ForegroundColor Gray
        Write-Host "═══════════════════════════════════════" -ForegroundColor Green
    }
    default {
        Write-Err "未知模式: $Mode"
        Write-Host "用法: .\dev.ps1 [all|backend|frontend|setup]"
    }
}
