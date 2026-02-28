#!/usr/bin/env bash
# reinstall.sh — Rebuild the customer image and redeploy the Helm chart
#
# Usage: ./scripts/reinstall.sh [--skip-build] [--hard-reset]
#
# Options:
#   --skip-build   Skip Gradle build and Docker image rebuild (faster if only YAML changed)
#   --hard-reset   Uninstall the Helm release before reinstalling (clears all state)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_PATH="$PROJECT_ROOT/deployment"
VALUES_FILE="$DEPLOY_PATH/values-dev.yaml"
CUSTOMER_SRC="$PROJECT_ROOT/Customer"
GATEWAY_SRC="$PROJECT_ROOT/Gateway"
LOG_CONSUMER_SRC="$PROJECT_ROOT/LogConsumer"
RELEASE_NAME="project-y"

SKIP_BUILD=false
HARD_RESET=false

for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
        --hard-reset) HARD_RESET=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

step() { echo ""; echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Build image (unless skipped)
# ---------------------------------------------------------------------------
if [ "$SKIP_BUILD" = false ]; then
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
else
    echo "Skipping image builds (--skip-build)."
fi

# ---------------------------------------------------------------------------
# 2. Helm uninstall + install  OR  helm upgrade
# ---------------------------------------------------------------------------
if [ "$HARD_RESET" = true ]; then
    step "Hard reset: uninstalling '$RELEASE_NAME'..."
    if helm list -q | grep -q "^$RELEASE_NAME$"; then
        helm uninstall "$RELEASE_NAME"
        echo "Uninstalled. Waiting for pods to terminate..."
        sleep 10
    fi
    step "Installing '$RELEASE_NAME'..."
    helm install "$RELEASE_NAME" "$DEPLOY_PATH" -f "$VALUES_FILE" --timeout 10m
else
    step "Upgrading '$RELEASE_NAME'..."
    if helm list -q | grep -q "^$RELEASE_NAME$"; then
        helm upgrade "$RELEASE_NAME" "$DEPLOY_PATH" -f "$VALUES_FILE" --timeout 10m
    else
        helm install "$RELEASE_NAME" "$DEPLOY_PATH" -f "$VALUES_FILE" --timeout 10m
    fi
fi

# ---------------------------------------------------------------------------
# 3. Rollout status
# ---------------------------------------------------------------------------
step "Waiting for RabbitMQ..."
kubectl rollout status deployment/rabbitmq --timeout=3m

step "Waiting for Keycloak..."
kubectl rollout status deployment/keycloak --timeout=5m

step "Waiting for Customer API..."
kubectl rollout status deployment/customer --timeout=3m

step "Waiting for Gateway..."
kubectl rollout status deployment/gateway --timeout=3m

step "Waiting for Log Consumer..."
kubectl rollout status deployment/log-consumer --timeout=3m

# ---------------------------------------------------------------------------
# 4. Ensure port-forward is running
# ---------------------------------------------------------------------------
step "Ensuring port-forward is active..."
if ! "$SCRIPT_DIR/port-forward.sh" status >/dev/null 2>&1; then
    "$SCRIPT_DIR/port-forward.sh" start
fi

echo ""
echo "Reinstall complete."
echo "  http://localhost:8080/auth/admin  (admin / admin)"
echo "  http://localhost:8080/api/customers/..."
