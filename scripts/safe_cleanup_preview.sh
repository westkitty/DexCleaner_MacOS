#!/usr/bin/env bash
set -euo pipefail
cat <<'TEXT'
DexCleaner command-line preview is read-only.
It grants no cleanup authority and deletes nothing.
The app still requires explicit selection, immutable Preview, and exact confirmation.
TEXT
"$(dirname "$0")/audit_read_only.sh"
