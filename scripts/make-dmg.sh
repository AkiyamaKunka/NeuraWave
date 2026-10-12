#!/bin/bash
# Build a release NeuraWave.app and wrap it in a drag-to-Applications DMG:
#   bash scripts/make-dmg.sh              -> dist/NeuraWave-<version>.dmg
#   bash scripts/make-dmg.sh out.dmg      -> out.dmg
# The version comes from packaging/Info.plist (CFBundleShortVersionString).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
APP="$ROOT/build/NeuraWave.app"
DMG="${1:-$ROOT/dist/NeuraWave-$VERSION.dmg}"

bash scripts/package-app.sh release >/dev/null
[ -x "$APP/Contents/MacOS/NeuraWave" ] || { echo "app bundle missing: $APP"; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -quiet -volname "NeuraWave $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"
echo "$DMG"
