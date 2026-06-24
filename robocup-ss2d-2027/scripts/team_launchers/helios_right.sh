#!/bin/sh
# Launch helios-base as the right team with the distinct name HELIOS_R.
# Mirror of helios_left.sh; see that script for the path-resolution note.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
exec "$REPO_ROOT/externals/src/helios-base/src/start.sh" -t HELIOS_R "$@"
