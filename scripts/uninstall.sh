#!/bin/bash
set -euo pipefail

LABEL="com.cian.bob-wordbook-helper"
INSTALL_PATH="$HOME/.local/bin/bob-wordbook-helper"
STATE_DIR="$HOME/.local/share/bob-wordbook"
UNINSTALL_PATH="$STATE_DIR/uninstall.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/bob-wordbook"
SERVICE_TARGET="gui/$(id -u)/$LABEL"

if [[ "${BOB_WORDBOOK_SKIP_LAUNCH:-0}" != "1" ]] && launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
  launchctl bootout "$SERVICE_TARGET"
fi

rm -f "$PLIST_PATH" "$INSTALL_PATH" "$LOG_DIR/stdout.log" "$LOG_DIR/stderr.log" "$UNINSTALL_PATH"
rmdir "$LOG_DIR" 2>/dev/null || true
rmdir "$STATE_DIR" 2>/dev/null || true

echo "Uninstalled Bob Wordbook helper."
echo "Your JSONL wordbook was not removed."
