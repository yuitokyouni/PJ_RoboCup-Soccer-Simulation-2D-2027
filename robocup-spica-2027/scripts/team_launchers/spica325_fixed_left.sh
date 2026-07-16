#!/bin/sh
# Spica325 "audit-fixed" variant on LEFT: full Phase 5/6/7/8 + iter-62
# stack PLUS the 2026-07 audit C++ fixes (SmartClearance defensive
# guard / resting-point check / execute() result, CDM unum 5-6,
# counter_press namespace link fix, TRS macro enabled).
# Snapshot is produced by:
#   scripts/setup_cyrus_snapshots.sh --dest cyrus-team-v3fix-snapshot
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
CYRUS_SRC="$REPO_ROOT/externals/src/cyrus-team-v3fix-snapshot/build/src"
PATCHED="$CYRUS_SRC/.start_patched_spica325_fixed_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$CYRUS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
cd "$CYRUS_SRC"
exec "$PATCHED" -t SPICA325F "$@"
