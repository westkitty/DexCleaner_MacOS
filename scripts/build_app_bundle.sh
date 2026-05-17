#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/.build/DexCleaner.app"
BIN="$ROOT/.build/$CONFIGURATION/DexCleaner"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
IDENTITY="${DEXCLEANER_CODESIGN_IDENTITY:--}"

swift build -c "$CONFIGURATION"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/DexCleaner"

# SwiftPM resources are emitted as a sidecar bundle. Copy it into app resources when present.
RESOURCE_BUNDLE="$(find "$ROOT/.build/$CONFIGURATION" -maxdepth 1 -name 'DexCleanerCore_DexCleanerCore.resources' -type d 2>/dev/null | head -n 1 || true)"
if [ -n "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DexCleaner</string>
  <key>CFBundleIdentifier</key><string>ca.westcat.DexCleaner</string>
  <key>CFBundleName</key><string>DexCleaner</string>
  <key>CFBundleDisplayName</key><string>DexCleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || true
printf 'Built %s\n' "$APP"
