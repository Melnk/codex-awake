#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CODEX_EXECUTABLE="${CODEX_BINARY:-$(command -v codex || true)}"
[[ -n "$CODEX_EXECUTABLE" && -x "$CODEX_EXECUTABLE" ]] || {
    echo "Codex CLI not found. Set CODEX_BINARY to an executable path." >&2
    exit 1
}

PROBE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codexawake-probe.XXXXXX")"
SOCKET_PATH="$PROBE_ROOT/server.sock"
SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$PROBE_ROOT"
}
trap cleanup EXIT
chmod 0700 "$PROBE_ROOT"

"$CODEX_EXECUTABLE" app-server --listen "unix://$SOCKET_PATH" >"$PROBE_ROOT/stdout.log" 2>"$PROBE_ROOT/stderr.log" &
SERVER_PID=$!
for _ in {1..100}; do
    [[ -S "$SOCKET_PATH" ]] && break
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "App Server exited before creating its socket" >&2; exit 1; }
    sleep 0.05
done
[[ -S "$SOCKET_PATH" ]] || { echo "Timed out waiting for App Server socket" >&2; exit 1; }

echo "Running initialize/initialized and read-only thread reconciliation. No model prompt is sent."
swift run --disable-sandbox CodexAwakeProtocolProbe "$SOCKET_PATH"
