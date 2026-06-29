#!/bin/sh
# Vanilla Cyrus on RIGHT, with distinct team name CYRUS_VAN_R so the
# server can pair it against another Vanilla on LEFT (which uses
# CYRUS_VANILLA) in the same match. Used by the vanilla LR side-bias
# check, which would otherwise fail because both sides default to
# team name CYRUS_VANILLA and the server rejects the second connect.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-vanilla-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_vanilla_right_distinct.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_VAN_R "$@"
