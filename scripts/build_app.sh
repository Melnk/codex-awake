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
swift build --disable-sandbox --configuration "$CONFIGURATION" --product CodexAwakeClosedLidHelper
BIN_DIR="$(swift build --disable-sandbox --configuration "$CONFIGURATION" --show-bin-path)"
APP="$PROJECT_ROOT/dist/CodexAwake.app"
HELPER_LABEL="com.melnikoleg.CodexAwake.ClosedLidHelper"

if [[ -e "$APP" ]]; then
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/PrivilegedHelperTools"
install -m 0755 "$BIN_DIR/CodexAwake" "$APP/Contents/MacOS/CodexAwake"
install -m 0755 "$BIN_DIR/CodexAwakeClosedLidHelper" "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
install -m 0644 "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
install -m 0644 "$PROJECT_ROOT/Resources/$HELPER_LABEL.plist" "$APP/Contents/Resources/$HELPER_LABEL.plist"
install -m 0755 "$PROJECT_ROOT/Resources/install-closed-lid-helper.sh" "$APP/Contents/Resources/install-closed-lid-helper.sh"
install -m 0755 "$PROJECT_ROOT/Resources/uninstall-closed-lid-helper.sh" "$APP/Contents/Resources/uninstall-closed-lid-helper.sh"

codesign --force --sign - --timestamp=none --identifier "$HELPER_LABEL" "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
