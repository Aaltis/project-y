# env-up.ps1 — Full environment setup from scratch
#
# Usage: .\scripts\env-up.ps1
#
# What it does:
#   1. Start Minikube (skips if already running)
#   2. Enable ingress + storage addons
#   3. Build all service images into Minikube's Docker daemon
#   4. Helm install or upgrade the chart
#   5. Start port-forward in background (localhost:8080)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot    = Resolve-Path "$PSScriptRoot\..\.."
$DeployPath     = "$ProjectRoot\deployment"
$ValuesFile     = "$DeployPath\values-dev.yaml"
$ReleaseName    = "project-y"
$LogDir = Join-Path $ProjectRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "env-up-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $LogFile

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Invoke-Build($name, $srcDir, $tag) {
    Write-Step "Building $name image..."
    Push-Location $srcDir
    try {
        .\gradlew.bat clean build -x test
        if ($LASTEXITCODE -ne 0) { throw "Gradle build failed for $name (exit $LASTEXITCODE)" }
        docker build -t "${tag}:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Docker build failed for $name (exit $LASTEXITCODE)" }
        Write-Host "$name image built." -ForegroundColor Green
    } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# 1. Minikube
# ---------------------------------------------------------------------------
Write-Step "Checking Minikube status..."

# minikube status exits non-zero when stopped/missing; must not let it throw
$status = ""
try {
    $status = & minikube status --format "{{.Host}}" 2>$null
} catch {
    $status = ""
}

if ($status -eq "Running") {
    Write-Host "Minikube already running - skipping start." -ForegroundColor Yellow
} else {
    Write-Step "Starting Minikube..."
    minikube start --memory=8192 --cpus=4 --disk-size=20g
}

# ---------------------------------------------------------------------------
# 2. Addons
# ---------------------------------------------------------------------------
Write-Step "Enabling addons..."
minikube addons enable ingress
minikube addons enable default-storageclass

# ---------------------------------------------------------------------------
# 3. Build images inside Minikube's Docker daemon
# ---------------------------------------------------------------------------
Write-Step "Pointing Docker CLI at Minikube's daemon..."
& minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

Invoke-Build "customer"      "$ProjectRoot\Customer"       "customer"
Invoke-Build "gateway"       "$ProjectRoot\Gateway"        "gateway"
Invoke-Build "log-consumer"  "$ProjectRoot\LogConsumer"    "log-consumer"
Invoke-Build "accounts"      "$ProjectRoot\Accounts"       "accounts"
Invoke-Build "contacts"      "$ProjectRoot\Contacts"       "contacts"
Invoke-Build "opportunities" "$ProjectRoot\Opportunities"  "opportunities"
Invoke-Build "activities"    "$ProjectRoot\Activities"     "activities"

# ---------------------------------------------------------------------------
# 4. Helm install / upgrade
# ---------------------------------------------------------------------------
Write-Step "Deploying with Helm..."

$releaseExists = helm list -q | Select-String -Pattern "^$ReleaseName$"

if ($releaseExists) {
    Write-Host "Upgrading existing release '$ReleaseName'..."
    helm upgrade $ReleaseName $DeployPath -f $ValuesFile --timeout 10m
} else {
    Write-Host "Installing release '$ReleaseName'..."
    helm install $ReleaseName $DeployPath -f $ValuesFile --timeout 10m
}

# ---------------------------------------------------------------------------
# 5. Wait for key pods
# ---------------------------------------------------------------------------
Write-Step "Waiting for Keycloak to be ready (this takes ~2 minutes)..."
kubectl rollout status deployment/keycloak --timeout=5m

Write-Step "Waiting for Gateway to be ready..."
kubectl rollout status deployment/gateway --timeout=3m

# ---------------------------------------------------------------------------
# 6. Port-forward
# ---------------------------------------------------------------------------
Write-Step "Starting port-forward on localhost:8080..."
& "$PSScriptRoot\port-forward.ps1" start

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Environment is up." -ForegroundColor Green
Write-Host ""
Write-Host "  Keycloak admin : http://localhost:8080/auth/admin  (admin / admin)"
Write-Host "  Token endpoint : POST http://localhost:8080/auth/realms/crm/protocol/openid-connect/token"
Write-Host "    Body: grant_type=password&client_id=crm-api&username=testuser&password=testpassword"
Write-Host ""
Write-Host "Import postman-collection.json in Postman to test."
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Stop-Transcript
