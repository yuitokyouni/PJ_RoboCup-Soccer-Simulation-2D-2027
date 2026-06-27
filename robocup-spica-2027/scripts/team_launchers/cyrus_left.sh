#!/bin/sh
# Launch cyrus-soccer-simulation-team as the LEFT team with name CYRUS_L.
#
# Same goaliesleep=1 -> 3 patch as helios_left.sh (cyrus's start.sh is
# directly forked from helios's so it has the identical race).
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team/build/src"
PATCHED="$CYRUS_SRC/.start_patched_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
# Cyrus's sample_player loads data/settings/teams.conf and the deep
# learning weight files under data/deep/ via PWD-relative paths, so
# we must cd into build/src before exec'ing start.sh.
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_L "$@"
