# render-diagrams.ps1 — Re-render all PlantUML diagrams in docs/
#
# Requires Docker (used to run the official plantuml/plantuml image).
# No local PlantUML or Java install needed.
#
# Usage:
#   .\scripts\render-diagrams.ps1          # renders all .puml files in docs/
#   .\scripts\render-diagrams.ps1 -Format svg  # SVG output instead of PNG

param(
    [ValidateSet("png", "svg", "pdf")]
    [string]$Format = "png"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$DocsDir     = Join-Path $ProjectRoot "docs"

$PumlFiles = @(Get-ChildItem -Path $DocsDir -Filter "*.puml")

if ($PumlFiles.Count -eq 0) {
    Write-Host "No .puml files found in $DocsDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Rendering $($PumlFiles.Count) diagram(s) as $($Format.ToUpper())..." -ForegroundColor Cyan

foreach ($file in $PumlFiles) {
    Write-Host "  $($file.Name) ... " -NoNewline

    # Mount only the docs directory; plantuml writes output next to the input file.
    # PowerShell path needs forward slashes for Docker volume mounts.
    $mountPath = $DocsDir.ToString().Replace('\', '/')

    docker run --rm `
        -v "${mountPath}:/data" `
        plantuml/plantuml `
        "-t$Format" `
        "/data/$($file.Name)"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED" -ForegroundColor Red
        throw "plantuml render failed for $($file.Name) (exit $LASTEXITCODE)"
    }

    $outName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + ".$Format"
    Write-Host "→ $outName" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Output written to $DocsDir" -ForegroundColor Green
