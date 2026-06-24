#!/bin/sh
# Launch helios-base as the RIGHT team with team name HELIOS_3_2_5
# and a custom formation directory implementing the user's 3-2-5
# wingback-fluid system. Other phase files (defense / offense /
# kickin / setplay / before-kick-off) are the helios defaults --
# only normal-formation.conf is overridden.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
FORMATIONS_DIR="$REPO_ROOT/experiments/helios_3_2_5_formations"
exec "$REPO_ROOT/externals/src/helios-base/src/start.sh" \
  -t HELIOS_3_2_5 \
  -f "$FORMATIONS_DIR" \
  "$@"
