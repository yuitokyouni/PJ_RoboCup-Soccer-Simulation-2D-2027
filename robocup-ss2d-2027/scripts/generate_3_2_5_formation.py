#!/usr/bin/env python3
"""Generate the three phase-specific formation files for the
HELIOS_3_2_5 wingback-fluid system:

  normal-formation.conf   = 3-2-5 (mid-block, ball at midfield)
  offense-formation.conf  = 3-2-5 pushed up, forwards INSIDE the box
  defense-formation.conf  = 5-3-2 compact, WBs joined to back line

Same role list across the three files; only the (ball -> position)
data points change. The roles are helios-base-compatible (no WingBack
in M_role_factory, so wingbacks are typed SideHalf).

Compared to the v1 single-file generator this script:
  - pushes forward_x past +40 in the attacking-third anchor, so
    forwards can actually crash the penalty area
  - drops WB_x to -30 in the deep-defense anchor (CB line is at -34
    in defense), giving a real back-5
  - produces a separate defense-formation that holds 5-3-2 regardless
    of ball position (the engine switches to this file when our team
    is defending)
  - produces a separate offense-formation that holds 3-2-5 with
    forwards near the opponent goal line regardless of ball position

The interceptor logic in Bhv_BasicMove still overrides any of this for
the player closest to the ball; the formation only fixes "rest" /
"non-intercepting" positions.
"""
import json
import sys
from pathlib import Path

ROLES = [
    {"number": 1,  "name": "Goalie",           "type": "G",  "side": "C", "pair": 0},
    {"number": 2,  "name": "CenterBack",       "type": "DF", "side": "L", "pair": 4},
    {"number": 3,  "name": "CenterBack",       "type": "DF", "side": "C", "pair": 0},
    {"number": 4,  "name": "CenterBack",       "type": "DF", "side": "R", "pair": 2},
    {"number": 5,  "name": "SideHalf",         "type": "MF", "side": "L", "pair": 8},
    {"number": 6,  "name": "DefensiveHalf",    "type": "MF", "side": "L", "pair": 7},
    {"number": 7,  "name": "DefensiveHalf",    "type": "MF", "side": "R", "pair": 6},
    {"number": 8,  "name": "SideHalf",         "type": "MF", "side": "R", "pair": 5},
    {"number": 9,  "name": "SideForward",      "type": "FW", "side": "L", "pair": 10},
    {"number": 10, "name": "SideForward",      "type": "FW", "side": "R", "pair": 9},
    {"number": 11, "name": "CenterForward",    "type": "FW", "side": "C", "pair": 0},
]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def normal_positions(bx, by):
    """Mid-block 3-2-5 that scales with ball x."""
    f = clamp(bx / 30.0, -1.0, 1.0)
    y_lean = clamp(by * 0.15, -6.0, 6.0)

    cb_x = -32.0 + 18.0 * (f + 1) / 2
    wb_x = -28.0 + 42.0 * (f + 1) / 2          # [-28, +14] -- low in own half
    cm_x = -10.0 + 24.0 * (f + 1) / 2
    cm_x -= max(0.0, -f - 0.2) * 8.0           # build-up drop
    fw_x = 12.0 + 30.0 * (f + 1) / 2           # [12, +42] -- crash the box

    return {
        1:  (-50.0, clamp(by * 0.05, -3, 3)),
        2:  (cb_x, -10 + y_lean),
        3:  (cb_x - 2.5, 0 + y_lean * 0.6),
        4:  (cb_x, +10 + y_lean),
        5:  (wb_x, -28 + y_lean * 0.4),
        6:  (cm_x - 2, -6 + y_lean),
        7:  (cm_x - 2, +6 + y_lean),
        8:  (wb_x, +28 + y_lean * 0.4),
        9:  (fw_x, -16 + y_lean * 0.5),
        10: (fw_x, +16 + y_lean * 0.5),
        11: (fw_x + 6, 0 + y_lean * 0.5),
    }


def offense_positions(bx, by):
    """3-2-5 high. Forwards INSIDE the box; WBs as wide forwards.

    Even when the ball is in our half we still hold the offensive
    shape because the engine only picks this file when our team has
    the initiative.
    """
    # v3 lesson: CB line at -8 in v2 cost an 18-4 (first goal at
    # cycle 114, ~11 s of game time). Cap CB depth so a single
    # turnover doesn't become a free run on goal.
    f = clamp(bx / 30.0, -0.4, 1.0)        # never drop below f=-0.4
    y_lean = clamp(by * 0.2, -8.0, 8.0)
    cb_x = -28.0 + 8.0 * (f + 1) / 2        # [-28, -20]
    wb_x = -10.0 + 25.0 * (f + 1) / 2       # [-10, +15]
    cm_x =  -5.0 + 20.0 * (f + 1) / 2       # [-5, +15]
    fw_x = +20.0 + 18.0 * (f + 1) / 2       # [+20, +38] -- penalty arc, not the goal line

    return {
        1:  (-50.0, 0.0),
        2:  (cb_x, -10 + y_lean),
        3:  (cb_x - 2, 0 + y_lean * 0.6),
        4:  (cb_x, +10 + y_lean),
        5:  (wb_x, -26 + y_lean * 0.4),
        6:  (cm_x, -6 + y_lean),
        7:  (cm_x, +6 + y_lean),
        8:  (wb_x, +26 + y_lean * 0.4),
        9:  (fw_x, -14 + y_lean * 0.5),
        10: (fw_x, +14 + y_lean * 0.5),
        11: (fw_x + 4, 0 + y_lean * 0.5),
    }


def defense_positions(bx, by):
    """5-3-2 compact. Five across the back, three in midfield,
    two forwards holding the half-spaces for the counter outlet.

    All positions track ball x more conservatively -- back line never
    pushes past -10 even when ball is at midfield; only the two
    forwards stay high.
    """
    f = clamp(bx / 40.0, -1.0, 0.3)
    y_lean = clamp(by * 0.25, -10.0, 10.0)

    back_x = -34.0 + 14.0 * (f + 1) / 2      # [-34, -27] -- low block
    mid_x  = -18.0 + 14.0 * (f + 1) / 2      # [-18, -11]
    fw_x   =  -2.0 + 14.0 * (f + 1) / 2      # [-2, +5]   -- only outlets stay high

    return {
        1:  (-50.0, 0.0),
        # FIVE-back across: WBs join the back line
        2:  (back_x, -10 + y_lean),       # CB L
        3:  (back_x - 2, 0 + y_lean * 0.6),  # CB C (sweeper)
        4:  (back_x, +10 + y_lean),        # CB R
        5:  (back_x + 2, -26 + y_lean * 0.3),   # WB L
        8:  (back_x + 2, +26 + y_lean * 0.3),   # WB R
        # THREE midfielders flat
        6:  (mid_x, -10 + y_lean),
        7:  (mid_x, +10 + y_lean),
        # The CenterForward drops to support
        11: (mid_x + 6, 0 + y_lean),
        # TWO forwards as counter outlets -- stay high
        9:  (fw_x, -16 + y_lean * 0.4),
        10: (fw_x, +16 + y_lean * 0.4),
    }


def build(positions_fn) -> list:
    points = []
    idx = 0
    xs = [-50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50]
    ys = [-30, -15, 0, +15, +30]
    for bx in xs:
        for by in ys:
            pos = positions_fn(bx, by)
            record = {"index": idx, "ball": {"x": float(bx), "y": float(by)}}
            for unum in range(1, 12):
                px, py = pos[unum]
                record[str(unum)] = {
                    "x": round(clamp(px, -51.0, 51.0), 2),
                    "y": round(clamp(py, -32.0, 32.0), 2),
                }
            points.append(record)
            idx += 1
    return points


def write_formation(out_path: Path, version_tag: str, positions_fn) -> None:
    formation = {
        "version": version_tag,
        "method": "DelaunayTriangulation",
        "role": ROLES,
        "data": build(positions_fn),
    }
    out_path.write_text(json.dumps(formation, indent=2) + "\n")
    print(f"wrote {out_path} ({len(formation['data'])} training points)")


def main() -> int:
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    write_formation(out_dir / "normal-formation.conf",  "3-2-5 normal v2",  normal_positions)
    write_formation(out_dir / "offense-formation.conf", "3-2-5 offense v2", offense_positions)
    write_formation(out_dir / "defense-formation.conf", "5-3-2 defense v2", defense_positions)
    return 0


if __name__ == "__main__":
    sys.exit(main())
