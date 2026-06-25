#!/bin/sh
# Improved Cyrus (Phase 5 patches active, F325-hybrid). Runs the binary
# saved in externals/src/cyrus-team-improved-snapshot/.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-improved-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_improved_right.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_IMPROVED "$@"
