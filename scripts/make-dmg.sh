#!/bin/bash
# Build a release NeuraWave.app and wrap it in a drag-to-Applications DMG:
#   bash scripts/make-dmg.sh              -> dist/NeuraWave-<version>.dmg
#   bash scripts/make-dmg.sh out.dmg      -> out.dmg
# Refuses to overwrite an existing DMG (e.g. an already released version)
# unless FORCE=1; bump CFBundleShortVersionString for a new release.
# The version comes from packaging/Info.plist (CFBundleShortVersionString).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Resolve a relative output path against where the script was run from.
OUT=""
if [ -n "${1:-}" ]; then
  mkdir -p "$(dirname "$1")"
  OUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
APP="$ROOT/build/NeuraWave.app"
DMG="${OUT:-$ROOT/dist/NeuraWave-$VERSION.dmg}"
if [ -e "$DMG" ] && [ "${FORCE:-}" != 1 ]; then
  echo "exists: $DMG (bump CFBundleShortVersionString, pass another path, or FORCE=1)" >&2
  exit 1
fi

bash scripts/package-app.sh release >&2
[ -x "$APP/Contents/MacOS/NeuraWave" ] || { echo "app bundle missing: $APP" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -quiet -volname "NeuraWave $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"
echo "$DMG"
