#!/usr/bin/env bash
set -euo pipefail

cat <<'TEXT'
DexCleaner preview only.
This script deletes nothing.
It prints exact targets that DexCleaner may offer to move to Trash after review.
Cleanup candidates in the app start unselected.
TEXT

"$(dirname "$0")/audit_read_only.sh"
