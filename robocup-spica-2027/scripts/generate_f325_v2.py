#!/usr/bin/env python3
"""Generate the F325 (3-2-5 wing-back-fluid) Delaunay formation set
for Cyrus / Spica325.

Strategy (different from the v1 generator that produced the regression):

  v1 (BAD):  static positions per .conf file; same player coordinates
             regardless of ball position. Cyrus's pass predictor needs
             player positions to DEPEND on ball.x and ball.y.

  v2 (this): borrow the EXACT 48 ball-sample positions from F433 so
             the Delaunay triangulation has the same density Cyrus's
             pass predictor was trained on; compute 3-2-5 player
             coordinates per ball position from a small set of rules
             so positions DO move with the ball.

Run from the project root:

  python3 scripts/generate_f325_v2.py

Output:

  externals/patches/cyrus-team/src/formations-dt/F325_*.conf  (9 files)
"""
from __future__ import annotations

import argparse
import copy
import json
import pathlib
import sys
from typing import Callable

# ---- 3-2-5 role definition (Cyrus's "Player / MF" neutral typing) ----

ROLES = [
    {"number": 1,  "name": "Goalie", "type": "G",  "side": "C", "pair":  0},
    # Phase 5/6 patches assume:
    #   unum 3, 4 = wing-backs (is_wing_back)
    #   unum 6, 7 = CDMs (is_build_up_drop_cdm)
    #   unum 11 = CF (is_false_nine)
    # F325 v3 unum-to-role to match:
    #   unum 2, 5, 8 = 3 CBs
    #   unum 3, 4 = LWB, RWB
    #   unum 6, 7 = LDM, RDM
    #   unum 9, 10 = LIF, RIF
    #   unum 11 = CF
    {"number": 2,  "name": "Player", "type": "MF", "side": "C", "pair":  8},  # LCB
    {"number": 3,  "name": "Player", "type": "MF", "side": "C", "pair":  4},  # LWB
    {"number": 4,  "name": "Player", "type": "MF", "side": "C", "pair":  3},  # RWB
    {"number": 5,  "name": "Player", "type": "MF", "side": "C", "pair":  0},  # MCB
    {"number": 6,  "name": "Player", "type": "MF", "side": "C", "pair":  7},  # LDM
    {"number": 7,  "name": "Player", "type": "MF", "side": "C", "pair":  6},  # RDM
    {"number": 8,  "name": "Player", "type": "MF", "side": "C", "pair":  2},  # RCB
    {"number": 9,  "name": "Player", "type": "MF", "side": "C", "pair": 10},  # LIF
    {"number": 10, "name": "Player", "type": "MF", "side": "C", "pair":  9},  # RIF
    {"number": 11, "name": "Player", "type": "MF", "side": "C", "pair":  0},  # CF
]


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def round2(v: float) -> float:
    return round(v, 2)


# ---- position rules ----------------------------------------------------
#
# Each rule maps (bx, by) -> {unum: (x, y)} for a specific phase.
# Conventions:
#   - bx, by are the ball position (server / team-frame: own goal at
#     x = -52.5, attacking right toward x = +52.5)
#   - we ASSUME our team is on the LEFT (Cyrus auto-mirrors via
#     librcsc for right-side, so rules need only be written once)
#   - units are metres
#
# The base shape at ball=(0,0) (centre spot) is the 3-2-5 in
# "transition" state:
#
#   GK   (-50, 0)
#   CB_L (-30, -10)   CB_M (-32, 0)    CB_R (-30, +10)
#   LWB  (-12, -28)                    RWB  (-12, +28)
#   LDM  (-15, -5)    RDM  (-15, +5)
#   LIF  (+5, -16)    RIF  (+5, +16)
#   CF   (+8, 0)
#
# Then each phase (offense / defense / normal etc.) is a function that
# shifts the base shape based on (bx, by).


def offense_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """3-2-5 in attack: WBs high and wide, IFs in half-spaces, CF
    near opp box. Heavy ball-tracking on forwards."""
    fwd_x = clamp(28.0 + bx * 0.35, 10.0, 44.0)
    half_x = clamp(15.0 + bx * 0.35, 0.0, 36.0)
    mid_x = clamp(-4.0 + bx * 0.35, -22.0, 20.0)
    back_x = clamp(-25.0 + bx * 0.20, -42.0, -10.0)
    gk_x = clamp(-49.0 + bx * 0.02, -52.0, -45.0)

    # Lateral shift toward ball.y (the whole shape leans).
    shift = clamp(by * 0.4, -8.0, 8.0)

    # v3 unum mapping: 2/5/8=CBs, 3/4=WBs, 6/7=CDMs, 9/10=IFs, 11=CF
    return {
        1:  (gk_x,         clamp(by * 0.15, -5.0, 5.0)),
        2:  (back_x - 1,   -10.0 + shift * 0.6),   # LCB
        3:  (mid_x + 6,   -26.0 + shift),          # LWB high
        4:  (mid_x + 6,    26.0 + shift),          # RWB high
        5:  (back_x - 3,    0.0 + shift * 0.6),    # MCB
        6:  (mid_x - 3,    -5.0 + shift * 0.7),    # LDM
        7:  (mid_x - 3,     5.0 + shift * 0.7),    # RDM
        8:  (back_x - 1,   10.0 + shift * 0.6),    # RCB
        9:  (half_x,      -12.0 + shift),          # LIF
        10: (half_x,       12.0 + shift),          # RIF
        11: (fwd_x,         0.0 + shift * 0.5),    # CF
    }


def defense_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """5-2-3 deep block: WBs join the back line forming a 5-back; CF
    + IFs stay as counter outlets near midfield."""
    back_x = clamp(-30.0 + bx * 0.30, -42.0, -10.0)
    mid_x = clamp(-12.0 + bx * 0.30, -28.0, 8.0)
    fwd_x = clamp(0.0 + bx * 0.30, -16.0, 22.0)
    gk_x = clamp(-49.0 + bx * 0.02, -52.0, -45.0)

    shift = clamp(by * 0.5, -10.0, 10.0)

    return {
        1:  (gk_x,         clamp(by * 0.2, -6.0, 6.0)),
        2:  (back_x,       -14.0 + shift * 0.8),   # LCB
        3:  (back_x + 1,  -26.0 + shift),          # LWB dropped to back-5
        4:  (back_x + 1,   26.0 + shift),          # RWB dropped to back-5
        5:  (back_x - 2,    0.0 + shift * 0.6),    # MCB
        6:  (mid_x,        -6.0 + shift * 0.6),    # LDM
        7:  (mid_x,         6.0 + shift * 0.6),    # RDM
        8:  (back_x,       14.0 + shift * 0.8),    # RCB
        9:  (fwd_x,       -12.0 + shift),          # LF
        10: (fwd_x,        12.0 + shift),          # RF
        11: (fwd_x + 4,     0.0 + shift * 0.5),    # CF
    }


def setplay_our_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Stretched 3-2-5 for our set-pieces: WBs and forwards push high."""
    base = offense_positions(bx, by)
    # Push everyone (except GK) ~5m more forward (within clamp).
    out: dict[int, tuple[float, float]] = {}
    for k, (x, y) in base.items():
        if k == 1:
            out[k] = (x, y)
        else:
            out[k] = (clamp(x + 5.0, -45.0, 46.0), y)
    return out


def setplay_opp_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """5-2-3 block for opp set-pieces: drop EVERYONE 4-5m."""
    base = defense_positions(bx, by)
    out: dict[int, tuple[float, float]] = {}
    for k, (x, y) in base.items():
        if k == 1:
            out[k] = (x, y)
        else:
            out[k] = (clamp(x - 4.0, -50.0, 35.0), y)
    return out


def kickin_our_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Our kick-in (throw-in). Use offense base; the player closest
    to the ball will be sucked there by Cyrus's set-play layer."""
    return offense_positions(bx, by)


def goal_kick_our_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Our goal kick (v3 unum mapping)."""
    return {
        1:  (-49.0,  0.0),
        2:  (-35.0, -14.0),   # LCB
        3:  (-22.0, -26.0),   # LWB dropped wide for outlet
        4:  (-22.0,  26.0),   # RWB dropped wide
        5:  (-44.0,   0.0),   # MCB deep
        6:  (-22.0,  -6.0),   # LDM
        7:  (-22.0,   6.0),   # RDM
        8:  (-35.0,  14.0),   # RCB
        9:  ( -2.0, -18.0),   # LIF
        10: ( -2.0,  18.0),   # RIF
        11: (  5.0,   0.0),   # CF
    }


def goal_kick_opp_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Opp goal kick (v3 unum mapping). High press-ready shape."""
    return {
        1:  (-49.0,  0.0),
        2:  (-15.0, -10.0),   # LCB
        3:  (  5.0, -25.0),   # LWB pushed up to press
        4:  (  5.0,  25.0),   # RWB pushed up
        5:  (-15.0,   0.0),   # MCB
        6:  (  5.0,  -6.0),   # LDM
        7:  (  5.0,   6.0),   # RDM
        8:  (-15.0,  10.0),   # RCB
        9:  ( 28.0, -16.0),   # LIF
        10: ( 28.0,  16.0),   # RIF
        11: ( 35.0,   0.0),   # CF
    }


def before_kick_off_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Static start-of-half position (v3 unum mapping)."""
    return {
        1:  (-49.0,  0.0),
        2:  (-32.0, -12.0),   # LCB
        3:  (-16.0, -26.0),   # LWB
        4:  (-16.0,  26.0),   # RWB
        5:  (-34.5,  0.0),    # MCB
        6:  (-12.0,  -6.0),   # LDM
        7:  (-12.0,   6.0),   # RDM
        8:  (-32.0,  12.0),   # RCB
        9:  ( -2.0, -16.0),   # LIF
        10: ( -2.0,  16.0),   # RIF
        11: ( -1.0,   0.0),   # CF
    }


def before_kick_off_our_positions(bx: float, by: float) -> dict[int, tuple[float, float]]:
    """Our kick-off: CF on the centre spot, LIF beside him."""
    out = before_kick_off_positions(bx, by)
    out[11] = ( -1.0,  0.0)
    out[9]  = ( -2.5, -2.0)
    return out


# ---- generation -------------------------------------------------------

def load_f433(src: pathlib.Path) -> dict:
    return json.loads(src.read_text())


def replace_positions(
    f433_conf: dict,
    rule: Callable[[float, float], dict[int, tuple[float, float]]],
    static: bool = False,
) -> dict:
    """Replace each (data[*][1..11]) with rule(ball.x, ball.y).

    If static=True we ignore F433's ball samples and emit ONE static
    sample at ball=(0,0). This matches helios's static-formation
    convention for set-pieces / kick-offs.
    """
    new = copy.deepcopy(f433_conf)
    new["role"] = ROLES

    if static:
        # Keep only sample index 0, place ball at centre.
        rep = rule(0.0, 0.0)
        sample = {"index": 0, "ball": {"x": 0.0, "y": 0.0}}
        for unum, (x, y) in rep.items():
            sample[str(unum)] = {"x": round2(x), "y": round2(y)}
        new["data"] = [sample]
    else:
        out = []
        for i, s in enumerate(f433_conf["data"]):
            bx = s["ball"]["x"]
            by = s["ball"]["y"]
            rep = rule(bx, by)
            sample = {"index": i, "ball": {"x": bx, "y": by}}
            for unum, (x, y) in rep.items():
                sample[str(unum)] = {"x": round2(x), "y": round2(y)}
            out.append(sample)
        new["data"] = out

    new["version"] = "F325 v2 (F433-Delaunay borrowed)"
    return new


# Mapping: F325 output filename → (F433 source filename, rule_fn, static flag)
MAPPING: list[tuple[str, str, Callable, bool]] = [
    ("F325_offense-formation.conf",
        "F433_offense-formation.conf",  offense_positions,           False),
    ("F325_defense-formation.conf",
        "F433_defense-formation.conf",  defense_positions,           False),
    ("F325_kickin-our-formation.conf",
        "F433_kickin-our-formation.conf", kickin_our_positions,      False),
    ("F325_setplay-our-formation.conf",
        "F433_setplay-our-formation.conf", setplay_our_positions,    False),
    ("F325_setplay-opp-formation.conf",
        "F433_setplay-opp-formation.conf", setplay_opp_positions,    False),
    ("F325_goal-kick-our.conf",
        "F433_goal-kick-our.conf",      goal_kick_our_positions,     True),
    ("F325_goal-kick-opp.conf",
        "F433_goal-kick-opp.conf",      goal_kick_opp_positions,     True),
    ("F325_before-kick-off.conf",
        "F433_before-kick-off.conf",    before_kick_off_positions,   True),
    ("F325_before-kick-off_for_our_kick.conf",
        "F433_before-kick-off_for_our_kick.conf", before_kick_off_our_positions,
        True),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src",
                    default="externals/src/cyrus-team/src/formations-dt",
                    help="Source F433 formation directory")
    ap.add_argument("--dest",
                    default="externals/patches/cyrus-team/src/formations-dt",
                    help="Destination directory for F325_*.conf")
    args = ap.parse_args()

    src_dir = pathlib.Path(args.src)
    dest_dir = pathlib.Path(args.dest)
    dest_dir.mkdir(parents=True, exist_ok=True)

    missing = []
    for dst_name, src_name, rule, static in MAPPING:
        src_path = src_dir / src_name
        if not src_path.exists():
            missing.append(str(src_path))
            continue
        f433 = load_f433(src_path)
        f325 = replace_positions(f433, rule, static=static)
        dst_path = dest_dir / dst_name
        dst_path.write_text(json.dumps(f325, indent=2) + "\n")
        print(f"  wrote {dst_path.relative_to(pathlib.Path('.'))}")

    if missing:
        print(f"\nWARNING: missing source files: {missing}", file=sys.stderr)
    print(f"\ndone. {len(MAPPING)} F325 files in {dest_dir}/")


if __name__ == "__main__":
    main()
