#!/bin/bash
set -e

BINARY_NAME="bob-wordbook-helper"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

echo "=== bob-wordbook-helper Uninstaller ==="
echo ""

# Uninstall LaunchAgent
echo "[1/3] Removing LaunchAgent..."
"$INSTALL_PATH" uninstall 2>/dev/null || true

# Remove binary
echo "[2/3] Removing binary..."
rm -f "$INSTALL_PATH"
rm -f "$(dirname "$0")/$BINARY_NAME"

# Clean up config and sandbox token
echo "[3/3] Removing config and cached files..."
rm -rf ~/.config/bob-wordbook
SANDBOX_PATH="$HOME/Library/Containers/com.hezongyidev.Bob/Data/Documents/InstalledPluginSandbox"
rm -f "$SANDBOX_PATH/shanbay_auth_token"
rm -f "$SANDBOX_PATH/word_queue.jsonl"

echo ""
echo "=== Uninstall complete ==="
