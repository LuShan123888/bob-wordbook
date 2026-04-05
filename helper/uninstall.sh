#!/bin/bash
set -e

BINARY_NAME="shanbay-cookie-helper"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

echo "=== Shanbay Cookie Helper Uninstaller ==="
echo ""

# Uninstall LaunchAgent
echo "[1/3] Removing LaunchAgent..."
"$INSTALL_PATH" uninstall 2>/dev/null || true

# Remove binary
echo "[2/3] Removing binary..."
rm -f "$INSTALL_PATH"
rm -f "$SCRIPT_DIR/$BINARY_NAME"

# Clean up sandbox token file
SANDBOX_PATH="$HOME/Library/Containers/com.hezongyidev.Bob/Data/Documents/InstalledPluginSandbox"
TOKEN_FILE="$SANDBOX_PATH/shanbay_auth_token"
if [ -f "$TOKEN_FILE" ]; then
    echo "[3/3] Removing token file..."
    rm -f "$TOKEN_FILE"
else
    echo "[3/3] No token file to remove."
fi

echo ""
echo "=== Uninstall complete ==="
