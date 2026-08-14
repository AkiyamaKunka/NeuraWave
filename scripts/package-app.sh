#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

cd "$ROOT"

echo "Building NeuraWave ($CONFIG)..."
swift build -c "$CONFIG"

APP_DIR="$ROOT/build/NeuraWave.app"
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
cp "$BIN_DIR/NeuraWave" "$APP_DIR/Contents/MacOS/NeuraWave"
cp "$ROOT/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$ROOT/packaging/AppIcon.icns" ]; then
  cp "$ROOT/packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
