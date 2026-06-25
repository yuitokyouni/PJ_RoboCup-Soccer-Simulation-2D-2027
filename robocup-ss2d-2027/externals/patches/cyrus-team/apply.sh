#!/usr/bin/env bash
# apply.sh - patch cyrus-soccer-simulation-team in place to use a
# pre-fetched rapidjson instead of running ExternalProject_Add (which
# requires outbound git at build time and silently produces an empty
# vendor/rapidjson/src/rapidjson if the clone is blocked).
#
# Usage:
#   apply.sh <path-to-cyrus-team>
#
# Idempotent: safe to re-run; the patched file overwrites cleanly.
set -euo pipefail

PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CYRUS_SRC="${1:-}"

if [[ -z "$CYRUS_SRC" || ! -d "$CYRUS_SRC/vendor" ]]; then
  echo "apply.sh: usage: apply.sh <path-to-cyrus-team>" >&2
  echo "  (the directory must contain a vendor/ subdirectory)" >&2
  exit 2
fi

echo "[patch] copying vendor/rapidjson.cmake into $CYRUS_SRC/vendor/"
cp -v "$PATCH_ROOT/vendor/rapidjson.cmake" "$CYRUS_SRC/vendor/rapidjson.cmake"
echo "[patch] done."
