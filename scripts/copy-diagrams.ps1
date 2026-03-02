param (
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

$src = Join-Path $ProjectRoot "docs"
$dst = Join-Path $ProjectRoot "Frontend\public\diagrams"

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }

foreach ($name in @("architecture.png", "database.png")) {
    $srcFile = Join-Path $src $name
    $dstFile = Join-Path $dst $name
    if (Test-Path $srcFile) {
        Copy-Item $srcFile $dstFile -Force
        Write-Host "  Copied $name" -ForegroundColor Green
    } else {
        Write-Host "  Warning: $srcFile not found (run render-diagrams.ps1 first)" -ForegroundColor Yellow
    }
}
