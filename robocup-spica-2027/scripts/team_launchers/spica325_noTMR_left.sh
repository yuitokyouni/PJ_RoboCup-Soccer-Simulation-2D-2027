#!/bin/sh
# Spica325 baseline = Phase 5/6/7/8 patches MINUS the iter-62 third-man-
# run path bonus. Used as the iter-62 contrast partner.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3-noTMR-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_spica325_noTMR_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t SPICA325_BASE "$@"
