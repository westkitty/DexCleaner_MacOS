#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/.build/DexCleaner.app"
DIST="$ROOT/.build/dist"
DMG="$DIST/DexCleaner.dmg"
VOLUME="DexCleaner"

bash ./scripts/build_app_bundle.sh

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required to build a DMG. Run this on macOS." >&2
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"

rm -f "$DMG"
hdiutil create -volname "$VOLUME" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$DMG" > "$DMG.sha256"
fi

printf 'Built %s\n' "$DMG"
