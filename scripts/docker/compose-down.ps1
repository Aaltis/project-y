# compose-down.ps1 — Stop the Docker Compose stack
#
# Usage:
#   .\scripts\docker\compose-down.ps1           # stop and remove containers (keep volumes)
#   .\scripts\docker\compose-down.ps1 -Volumes  # also remove volumes (wipes all data)

param([switch]$Volumes)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."

Push-Location $ProjectRoot
try {
    $downArgs = @("compose", "down")
    if ($Volumes) { $downArgs += "-v" }
    & docker @downArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose down failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host "Stack stopped." -ForegroundColor Green
if ($Volumes) { Write-Host "Volumes removed - all data cleared." -ForegroundColor Yellow }
