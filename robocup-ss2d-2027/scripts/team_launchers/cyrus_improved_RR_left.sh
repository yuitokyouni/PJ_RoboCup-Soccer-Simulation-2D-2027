#!/bin/sh
# Improved Cyrus v3 with team name CYRUS_IMP_RR (for self-swap pairing).
# Used for imp-vs-imp self-swap LEFT-bias smoking-gun experiment.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_ii_RR_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_IMP_RR "$@"
