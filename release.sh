#!/bin/bash
set -e

VERSION=$(python3 -c "import json; print(json.load(open('src/info.json'))['version'])" 2>/dev/null || echo "1.0.0")
PLUGIN_NAME="bob-shanbay-wordbook"
OUTPUT="${PLUGIN_NAME}-v${VERSION}.bobplugin"

echo "Building ${OUTPUT}..."
cd src
zip -r -j "../${OUTPUT}" info.json main.js shanbay.js
cd ..

echo ""
echo "SHA256:"
shasum -a 256 "${OUTPUT}"
echo ""
echo "Done: ${OUTPUT}"
