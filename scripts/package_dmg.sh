#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${DEXCLEANER_APP_OUTPUT:-$HOME/Library/Application Support/DexCleaner/ReleaseCandidate/DexCleaner.app}"
DIST="$ROOT/.build-final/dist-$(date -u +%Y%m%dT%H%M%SZ)"
DMG="$DIST/DexCleaner.dmg"
VOLUME="DexCleaner"

bash ./scripts/build_app_bundle.sh
command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil is required. Run this on macOS." >&2; exit 1; }
mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
hdiutil create -volname "$VOLUME" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
printf 'Built %s and %s\n' "$DMG" "$DMG.sha256"
