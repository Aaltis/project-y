#!/usr/bin/env bash
# port-forward.sh — Manage kubectl port-forward for ingress-nginx in the background
#
# Usage:
#   ./port-forward.sh start    — Start port-forward in background (auto-restarts on drop)
#   ./port-forward.sh stop     — Stop the background port-forward
#   ./port-forward.sh status   — Show whether it is running

set -euo pipefail

PID_FILE="/tmp/kube-port-forward.pid"
LOG_FILE="/tmp/kube-port-forward.log"
PORT=8080
SVC="svc/ingress-nginx-controller"
NS="ingress-nginx"

is_running() {
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) || return 1
    kill -0 "$pid" 2>/dev/null
}

case "${1:-}" in

    start)
        if is_running; then
            echo "Already running (PID $(cat "$PID_FILE")). Use 'stop' first to restart."
            exit 0
        fi

        # Check port is free
        if lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo "Error: port $PORT is already in use."
            exit 1
        fi

        # Background loop: restart port-forward automatically when it drops
        (
            while true; do
                echo "[$(date '+%T')] Starting port-forward $SVC $PORT:80 -n $NS" >> "$LOG_FILE"
                kubectl port-forward "$SVC" "${PORT}:80" -n "$NS" >> "$LOG_FILE" 2>&1 || true
                echo "[$(date '+%T')] port-forward exited, restarting in 2s..." >> "$LOG_FILE"
                sleep 2
            done
        ) &

        echo $! > "$PID_FILE"
        echo "Port-forward started in background (PID $!)."
        echo "Traffic on http://localhost:$PORT is now routed to $SVC."
        echo "Logs: $LOG_FILE"
        ;;

    stop)
        if ! is_running; then
            echo "No running port-forward found."
            rm -f "$PID_FILE"
            exit 0
        fi

        pid=$(cat "$PID_FILE")

        # Kill the wrapper loop and any kubectl child it spawned
        pkill -P "$pid" kubectl 2>/dev/null || true
        kill "$pid" 2>/dev/null || true

        rm -f "$PID_FILE"
        echo "Port-forward stopped."
        ;;

    status)
        if is_running; then
            echo "Running (PID $(cat "$PID_FILE")) — http://localhost:$PORT"
            echo "Logs: $LOG_FILE"
        else
            echo "Not running."
            rm -f "$PID_FILE"
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
