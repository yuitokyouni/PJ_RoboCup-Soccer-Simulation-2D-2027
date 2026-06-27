#!/bin/sh
# Spica325 ORIG variant on RIGHT
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_spica_orig_right.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t SPICA_ORIG -f "$CYRUS_SRC/formations-dt-orig" "$@"
