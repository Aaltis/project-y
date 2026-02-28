# reinstall.ps1 — Rebuild the customer image and redeploy the Helm chart
#
# Usage: .\scripts\reinstall.ps1 [-SkipBuild] [-HardReset]
#
# Options:
#   -SkipBuild   Skip Gradle build and Docker image rebuild (faster if only YAML changed)
#   -HardReset   Uninstall the Helm release before reinstalling (clears all state including PVCs)

param(
    [switch]$SkipBuild,
    [switch]$HardReset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot       = Resolve-Path "$PSScriptRoot\..\.."
$LogDir = Join-Path $ProjectRoot "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir "reinstall-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
Start-Transcript -Path $LogFile
$DeployPath        = "$ProjectRoot\deployment"
$ValuesFile        = "$DeployPath\values-dev.yaml"
$CustomerSrc       = "$ProjectRoot\Customer"
$GatewaySrc        = "$ProjectRoot\Gateway"
$LogConsumerSrc    = "$ProjectRoot\LogConsumer"
$AccountsSrc       = "$ProjectRoot\Accounts"
$ContactsSrc       = "$ProjectRoot\Contacts"
$OpportunitiesSrc  = "$ProjectRoot\Opportunities"
$ActivitiesSrc     = "$ProjectRoot\Activities"
$ReleaseName       = "project-y"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 1. Build image (unless skipped)
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Step "Pointing Docker CLI at Minikube's daemon..."
    & minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

    function Invoke-Build($name, $srcDir, $tag) {
        Write-Step "Building $name image..."
        Push-Location $srcDir
        try {
            .\gradlew.bat clean build -x test
            if ($LASTEXITCODE -ne 0) { throw "Gradle build failed for $name (exit $LASTEXITCODE)" }
            docker build -t "${tag}:latest" .
            if ($LASTEXITCODE -ne 0) { throw "Docker build failed for $name (exit $LASTEXITCODE)" }
        } finally { Pop-Location }
    }

    Invoke-Build "customer"      $CustomerSrc      "customer"
    Invoke-Build "gateway"       $GatewaySrc       "gateway"
    Invoke-Build "log-consumer"  $LogConsumerSrc   "log-consumer"
    Invoke-Build "accounts"      $AccountsSrc      "accounts"
    Invoke-Build "contacts"      $ContactsSrc      "contacts"
    Invoke-Build "opportunities" $OpportunitiesSrc "opportunities"
    Invoke-Build "activities"    $ActivitiesSrc    "activities"

    Write-Host "All images built." -ForegroundColor Green
} else {
    Write-Host "Skipping image builds (-SkipBuild)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 2. Helm uninstall + install  OR  helm upgrade
# ---------------------------------------------------------------------------
if ($HardReset) {
    Write-Step "Hard reset: uninstalling '$ReleaseName'..."
    $releaseExists = helm list -q | Select-String -Pattern "^$ReleaseName$"
    if ($releaseExists) {
        helm uninstall $ReleaseName
        Write-Host "Uninstalled. Waiting for pods to terminate..."
        Start-Sleep -Seconds 10
    }
    Write-Step "Installing '$ReleaseName'..."
    helm install $ReleaseName $DeployPath -f $ValuesFile --timeout 10m
} else {
    Write-Step "Upgrading '$ReleaseName'..."
    $releaseExists = helm list -q | Select-String -Pattern "^$ReleaseName$"
    if ($releaseExists) {
        helm upgrade $ReleaseName $DeployPath -f $ValuesFile --timeout 10m
    } else {
        helm install $ReleaseName $DeployPath -f $ValuesFile --timeout 10m
    }
}

# ---------------------------------------------------------------------------
# 3. Rollout status
# ---------------------------------------------------------------------------
Write-Step "Waiting for RabbitMQ..."
kubectl rollout status deployment/rabbitmq --timeout=3m

Write-Step "Waiting for Keycloak..."
kubectl rollout status deployment/keycloak --timeout=5m

Write-Step "Waiting for Customer API..."
kubectl rollout status deployment/customer --timeout=3m

Write-Step "Waiting for Gateway..."
kubectl rollout status deployment/gateway --timeout=3m

Write-Step "Waiting for Log Consumer..."
kubectl rollout status deployment/log-consumer --timeout=3m

Write-Step "Waiting for Accounts..."
kubectl rollout status deployment/accounts --timeout=3m

Write-Step "Waiting for Contacts..."
kubectl rollout status deployment/contacts --timeout=3m

Write-Step "Waiting for Opportunities..."
kubectl rollout status deployment/opportunities --timeout=3m

Write-Step "Waiting for Activities..."
kubectl rollout status deployment/activities --timeout=3m

# ---------------------------------------------------------------------------
# 4. Ensure port-forward is running
# ---------------------------------------------------------------------------
Write-Step "Ensuring port-forward is active..."
& "$PSScriptRoot\port-forward.ps1" status | Out-Null
if ($LASTEXITCODE -ne 0) {
    & "$PSScriptRoot\port-forward.ps1" start
}

Write-Host ""
Write-Host "Reinstall complete." -ForegroundColor Green
Write-Host "  http://localhost:8080/auth/admin  (admin / admin)"
Write-Host "  http://localhost:8080/api/customers/..."
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Stop-Transcript
