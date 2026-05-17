#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n=== %s ===\n' "$1"
}

section "DISK"
df -h /System/Volumes/Data 2>/dev/null || df -h

section "REAL HOME USAGE"
du -xhd 1 "$HOME" 2>/dev/null | sort -h | tail -n 80 || true

section "REAL LIBRARY USAGE"
du -xhd 1 "$HOME/Library" 2>/dev/null | sort -h | tail -n 60 || true

section "APPLICATION SUPPORT USAGE"
du -xhd 1 "$HOME/Library/Application Support" 2>/dev/null | sort -h | tail -n 60 || true

section "LARGE FILES"
find "$HOME" -type f -size +500M -exec du -sh {} + 2>/dev/null | sort -h | tail -n 80 || true

section "EXACT SAFE TARGET PREVIEW"
for p in \
  "$HOME/Library/Caches/Homebrew" \
  "$HOME/Library/Caches/pip" \
  "$HOME/Library/Caches/org.swift.swiftpm" \
  "$HOME/Library/Application Support/Code/Cache"; do
  [ -e "$p" ] && du -sh "$p" 2>/dev/null || true
done

section "PROTECTED MARKERS"
for p in \
  "$HOME/.cache" \
  "$HOME/Library/Application Support" \
  "$HOME/Library/CloudStorage" \
  "$HOME/Documents" \
  "$HOME/Downloads" \
  "$HOME/Desktop" \
  "$HOME/Projects"; do
  [ -e "$p" ] && printf 'protected/audit-only: %s\n' "$p" || true
done
