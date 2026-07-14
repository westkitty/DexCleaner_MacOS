#!/usr/bin/env bash
set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }
measure_children() {
  local root="$1"
  shift
  [ -d "$root" ] || return 0
  while IFS= read -r -d '' child; do
    du -xsh "$child" 2>/dev/null || true
  done < <(find "$root" -mindepth 1 -maxdepth 1 "$@" -print0 2>/dev/null) \
    | sort -h \
    | tail -n 80 || true
}

section "DISK"
df -h /System/Volumes/Data 2>/dev/null || df -h /

section "TOP-LEVEL HOME USAGE (PROTECTED ROOTS PRUNED)"
measure_children "$HOME" \
  ! -name Library ! -name Projects ! -name Developer ! -name Applications \
  ! -name Documents ! -name Downloads ! -name Desktop ! -name Movies ! -name Pictures \
  ! -name Dropbox ! -name OneDrive ! -name 'Google Drive' ! -name .Trash ! -name .cache

section "TOP-LEVEL LIBRARY USAGE (PROTECTED ROOTS PRUNED)"
measure_children "$HOME/Library" \
  ! -name 'Application Support' ! -name CloudStorage ! -name Keychains \
  ! -name Mail ! -name Messages ! -name Safari ! -name Developer

section "LARGE FILES OUTSIDE MANDATORY EXCLUSIONS"
find "$HOME" \
  \( -path "$HOME/Library" -o -path "$HOME/Library/*" \
     -o -path "$HOME/.Trash" -o -path "$HOME/.Trash/*" \
     -o -path "$HOME/.cache" -o -path "$HOME/.cache/*" \
     -o -path "$HOME/Projects" -o -path "$HOME/Projects/*" \
     -o -path "$HOME/Developer" -o -path "$HOME/Developer/*" \
     -o -path "$HOME/Applications" -o -path "$HOME/Applications/*" \
     -o -path "$HOME/Documents" -o -path "$HOME/Documents/*" \
     -o -path "$HOME/Downloads" -o -path "$HOME/Downloads/*" \
     -o -path "$HOME/Desktop" -o -path "$HOME/Desktop/*" \
     -o -path "$HOME/Movies" -o -path "$HOME/Movies/*" \
     -o -path "$HOME/Pictures" -o -path "$HOME/Pictures/*" \
     -o -path "$HOME/Dropbox" -o -path "$HOME/Dropbox/*" \
     -o -path "$HOME/OneDrive" -o -path "$HOME/OneDrive/*" \
     -o -path "$HOME/Google Drive" -o -path "$HOME/Google Drive/*" \
     -o -path '*/.git' -o -path '*/.git/*' \) -prune -o \
  -type f -size +500M -exec du -sh {} + 2>/dev/null | sort -h | tail -n 80 || true

section "EXACT MANIFEST TARGET PREVIEW"
ROOT="$(cd "$(dirname "$0")/.." && pwd)" python3 - <<'PY'
import json, os
from pathlib import Path
manifest = Path(os.environ['ROOT']) / "Sources/DexCleanerCore/Resources/CleanupManifest.json"
data = json.loads(manifest.read_text())
for entry in data["safeExactTargets"]:
    path = Path.home() / entry["relativePath"]
    if path.exists():
        print(f"candidate: {entry['id']}\t{path}")
PY

section "PROTECTED PRESENCE MARKERS"
for p in \
  "$HOME/.cache" "$HOME/Library/CloudStorage" "$HOME/Library/Application Support" \
  "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Projects" "$HOME/Developer"; do
  [ -e "$p" ] && printf 'protected/audit-only: %s\n' "$p" || true
done
