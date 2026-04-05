#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_NAME="bob-wordbook-helper"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

echo "=== bob-wordbook-helper Installer ==="
echo ""

# Build
echo "[1/4] Building helper binary..."
cd "$SCRIPT_DIR"
make build

# Install binary
echo "[2/4] Installing to $INSTALL_PATH..."
cp "$BINARY_NAME" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# Initial token extraction
echo "[3/4] Running initial token extraction..."
"$INSTALL_PATH" extract || true

# Install LaunchAgent
echo "[4/4] Setting up auto-refresh (every 1 minute)..."
"$INSTALL_PATH" install

echo ""
echo "=== All done! ==="
echo ""
echo "Next step: run '$INSTALL_PATH init' to configure your Markdown wordbook path"
