#!/bin/sh
# Launch WrightEagleBASE as the right side with team name WE_R.
# start.sh must be invoked from inside its own source directory so its
# relative LOG_DIR ("Logfiles") and "./Release/WEBase" resolve.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
WE_DIR="$REPO_ROOT/externals/src/wrighteaglebase"
cd "$WE_DIR" || exit 1
exec ./start.sh -t WE_R -v Release "$@"
