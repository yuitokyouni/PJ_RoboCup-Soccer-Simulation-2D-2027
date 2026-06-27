#!/bin/sh
# Spica325 (Cyrus-based research model, Phase 5a-e patches) on RIGHT.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_spica325_right.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t SPICA325 "$@"
