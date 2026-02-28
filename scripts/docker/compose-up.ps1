# compose-up.ps1 — Build Gradle JARs, build Docker images, start the Compose stack
#
# Usage:
#   .\scripts\docker\compose-up.ps1                                   # build all + start detached
#   .\scripts\docker\compose-up.ps1 -SkipBuild                        # skip Gradle; rebuild images + start
#   .\scripts\docker\compose-up.ps1 -Foreground                       # stream logs (blocks)
#   .\scripts\docker\compose-up.ps1 -Services gateway,contacts,activities  # partial rebuild (Gradle + Docker + restart only listed services)
#
# IMPORTANT: The Dockerfiles are single-stage — they only copy a pre-built JAR from build/libs/.
# Running `docker compose up --build -d <service>` directly will NOT re-run Gradle, so the image
# will contain the old JAR. Always use this script (or manually run gradlew before docker compose).

param(
    [switch]$SkipBuild,
    [switch]$Foreground,
    [string[]]$Services = @()   # if set, only rebuild + restart the listed service(s)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$LogDir = Join-Path $ProjectRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "compose-up-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $LogFile

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# Map of service name (as used in docker-compose.yml) to its source directory
$ServiceDirs = @{
    "customer"      = "$ProjectRoot\Customer"
    "gateway"       = "$ProjectRoot\Gateway"
    "log-consumer"  = "$ProjectRoot\LogConsumer"
    "accounts"      = "$ProjectRoot\Accounts"
    "contacts"      = "$ProjectRoot\Contacts"
    "opportunities" = "$ProjectRoot\Opportunities"
    "activities"    = "$ProjectRoot\Activities"
}

# ---------------------------------------------------------------------------
# 1. Build Gradle JARs (into host Docker daemon — no minikube docker-env needed)
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    function Invoke-GradleBuild($name, $srcDir) {
        Write-Step "Building $name JAR..."
        Push-Location $srcDir
        try {
            .\gradlew.bat clean build -x test
            if ($LASTEXITCODE -ne 0) { throw "Gradle build failed for $name (exit $LASTEXITCODE)" }
        } finally { Pop-Location }
    }

    if ($Services.Count -gt 0) {
        foreach ($svc in $Services) {
            $svcLower = $svc.ToLower()
            if ($ServiceDirs.ContainsKey($svcLower)) {
                Invoke-GradleBuild $svc $ServiceDirs[$svcLower]
            } else {
                Write-Host "  Warning: unknown service '$svc' - skipping Gradle build" -ForegroundColor Yellow
            }
        }
    } else {
        foreach ($entry in $ServiceDirs.GetEnumerator()) {
            Invoke-GradleBuild $entry.Key $entry.Value
        }
    }

    Write-Host "JARs built." -ForegroundColor Green
} else {
    Write-Host "Skipping Gradle builds (-SkipBuild)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 2. docker compose up --build
# ---------------------------------------------------------------------------
Write-Step "Starting Docker Compose stack (building images)..."
Push-Location $ProjectRoot
try {
    # --progress plain suppresses Docker Desktop's interactive TUI (which exits with code 1
    # in non-interactive terminals like VS Code's PowerShell). It must come after "compose"
    # but before the subcommand ("up") — it is a global docker compose option, not an up flag.
    $upArgs = @("compose", "--progress", "plain", "up", "--build")
    if ($Services.Count -gt 0) {
        # Partial rebuild: only restart the listed services
        $upArgs += $Services
    }
    if (-not $Foreground) { $upArgs += "-d" }
    & docker @upArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host ""
if ($Services.Count -gt 0) {
    Write-Host "Services rebuilt and restarted: $($Services -join ', ')" -ForegroundColor Green
} else {
    Write-Host "Stack started." -ForegroundColor Green
    Write-Host "  API:            http://localhost:8080/api/..."
    Write-Host "  Keycloak admin: http://localhost:8080/auth/admin  (keycloak / keycloak)"
    Write-Host "  RabbitMQ UI:    http://localhost:15672            (guest / guest)"
}
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Stop-Transcript
