#!/bin/bash
set -euo pipefail

LABEL="com.cian.bob-wordbook-helper"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_BINARY="${1:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bob-wordbook-helper only supports macOS." >&2
  exit 1
fi

if [[ -z "$SOURCE_BINARY" ]]; then
  for candidate in "$SCRIPT_DIR/bob-wordbook-helper" "$SCRIPT_DIR/../bin/bob-wordbook-helper"; do
    if [[ -f "$candidate" ]]; then
      SOURCE_BINARY="$candidate"
      break
    fi
  done
fi
if [[ -z "$SOURCE_BINARY" || ! -f "$SOURCE_BINARY" ]]; then
  echo "Cannot find bob-wordbook-helper. Pass its path as the first argument." >&2
  exit 1
fi

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/bob-wordbook-helper"
STATE_DIR="$HOME/.local/share/bob-wordbook"
UNINSTALL_PATH="$STATE_DIR/uninstall.sh"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/bob-wordbook"
USER_ID="$(id -u)"
DOMAIN="gui/$USER_ID"
SERVICE_TARGET="$DOMAIN/$LABEL"

mkdir -p "$INSTALL_DIR" "$STATE_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

TEMP_BINARY="$(mktemp "$INSTALL_DIR/.bob-wordbook-helper.XXXXXX")"
TEMP_PLIST="$(mktemp "$LAUNCH_AGENTS_DIR/.$LABEL.XXXXXX")"
cleanup() {
  rm -f "$TEMP_BINARY" "$TEMP_PLIST"
}
trap cleanup EXIT

install -m 0755 "$SOURCE_BINARY" "$TEMP_BINARY"
mv -f "$TEMP_BINARY" "$INSTALL_PATH"
if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
  install -m 0755 "$SCRIPT_DIR/uninstall.sh" "$UNINSTALL_PATH"
fi

plutil -create xml1 "$TEMP_PLIST"
plutil -insert Label -string "$LABEL" "$TEMP_PLIST"
plutil -insert ProgramArguments -array "$TEMP_PLIST"
plutil -insert ProgramArguments.0 -string "$INSTALL_PATH" "$TEMP_PLIST"
plutil -insert RunAtLoad -bool true "$TEMP_PLIST"
plutil -insert KeepAlive -bool true "$TEMP_PLIST"
plutil -insert ProcessType -string Background "$TEMP_PLIST"
plutil -insert ThrottleInterval -integer 10 "$TEMP_PLIST"
plutil -insert StandardOutPath -string "$LOG_DIR/stdout.log" "$TEMP_PLIST"
plutil -insert StandardErrorPath -string "$LOG_DIR/stderr.log" "$TEMP_PLIST"
plutil -lint "$TEMP_PLIST"
mv -f "$TEMP_PLIST" "$PLIST_PATH"

if [[ "${BOB_WORDBOOK_SKIP_LAUNCH:-0}" != "1" ]]; then
  if launchctl print "$SERVICE_TARGET" >/dev/null 2>&1; then
    launchctl bootout "$SERVICE_TARGET"
  fi
  launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
  launchctl kickstart -k "$SERVICE_TARGET"
fi

echo "Installed helper: $INSTALL_PATH"
echo "Installed LaunchAgent: $PLIST_PATH"
echo "Uninstaller: $UNINSTALL_PATH"
echo "Logs: $LOG_DIR"
echo "The JSONL wordbook is preserved during upgrades and uninstall."
