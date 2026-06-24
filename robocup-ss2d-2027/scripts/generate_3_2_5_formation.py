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
    # v10: WBs typed as SideBack (fullback) -- more defensive role
    # logic than SideHalf, less likely to charge upfield and leave
    # the back line vulnerable.
    {"number": 5,  "name": "SideBack",         "type": "DF", "side": "L", "pair": 8},
    {"number": 6,  "name": "DefensiveHalf",    "type": "MF", "side": "L", "pair": 7},
    {"number": 7,  "name": "DefensiveHalf",    "type": "MF", "side": "R", "pair": 6},
    {"number": 8,  "name": "SideBack",         "type": "DF", "side": "R", "pair": 5},
    {"number": 9,  "name": "SideForward",      "type": "FW", "side": "L", "pair": 10},
    {"number": 10, "name": "SideForward",      "type": "FW", "side": "R", "pair": 9},
    {"number": 11, "name": "CenterForward",    "type": "FW", "side": "C", "pair": 0},
]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def normal_positions(bx, by):
    """v5: defensive-by-default normal. Helios switches Defense
    only when opp_min <= our_min - 2; the contested 50/50 case is
    Normal, and our team needs to be in a safe shape there. Back
    line tracks the ball deep into our half; forwards stay as
    counter outlets.
    """
    # v7: revert to v5-ish back depth (deeper than v3, less extreme
    # than v6). The 12-1 in v6 showed that over-compressing the
    # back line just gives helios a free zone in our 3rd to crash
    # into. v7 holds the v5 anchor that gave 9-1.
    back_x = clamp(bx - 12, -45.0, -20.0)
    y_lean = clamp(by * 0.35, -12.0, 12.0)
    wb_x = back_x + 4.0
    cm_x = back_x + 14.0
    fw_x = clamp(back_x + 38.0, 0.0, 38.0)

    return {
        1:  (-50.0, clamp(by * 0.05, -3, 3)),
        2:  (back_x, -10 + y_lean),
        3:  (back_x - 2.5, 0 + y_lean * 0.6),
        4:  (back_x, +10 + y_lean),
        5:  (wb_x, -27 + y_lean * 0.4),
        6:  (cm_x, -7 + y_lean),
        7:  (cm_x, +7 + y_lean),
        8:  (wb_x, +27 + y_lean * 0.4),
        9:  (fw_x, -16 + y_lean * 0.5),
        10: (fw_x, +16 + y_lean * 0.5),
        11: (fw_x + 4, 0 + y_lean * 0.5),
    }


def offense_positions(bx, by):
    """3-2-5 high. Forwards INSIDE the box; WBs as wide forwards.

    Even when the ball is in our half we still hold the offensive
    shape because the engine only picks this file when our team has
    the initiative.
    """
    # v7: pull offense back hard. Even when we have the ball, the
    # CB line never goes higher than -25. Forwards still push to
    # the penalty arc but the back is safe against turnover.
    f = clamp(bx / 30.0, -0.4, 1.0)
    y_lean = clamp(by * 0.2, -8.0, 8.0)
    cb_x = -32.0 + 7.0 * (f + 1) / 2        # [-32, -25]
    wb_x = -16.0 + 18.0 * (f + 1) / 2       # [-16, +2]
    cm_x = -10.0 + 18.0 * (f + 1) / 2       # [-10, +8]
    fw_x = +14.0 + 18.0 * (f + 1) / 2       # [+14, +32]

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
    """v9: ULTRA park-the-bus. When ball is in our half, every
    outfielder except one "outlet" forward camps inside or on the
    edge of the 18 yd box. Goalie at the line. Nine bodies between
    the ball and the goal.
    """
    # When ball in our half, lock everyone deep. Otherwise hold a
    # very compact mid-block.
    if bx <= 0:
        back_x = clamp(bx - 4, -46.0, -32.0)
    else:
        back_x = -28.0
    y_lean = clamp(by * 0.6, -18.0, 18.0)
    box_x = back_x + 6.0       # second line right behind back, in the box

    return {
        1:  (-50.0, clamp(by * 0.05, -3, 3)),
        # First line (back 5) -- across the goal mouth + posts
        2:  (back_x, -8 + y_lean * 0.5),
        3:  (back_x - 2, 0 + y_lean * 0.3),
        4:  (back_x, +8 + y_lean * 0.5),
        5:  (back_x, -20 + y_lean * 0.3),
        8:  (back_x, +20 + y_lean * 0.3),
        # Second line, 4 across, tucked just in front -- creates
        # a wall of 9 bodies in/around the box
        6:  (box_x, -12 + y_lean),
        7:  (box_x, +12 + y_lean),
        11: (box_x, 0 + y_lean),
        9:  (box_x, -22 + y_lean * 0.5),
        # 10 stays as the single counter outlet
        10: (clamp(back_x + 35, 0, 30), 0 + y_lean * 0.5),
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
