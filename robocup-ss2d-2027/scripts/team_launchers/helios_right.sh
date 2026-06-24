#!/bin/sh
# Launch helios-base as the right team with team name HELIOS_R.
# See helios_left.sh for the goalie-race rationale.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
HELIOS_SRC="$REPO_ROOT/externals/src/helios-base/src"
PATCHED="$HELIOS_SRC/.start_patched_right.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$HELIOS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
exec "$PATCHED" -t HELIOS_R "$@"
