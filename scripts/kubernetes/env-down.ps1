# env-down.ps1 — Stop the development environment
#
# Usage: .\scripts\env-down.ps1 [-StopMinikube]
#
# Options:
#   -StopMinikube   Also stop the Minikube VM (slower restart next time)

param(
    [switch]$StopMinikube
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"   # non-fatal - clean up as much as possible

$LogDir = Join-Path $PSScriptRoot "..\..\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "env-down-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $LogFile

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 1. Stop port-forward
# ---------------------------------------------------------------------------
Write-Step "Stopping port-forward..."
& "$PSScriptRoot\port-forward.ps1" stop

# ---------------------------------------------------------------------------
# 2. Uninstall Helm release
# ---------------------------------------------------------------------------
Write-Step "Uninstalling Helm release..."
$releaseExists = helm list -q | Select-String -Pattern "^project-y$"
if ($releaseExists) {
    helm uninstall project-y
    Write-Host "Helm release uninstalled." -ForegroundColor Green
} else {
    Write-Host "No active Helm release found - skipping." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 3. Minikube (optional)
# ---------------------------------------------------------------------------
if ($StopMinikube) {
    Write-Step "Stopping Minikube..."
    minikube stop
    Write-Host "Minikube stopped." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Minikube is still running. Use '-StopMinikube' to shut it down." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Environment down." -ForegroundColor Green
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Stop-Transcript
