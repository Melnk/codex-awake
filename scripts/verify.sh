#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APP="$PROJECT_ROOT/dist/CodexAwake.app"
[[ -d "$APP" ]] || { echo "Missing $APP; run scripts/build_app.sh first" >&2; exit 1; }

plutil -lint "$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == "com.melnikoleg.CodexAwake" ]]
[[ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" == "true" ]]
[[ -x "$APP/Contents/MacOS/CodexAwake" ]]
codesign --verify --deep --strict "$APP"
git diff --check

if find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.git" -prune -o -path "$PROJECT_ROOT/.build" -prune -o -path "$PROJECT_ROOT/dist" -prune -o -type f \( -name '*.sock' -o -name '.env' -o -name 'auth.json' \) -print | grep -q .; then
    echo "Unsafe runtime or credential-shaped file found in project" >&2
    exit 1
fi

echo "Verification passed: bundle metadata, signature, diff hygiene, and secret-shaped files"
