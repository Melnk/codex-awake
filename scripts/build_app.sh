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
swift build --disable-sandbox --configuration "$CONFIGURATION" --product CodexAwakeWidget
BIN_DIR="$(swift build --disable-sandbox --configuration "$CONFIGURATION" --show-bin-path)"
APP="$PROJECT_ROOT/dist/CodexAwake.app"
WIDGET="$APP/Contents/PlugIns/CodexAwakeWidget.appex"
HELPER_LABEL="com.melnikoleg.CodexAwake.ClosedLidHelper"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ -e "$APP" ]]; then
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
    "$APP/Contents/Library/PrivilegedHelperTools"
mkdir -p "$WIDGET/Contents/MacOS"
install -m 0755 "$BIN_DIR/CodexAwake" "$APP/Contents/MacOS/CodexAwake"
install -m 0755 "$BIN_DIR/CodexAwakeClosedLidHelper" "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
install -m 0755 "$BIN_DIR/CodexAwakeWidget" "$WIDGET/Contents/MacOS/CodexAwakeWidget"
install -m 0644 "$PROJECT_ROOT/Resources/CodexAwakeWidget-Info.plist" "$WIDGET/Contents/Info.plist"
install -m 0644 "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
install -m 0644 "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
install -m 0644 "$PROJECT_ROOT/Resources/$HELPER_LABEL.plist" "$APP/Contents/Resources/$HELPER_LABEL.plist"
install -m 0755 "$PROJECT_ROOT/Resources/install-closed-lid-helper.sh" "$APP/Contents/Resources/install-closed-lid-helper.sh"
install -m 0755 "$PROJECT_ROOT/Resources/uninstall-closed-lid-helper.sh" "$APP/Contents/Resources/uninstall-closed-lid-helper.sh"
install -m 0644 "$PROJECT_ROOT/Resources/CodexAwake.applescript" "$APP/Contents/Resources/CodexAwake.applescript"

CONST_VALUES="$BIN_DIR/CodexAwakeApp.build/CodexAwakeApp.swiftconstvalues"
CONST_VALUES_LIST="$BIN_DIR/CodexAwakeApp.build/CodexAwakeApp.SwiftConstValuesFileList"
SOURCE_LIST="$BIN_DIR/CodexAwakeApp.build/sources"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")"
XCODE_BUILD_VERSION="$(xcodebuild -version | awk '/Build version/ { print $3 }')"
BUILD_ARCH="$(uname -m)"

[[ -s "$CONST_VALUES" ]] || { echo "Missing App Intents const values: $CONST_VALUES" >&2; exit 1; }
[[ -s "$SOURCE_LIST" ]] || { echo "Missing App Intents source list: $SOURCE_LIST" >&2; exit 1; }
printf '%s\n' "$CONST_VALUES" > "$CONST_VALUES_LIST"

xcrun appintentsmetadataprocessor \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name CodexAwakeApp \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD_VERSION" \
    --platform-family macOS \
    --deployment-target 14.0 \
    --bundle-identifier com.melnikoleg.CodexAwake \
    --output "$APP/Contents/Resources" \
    --target-triple "$BUILD_ARCH-apple-macos14.0" \
    --binary-file "$APP/Contents/MacOS/CodexAwake" \
    --source-file-list "$SOURCE_LIST" \
    --swift-const-vals-list "$CONST_VALUES_LIST" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --validate-assistant-intents \
    --no-app-shortcuts-localization

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # App Groups require a real signing identity and provisioning profile.
    # Applying them to an ad-hoc build creates a permanent cfprefsd/TCC retry loop.
    codesign --force --sign - --timestamp=none "$WIDGET"
    codesign --force --sign - --timestamp=none --identifier "$HELPER_LABEL" "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$PROJECT_ROOT/Resources/CodexAwakeWidget.entitlements" "$WIDGET"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --identifier "$HELPER_LABEL" "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$PROJECT_ROOT/Resources/CodexAwake.entitlements" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
