#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIGURATION="${CONFIGURATION:-release}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "CONFIGURATION must be debug or release" >&2; exit 64 ;;
esac

echo "Building CodexAwake ($CONFIGURATION)…"
swift build --disable-sandbox --configuration "$CONFIGURATION" --product CodexAwake
BIN_DIR="$(swift build --disable-sandbox --configuration "$CONFIGURATION" --show-bin-path)"
APP="$PROJECT_ROOT/dist/CodexAwake.app"

if [[ -e "$APP" ]]; then
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 0755 "$BIN_DIR/CodexAwake" "$APP/Contents/MacOS/CodexAwake"
install -m 0644 "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
