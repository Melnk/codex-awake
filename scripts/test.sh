#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "Running CodexAwake unit and fake-server integration tests…"
swift test --disable-sandbox
