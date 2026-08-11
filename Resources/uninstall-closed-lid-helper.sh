#!/bin/bash
set -euo pipefail

LABEL="com.melnikoleg.CodexAwake.ClosedLidHelper"
DEST_HELPER="/Library/PrivilegedHelperTools/$LABEL"
DEST_PLIST="/Library/LaunchDaemons/$LABEL.plist"
STATE_DIR="/var/db/com.melnikoleg.CodexAwake"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "This uninstaller must run through sudo." >&2
    exit 77
fi

if /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$LABEL"
fi
if [[ -x "$DEST_HELPER" ]]; then
    "$DEST_HELPER" --recover || true
fi

/bin/rm -f "$DEST_PLIST" "$DEST_HELPER"
/bin/rm -f "$STATE_DIR/closed-lid-lease.json"
/bin/rmdir "$STATE_DIR" 2>/dev/null || true

echo
echo "CodexAwake Closed-Lid helper removed; normal lid sleep is restored."
