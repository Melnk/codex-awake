#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIGURATION=debug "$SCRIPT_DIR/build_app.sh"
open -n "$SCRIPT_DIR/../dist/CodexAwake.app"
