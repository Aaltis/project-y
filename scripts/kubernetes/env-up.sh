#!/usr/bin/env bash
# env-up.sh — Full environment setup from scratch
#
# Usage: ./scripts/env-up.sh
#
# What it does:
#   1. Start Minikube (skips if already running)
#   2. Enable ingress + storage addons
#   3. Build the customer image into Minikube's Docker daemon
#   4. Helm install or upgrade the chart
#   5. Start port-forward in background (localhost:8080)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_PATH="$PROJECT_ROOT/deployment"
VALUES_FILE="$DEPLOY_PATH/values-dev.yaml"
CUSTOMER_SRC="$PROJECT_ROOT/Customer"
GATEWAY_SRC="$PROJECT_ROOT/Gateway"
LOG_CONSUMER_SRC="$PROJECT_ROOT/LogConsumer"
RELEASE_NAME="project-y"

step() { echo ""; echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Minikube
# ---------------------------------------------------------------------------
step "Checking Minikube status..."

if minikube status --format "{{.Host}}" 2>/dev/null | grep -q "Running"; then
    echo "Minikube already running — skipping start."
else
    step "Starting Minikube..."
    minikube start --memory=8192 --cpus=4 --disk-size=20g
fi

# ---------------------------------------------------------------------------
# 2. Addons
# ---------------------------------------------------------------------------
step "Enabling addons..."
minikube addons enable ingress
minikube addons enable default-storageclass

# ---------------------------------------------------------------------------
# 3. Build images inside Minikube's Docker daemon
# ---------------------------------------------------------------------------
eval "$(minikube docker-env)"

step "Building customer image..."
pushd "$CUSTOMER_SRC" > /dev/null
./gradlew clean build -x test
docker build -t customer:latest .
popd > /dev/null

step "Building gateway image..."
pushd "$GATEWAY_SRC" > /dev/null
./gradlew clean build -x test
docker build -t gateway:latest .
popd > /dev/null

step "Building log-consumer image..."
pushd "$LOG_CONSUMER_SRC" > /dev/null
./gradlew clean build -x test
docker build -t log-consumer:latest .
popd > /dev/null
echo "All images built."

# ---------------------------------------------------------------------------
# 4. Helm install / upgrade
# ---------------------------------------------------------------------------
step "Deploying with Helm..."

if helm list -q | grep -q "^$RELEASE_NAME$"; then
    echo "Upgrading existing release '$RELEASE_NAME'..."
    helm upgrade "$RELEASE_NAME" "$DEPLOY_PATH" -f "$VALUES_FILE" --timeout 10m
else
    echo "Installing release '$RELEASE_NAME'..."
    helm install "$RELEASE_NAME" "$DEPLOY_PATH" -f "$VALUES_FILE" --timeout 10m
fi

# ---------------------------------------------------------------------------
# 5. Wait for key pods
# ---------------------------------------------------------------------------
step "Waiting for RabbitMQ to be ready..."
kubectl rollout status deployment/rabbitmq --timeout=3m

step "Waiting for Keycloak to be ready (this takes ~2 minutes)..."
kubectl rollout status deployment/keycloak --timeout=5m

step "Waiting for Customer API to be ready..."
kubectl rollout status deployment/customer --timeout=3m

step "Waiting for Gateway to be ready..."
kubectl rollout status deployment/gateway --timeout=3m

step "Waiting for Log Consumer to be ready..."
kubectl rollout status deployment/log-consumer --timeout=3m

# ---------------------------------------------------------------------------
# 6. Port-forward
# ---------------------------------------------------------------------------
step "Starting port-forward on localhost:8080..."
"$SCRIPT_DIR/port-forward.sh" start

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Environment is up."
echo ""
echo "  Keycloak admin : http://localhost:8080/auth/admin  (admin / admin)"
echo "  Token endpoint : POST http://localhost:8080/auth/realms/TTB/protocol/openid-connect/token"
echo "  Customer API   : http://localhost:8080/api/customers/..."
echo "  RabbitMQ UI    : kubectl port-forward svc/rabbitmq 15672:15672  ->  http://localhost:15672 (guest/guest)"
echo "  Logs DB        : kubectl exec -it deployment/postgres-logs -- psql -U loguser -d logsdb -c 'SELECT * FROM request_log;'"
echo ""
echo "Import postman-collection.json in Postman to test."
