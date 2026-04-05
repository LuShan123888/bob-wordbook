#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_NAME="shanbay-cookie-helper"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

echo "=== Shanbay Cookie Helper Installer ==="
echo ""

# Build
echo "[1/4] Building helper binary..."
cd "$SCRIPT_DIR"
make build

# Install binary
echo "[2/4] Installing to $INSTALL_PATH..."
cp "$BINARY_NAME" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# Initial extraction
echo "[3/4] Running initial token extraction..."
"$INSTALL_PATH"

# Install LaunchAgent
echo "[4/4] Setting up auto-refresh (every 30 minutes)..."
"$INSTALL_PATH" install

echo ""
echo "=== All done! ==="
echo ""
echo "Your Shanbay auth_token will be automatically refreshed every 30 minutes."
echo "View logs: tail -f /tmp/shanbay-cookie-helper.log"
