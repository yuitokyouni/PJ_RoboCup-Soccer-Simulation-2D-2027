#!/bin/sh
# TRUE vanilla Cyrus (no Phase 5 patches). Uses the freshly-fetched
# cyrus-team master + only the rapidjson vendor patch.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-vanilla-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_vanilla_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t CYRUS_VANILLA "$@"
