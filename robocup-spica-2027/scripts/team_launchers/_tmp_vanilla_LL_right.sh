#!/bin/sh
# Vanilla Cyrus on RIGHT side with team name CYRUS_VANILLA_LL (mirror for side-swap)
# Used for vanilla-vs-vanilla LEFT-bias isolation experiment.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-vanilla-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_vv_LL_right.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_VAN_LL "$@"
