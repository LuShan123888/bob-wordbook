#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(python3 -c 'import json; print(json.load(open("src/info.json"))["version"])')"
OUTPUT_DIR="$SCRIPT_DIR/dist"
OUTPUT_NAME="bob-wordbook-v${VERSION}.bobplugin"

mkdir -p "$OUTPUT_DIR"
cd "$SCRIPT_DIR/src"
zip -q -r -FS "$OUTPUT_DIR/$OUTPUT_NAME" info.json main.js

echo "Built: $OUTPUT_DIR/$OUTPUT_NAME"
shasum -a 256 "$OUTPUT_DIR/$OUTPUT_NAME"
