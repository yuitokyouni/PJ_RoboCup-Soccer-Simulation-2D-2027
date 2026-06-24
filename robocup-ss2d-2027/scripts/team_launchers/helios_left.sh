#!/bin/sh
# Launch helios-base as the left team with the distinct name HELIOS_L.
# scripts/team_launchers/helios_left.sh
#   -> externals/src/helios-base/src/start.sh -t HELIOS_L
# The two-level dirname walk reaches the repo root regardless of how the
# script is invoked (relative path, absolute path, or via PATH lookup).
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
exec "$REPO_ROOT/externals/src/helios-base/src/start.sh" -t HELIOS_L "$@"
