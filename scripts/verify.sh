#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APP="$PROJECT_ROOT/dist/CodexAwake.app"
HELPER_LABEL="com.melnikoleg.CodexAwake.ClosedLidHelper"
[[ -d "$APP" ]] || { echo "Missing $APP; run scripts/build_app.sh first" >&2; exit 1; }

plutil -lint "$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == "com.melnikoleg.CodexAwake" ]]
[[ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" == "false" ]]
[[ -x "$APP/Contents/MacOS/CodexAwake" ]]
codesign --verify --deep --strict "$APP"
codesign --verify --strict "$APP/Contents/Library/PrivilegedHelperTools/$HELPER_LABEL"
/usr/bin/plutil -lint "$APP/Contents/Resources/$HELPER_LABEL.plist"
[[ -x "$APP/Contents/Resources/install-closed-lid-helper.sh" ]]
[[ -x "$APP/Contents/Resources/uninstall-closed-lid-helper.sh" ]]
test -s "$APP/Contents/Resources/Metadata.appintents/version.json"
test -s "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
grep -q 'ToggleCodexAwakeProtectionIntent' "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
grep -q 'ApplyCodexAwakeProfileIntent' "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
grep -q 'GetCodexAwakeStatusIntent' "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"

WIDGET="$APP/Contents/PlugIns/CodexAwakeWidget.appex"
[[ -x "$WIDGET/Contents/MacOS/CodexAwakeWidget" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$WIDGET/Contents/Info.plist")" == "com.melnikoleg.CodexAwake.StatusWidget" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw "$WIDGET/Contents/Info.plist")" == "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" ]]
[[ "$(plutil -extract CFBundleVersion raw "$WIDGET/Contents/Info.plist")" == "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" ]]
codesign --verify --strict "$WIDGET"

SWIFT_FILES=()
while IFS= read -r -d '' file; do
    SWIFT_FILES+=("$file")
done < <(find "$PROJECT_ROOT/Sources" "$PROJECT_ROOT/Tests" -type f -name '*.swift' -print0)
xcrun swift-format lint --configuration "$PROJECT_ROOT/.swift-format" --strict "${SWIFT_FILES[@]}"

git diff --check

if find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.git" -prune -o -path "$PROJECT_ROOT/.build" -prune -o -path "$PROJECT_ROOT/dist" -prune -o -type f \( -name '*.sock' -o -name '.env' -o -name 'auth.json' \) -print | grep -q .; then
    echo "Unsafe runtime or credential-shaped file found in project" >&2
    exit 1
fi

echo "Verification passed: bundle metadata, signature, Swift format, diff hygiene, and secret-shaped files"
