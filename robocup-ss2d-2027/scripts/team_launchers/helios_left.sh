#!/bin/sh
# Launch helios-base as the left team with team name HELIOS_L.
#
# Goalie-race workaround: helios-base/src/start.sh sleeps 1 second
# between the goalie launch (with -g) and the first outfielder, but
# the goalie process is slightly heavier (formation reads) than the
# outfielders. In synch_mode races both teams' players init in
# 0.1 s windows; if the goalie's init message arrives 10th the
# server allocates unum=10 to it, which produced the green-#10
# "goalie of HELIOS_L is player 10" anomaly in earlier matches.
#
# We patch goaliesleep=1 -> 3 by writing a sed'd copy of start.sh
# next to the original (the file is dot-prefixed and lives under
# externals/src/, which is gitignored). Keeping it in the helios src
# dir means `dirname $0` inside the patched script still resolves to
# the helios src so its sample_player / sample_coach references work.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../.." && pwd)
HELIOS_SRC="$REPO_ROOT/externals/src/helios-base/src"
PATCHED="$HELIOS_SRC/.start_patched_left.sh"
sed 's/^goaliesleep=1$/goaliesleep=3/' "$HELIOS_SRC/start.sh" > "$PATCHED"
chmod +x "$PATCHED"
exec "$PATCHED" -t HELIOS_L "$@"
