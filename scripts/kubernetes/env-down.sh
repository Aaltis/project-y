#!/usr/bin/env bash
# env-down.sh — Stop the development environment
#
# Usage: ./scripts/env-down.sh [--stop-minikube]
#
# Options:
#   --stop-minikube   Also stop the Minikube VM (slower restart next time)

set -uo pipefail   # no -e: clean up as much as possible even on errors

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_NAME="project-y"
STOP_MINIKUBE=false

for arg in "$@"; do
    case $arg in
        --stop-minikube) STOP_MINIKUBE=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

step() { echo ""; echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Stop port-forward
# ---------------------------------------------------------------------------
step "Stopping port-forward..."
"$SCRIPT_DIR/port-forward.sh" stop || true

# ---------------------------------------------------------------------------
# 2. Uninstall Helm release
# ---------------------------------------------------------------------------
step "Uninstalling Helm release..."
if helm list -q | grep -q "^$RELEASE_NAME$"; then
    helm uninstall "$RELEASE_NAME"
    echo "Helm release uninstalled."
else
    echo "No active Helm release found — skipping."
fi

# ---------------------------------------------------------------------------
# 3. Minikube (optional)
# ---------------------------------------------------------------------------
if [ "$STOP_MINIKUBE" = true ]; then
    step "Stopping Minikube..."
    minikube stop
    echo "Minikube stopped."
else
    echo ""
    echo "Minikube is still running. Use --stop-minikube to shut it down."
fi

echo ""
echo "Environment down."
