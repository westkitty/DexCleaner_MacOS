#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/.build/DexCleaner.app"
DIST="$ROOT/.build/dist"
DMG="$DIST/DexCleaner.dmg"
VOLUME="DexCleaner"

bash ./scripts/build_app_bundle.sh
command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil is required. Run this on macOS." >&2; exit 1; }
rm -rf "$DIST"
mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
hdiutil create -volname "$VOLUME" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
printf 'Built %s and %s\n' "$DMG" "$DMG.sha256"
