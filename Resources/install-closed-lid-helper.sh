#!/bin/bash
set -euo pipefail

LABEL="com.melnikoleg.CodexAwake.ClosedLidHelper"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_HELPER="$APP_ROOT/Contents/Library/PrivilegedHelperTools/$LABEL"
SOURCE_PLIST="$SCRIPT_DIR/$LABEL.plist"
DEST_HELPER="/Library/PrivilegedHelperTools/$LABEL"
DEST_PLIST="/Library/LaunchDaemons/$LABEL.plist"
STATE_DIR="/var/db/com.melnikoleg.CodexAwake"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "This installer must run through sudo." >&2
    exit 77
fi

if [[ ! -x "$SOURCE_HELPER" || ! -f "$SOURCE_PLIST" ]]; then
    echo "The CodexAwake bundle is missing its Closed-Lid helper resources." >&2
    exit 66
fi

/usr/bin/codesign --verify --strict "$APP_ROOT"
/usr/bin/codesign --verify --strict "$SOURCE_HELPER"
CLIENT_CDHASH="$(/usr/bin/codesign -dvvv "$APP_ROOT" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')"
if [[ ! "$CLIENT_CDHASH" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "Unable to determine the authorized CodexAwake code hash." >&2
    exit 65
fi
CLIENT_TEAM_ID="$(/usr/bin/codesign -dvvv "$APP_ROOT" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
CLIENT_MODE="--client-cdhash"
CLIENT_IDENTITY="$CLIENT_CDHASH"
if [[ "$CLIENT_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    CLIENT_MODE="--client-team-id"
    CLIENT_IDENTITY="$CLIENT_TEAM_ID"
fi

TEMP_PLIST="$(/usr/bin/mktemp "/private/tmp/$LABEL.XXXXXX")"
trap '/bin/rm -f "$TEMP_PLIST"' EXIT
/bin/cp "$SOURCE_PLIST" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 $CLIENT_MODE" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $CLIENT_IDENTITY" "$TEMP_PLIST"
/usr/bin/plutil -lint "$TEMP_PLIST"

if /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$LABEL"
fi
if [[ -x "$DEST_HELPER" ]]; then
    "$DEST_HELPER" --recover || true
fi

/usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
/usr/bin/install -d -o root -g wheel -m 0755 /Library/LaunchDaemons
/usr/bin/install -o root -g wheel -m 0755 "$SOURCE_HELPER" "$DEST_HELPER"
/usr/bin/install -o root -g wheel -m 0644 "$TEMP_PLIST" "$DEST_PLIST"
/usr/bin/codesign --verify --strict "$DEST_HELPER"
/usr/bin/plutil -lint "$DEST_PLIST"
"$DEST_HELPER" --recover

if ! /bin/launchctl bootstrap system "$DEST_PLIST"; then
    "$DEST_HELPER" --recover || true
    /bin/rm -f "$DEST_PLIST" "$DEST_HELPER"
    /bin/rmdir "$STATE_DIR" 2>/dev/null || true
    echo "Failed to bootstrap the Closed-Lid helper." >&2
    exit 70
fi
/bin/launchctl kickstart -k "system/$LABEL"

echo
echo "CodexAwake Closed-Lid helper installed successfully."
if [[ "$CLIENT_MODE" == "--client-team-id" ]]; then
    echo "Signed updates from Team $CLIENT_IDENTITY will reuse this helper without another password."
else
    echo "This local ad-hoc build is pinned to its exact code hash for security."
fi
echo "Return to CodexAwake and enable CLOSED-LID."
