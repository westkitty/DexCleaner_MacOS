#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/.build/DexCleaner.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
IDENTITY="${DEXCLEANER_CODESIGN_IDENTITY:--}"
VERSION="1.0.0"

swift build -c "$CONFIGURATION" --product DexCleaner
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN="$BIN_DIR/DexCleaner"

if [ ! -x "$BIN" ]; then
  echo "DexCleaner executable was not produced at $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/DexCleaner"

RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d \
  \( -name '*DexCleanerCore.resources' -o -name '*DexCleanerCore.bundle' \) \
  -print -quit 2>/dev/null || true)"
if [ -z "$RESOURCE_BUNDLE" ]; then
  echo "SwiftPM resource bundle was not produced; cleanup authority would be unavailable." >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DexCleaner</string>
  <key>CFBundleIdentifier</key><string>ca.westcat.DexCleaner</string>
  <key>CFBundleName</key><string>DexCleaner</string>
  <key>CFBundleDisplayName</key><string>DexCleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built and verified %s\n' "$APP"
