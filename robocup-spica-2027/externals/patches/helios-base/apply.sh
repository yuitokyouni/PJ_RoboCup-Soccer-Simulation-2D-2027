#!/usr/bin/env bash
# apply.sh - patch helios-base in place with the Phase 4 defensive
# duty layer (Bhv_PressBallCarrier + Bhv_CoverGoalSide + DefenseDuty
# assigner). Idempotent: safe to run multiple times.
#
# Usage:
#   apply.sh <path-to-helios-base/src>
#
# Effect:
#   1. Copies 6 new files into <helios>/src/player/
#   2. Patches <helios>/src/player/bhv_basic_move.cpp to dispatch to
#      the new behaviors before the existing chase logic.
#   3. Patches <helios>/src/player/Makefile.am to compile the new
#      .cpp files.
#   After patching, the caller must re-run ./bootstrap + ./configure
#   so the Makefile.in regenerates from Makefile.am.
set -euo pipefail

PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELIOS_SRC="${1:-}"

if [[ -z "$HELIOS_SRC" || ! -d "$HELIOS_SRC/player" ]]; then
  echo "apply.sh: usage: apply.sh <path-to-helios-base/src>" >&2
  echo "  (the directory must contain a player/ subdirectory)" >&2
  exit 2
fi

PLAYER="$HELIOS_SRC/player"

# 1. Copy new files
echo "[patch] copying new sources into $PLAYER/"
cp -v "$PATCH_ROOT/src/player/defense_duty.h"          "$PLAYER/"
cp -v "$PATCH_ROOT/src/player/defense_duty.cpp"        "$PLAYER/"
cp -v "$PATCH_ROOT/src/player/bhv_press_ball_carrier.h"   "$PLAYER/"
cp -v "$PATCH_ROOT/src/player/bhv_press_ball_carrier.cpp" "$PLAYER/"
cp -v "$PATCH_ROOT/src/player/bhv_cover_goal_side.h"      "$PLAYER/"
cp -v "$PATCH_ROOT/src/player/bhv_cover_goal_side.cpp"    "$PLAYER/"

# 2. Patch bhv_basic_move.cpp
BBM="$PLAYER/bhv_basic_move.cpp"
if grep -q PATCH_4ACD_BEGIN "$BBM" 2>/dev/null; then
  echo "[patch] $BBM already patched (PATCH_4ACD_BEGIN found); skipping"
else
  echo "[patch] patching $BBM"

  # 2a. Add includes after the existing bhv_basic_tackle.h include.
  python3 - "$BBM" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
anchor = '#include "bhv_basic_tackle.h"'
add = """\
#include "bhv_basic_tackle.h"

// PATCH_4ACD: defensive duty headers
#include "defense_duty.h"
#include "bhv_press_ball_carrier.h"
#include "bhv_cover_goal_side.h\""""
if anchor not in src:
    sys.exit("apply.sh: anchor #include \"bhv_basic_tackle.h\" not found in bhv_basic_move.cpp")
src = src.replace(anchor, add, 1)
p.write_text(src)
PYEOF

  # 2b. Insert the duty dispatch block after the function-scope
  # `const WorldModel & wm = agent->world();` line.
  python3 - "$BBM" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
anchor = "    const WorldModel & wm = agent->world();"
block = """\
    const WorldModel & wm = agent->world();

    // ===== PATCH_4ACD_BEGIN =====
    // Defensive duty: a closer-than-anyone teammate presses the ball
    // carrier; the next-best defender covers an unmarked opponent
    // goal-side. See defense_duty.cpp for the assignment algorithm.
    {
        DefenseDuty duty = DefenseDutyAssigner::assign( wm );
        if ( duty.type == DefenseDuty::PRESS )
        {
            if ( Bhv_PressBallCarrier( duty.position ).execute( agent ) )
                return true;
        }
        else if ( duty.type == DefenseDuty::COVER )
        {
            if ( Bhv_CoverGoalSide( duty.position, duty.target ).execute( agent ) )
                return true;
        }
    }
    // ===== PATCH_4ACD_END ====="""
if anchor not in src:
    sys.exit("apply.sh: anchor `const WorldModel & wm = agent->world();` not found in bhv_basic_move.cpp")
# Only replace the FIRST occurrence (the one inside execute()).
src = src.replace(anchor, block, 1)
p.write_text(src)
PYEOF

  echo "[patch] $BBM patched"
fi

# 3. Patch Makefile.am
MFA="$PLAYER/Makefile.am"
if grep -q "defense_duty.cpp" "$MFA" 2>/dev/null; then
  echo "[patch] $MFA already patched; skipping"
else
  echo "[patch] patching $MFA"
  python3 - "$MFA" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()

# Insert new .cpp lines after bhv_basic_move.cpp
src = src.replace(
    "\tbhv_basic_move.cpp \\",
    "\tbhv_basic_move.cpp \\\n"
    "\tbhv_cover_goal_side.cpp \\\n"
    "\tbhv_press_ball_carrier.cpp \\\n"
    "\tdefense_duty.cpp \\",
    1,
)

# Insert new .h lines after bhv_basic_move.h
src = src.replace(
    "\tbhv_basic_move.h \\",
    "\tbhv_basic_move.h \\\n"
    "\tbhv_cover_goal_side.h \\\n"
    "\tbhv_press_ball_carrier.h \\\n"
    "\tdefense_duty.h \\",
    1,
)

p.write_text(src)
PYEOF
  echo "[patch] $MFA patched"
fi

echo "[patch] done. Re-run ./bootstrap in $HELIOS_SRC/.. to regenerate Makefile.in."
