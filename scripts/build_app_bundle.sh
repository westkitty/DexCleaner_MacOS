#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
BUILD_ROOT="${DEXCLEANER_BUILD_ROOT:-$ROOT/.build-final}"
FINAL_APP="${DEXCLEANER_APP_OUTPUT:-$HOME/Library/Application Support/DexCleaner/ReleaseCandidate/DexCleaner.app}"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/DexCleaner-app-stage.XXXXXX")"
APP="$STAGE_ROOT/DexCleaner.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
IDENTITY="${DEXCLEANER_CODESIGN_IDENTITY:--}"
VERSION="1.3.2"
RESOURCE_BUNDLE_NAME="DexCleaner_DexCleanerCore.bundle"
MANIFEST_NAME="CleanupManifest.json"

swift build --scratch-path "$BUILD_ROOT" -c "$CONFIGURATION" --product DexCleaner
BIN_DIR="$(swift build --scratch-path "$BUILD_ROOT" -c "$CONFIGURATION" --show-bin-path)"
BIN="$BIN_DIR/DexCleaner"

if [ ! -x "$BIN" ]; then
  echo "DexCleaner executable was not produced at $BIN" >&2
  exit 1
fi

mkdir -p "$MACOS"
cp "$BIN" "$MACOS/DexCleaner"

RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d \
  \( -name "$RESOURCE_BUNDLE_NAME" -o -name '*DexCleanerCore.resources' \) \
  -print -quit 2>/dev/null || true)"
if [ -z "$RESOURCE_BUNDLE" ]; then
  echo "SwiftPM resource bundle was not produced; cleanup authority would be unavailable." >&2
  exit 1
fi
if [ ! -f "$RESOURCE_BUNDLE/$MANIFEST_NAME" ]; then
  echo "SwiftPM resource bundle is missing $MANIFEST_NAME; refusing to package an app without cleanup authority." >&2
  exit 1
fi

# A valid macOS app seals resources under Contents/Resources. CleanupCatalog resolves this installed location directly.
PACKAGED_BUNDLE="$CONTENTS/Resources/$RESOURCE_BUNDLE_NAME"
mkdir -p "$PACKAGED_BUNDLE/Contents/Resources"
cp -R "$RESOURCE_BUNDLE/." "$PACKAGED_BUNDLE/Contents/Resources/"
cat > "$PACKAGED_BUNDLE/Contents/Info.plist" <<BUNDLE_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>ca.westcat.DexCleanerCore.resources</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
</dict></plist>
BUNDLE_PLIST
if [ ! -d "$PACKAGED_BUNDLE" ] || [ ! -r "$PACKAGED_BUNDLE" ] || [ ! -f "$PACKAGED_BUNDLE/Contents/Resources/$MANIFEST_NAME" ]; then
  echo "Packaged SwiftPM resource bundle preflight failed." >&2
  exit 1
fi
if ! cmp -s "$BIN" "$MACOS/DexCleaner" || ! cmp -s "$RESOURCE_BUNDLE/$MANIFEST_NAME" "$PACKAGED_BUNDLE/Contents/Resources/$MANIFEST_NAME"; then
  echo "Release product and staged app differ before signing; refusing installation." >&2
  exit 1
fi

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
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
# A root-level SwiftPM bundle is required by resource_bundle_accessor.swift and must be sealed before its enclosing app.
codesign --force --sign "$IDENTITY" "$PACKAGED_BUNDLE"
codesign --verify --strict "$PACKAGED_BUNDLE"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if [ ! -f "$PACKAGED_BUNDLE/Contents/Resources/$MANIFEST_NAME" ]; then
  echo "Signed application lost its SwiftPM resource bundle; refusing installation." >&2
  exit 1
fi

if [ -e "$FINAL_APP" ]; then
  PREVIOUS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/DexCleaner-previous-build.XXXXXX")"
  mv "$FINAL_APP" "$PREVIOUS_ROOT/DexCleaner.app"
fi
mkdir -p "$(dirname "$FINAL_APP")"
mv "$APP" "$FINAL_APP"
xattr -cr "$FINAL_APP"
codesign --force --deep --sign "$IDENTITY" "$FINAL_APP"
codesign --verify --deep --strict "$FINAL_APP"
printf 'Built and verified %s\n' "$FINAL_APP"
