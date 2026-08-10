#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
export XDG_CACHE_HOME="$PROJECT_ROOT/.build/swiftpm-cache"
mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE" "$XDG_CACHE_HOME"
