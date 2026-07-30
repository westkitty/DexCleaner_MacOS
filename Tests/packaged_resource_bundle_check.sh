#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/DexCleaner-resource-test.XXXXXX")"
TEST_BUILD="$TEST_ROOT/build"
TEST_APP="$TEST_ROOT/DexCleaner.app"
TEST_LOG="$TEST_ROOT/launch.log"

DEXCLEANER_BUILD_ROOT="$TEST_BUILD" DEXCLEANER_APP_OUTPUT="$TEST_APP" bash "$ROOT/scripts/build_app_bundle.sh" >/dev/null
test -d "$TEST_APP/Contents/Resources/DexCleaner_DexCleanerCore.bundle"
test -f "$TEST_APP/Contents/Resources/DexCleaner_DexCleanerCore.bundle/Contents/Resources/CleanupManifest.json"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier ca.westcat.DexCleaner.resource-test' "$TEST_APP/Contents/Info.plist"
codesign --force --deep --sign - "$TEST_APP" >/dev/null
rm -rf "$TEST_BUILD"
mkdir -p "$TEST_ROOT/home"
HOME="$TEST_ROOT/home" "$TEST_APP/Contents/MacOS/DexCleaner" >"$TEST_LOG" 2>&1 &
APP_PID=$!
sleep 2
if ! kill -0 "$APP_PID" 2>/dev/null; then
  cat "$TEST_LOG" >&2
  exit 1
fi
if rg -q 'could not load resource bundle' "$TEST_LOG"; then
  cat "$TEST_LOG" >&2
  exit 1
fi
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
printf 'Packaged Bundle.module resource check passed.\n'
