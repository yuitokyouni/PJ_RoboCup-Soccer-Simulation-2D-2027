#!/bin/sh
# Spica325 with team name SPICA325_RR (self-swap RIGHT half pair).
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_spica325_RR_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t SPICA325_RR "$@"
