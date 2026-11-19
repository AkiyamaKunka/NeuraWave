#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

cd "$ROOT"

# UNIVERSAL=1 builds for both Apple silicon and Intel (use for releases).
ARCH_FLAGS=()
if [ "${UNIVERSAL:-}" = 1 ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "Building NeuraWave ($CONFIG${UNIVERSAL:+, universal})..."
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

APP_DIR="$ROOT/build/NeuraWave.app"
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
cp "$BIN_DIR/NeuraWave" "$APP_DIR/Contents/MacOS/NeuraWave"
cp "$ROOT/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$ROOT/packaging/AppIcon.icns" ]; then
  cp "$ROOT/packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature; a broken seal would break Launch at Login and the
# Gatekeeper right-click > Open flow, so fail loudly instead of shipping it.
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
