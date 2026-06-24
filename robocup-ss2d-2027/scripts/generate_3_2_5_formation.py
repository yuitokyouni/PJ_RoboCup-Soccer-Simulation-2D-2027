#!/usr/bin/env python3
"""Generate helios-compatible 3-2-5 formation files.

Writes both `normal-formation.conf` (DelaunayTriangulation, in-play
positioning) and `before-kick-off.conf` (Static, kickoff lineup) so
the player numbers carry the same role assignment across phases --
otherwise the engine treats e.g. #5 as a SideBack at kickoff and a
SideHalf during play, and the visual transition looks like a
4-back rather than 3-2-5.

Tactical design (per user spec, refined after first match):
- 3 CenterBacks (#2 L, #3 C sweeper, #4 R)
- 2 SideHalves acting as wing-backs (#5 L, #8 R)
    - LOW when defending (deep in our half) -- form a back 5
    - HIGH when attacking -- join the forward line for a true
      3-2-5 with a 5-man front
- 2 DefensiveHalves (#6, #7) drop into the back during build-up
- 3 Forwards (#9 LW, #10 RW, #11 CF)
"""
import json
import sys
from pathlib import Path

ROLES = [
    {"number": 1,  "name": "Goalie",        "type": "G",  "side": "C", "pair": 0},
    {"number": 2,  "name": "CenterBack",    "type": "DF", "side": "L", "pair": 4},
    {"number": 3,  "name": "CenterBack",    "type": "DF", "side": "C", "pair": 0},
    {"number": 4,  "name": "CenterBack",    "type": "DF", "side": "R", "pair": 2},
    {"number": 5,  "name": "SideHalf",      "type": "MF", "side": "L", "pair": 8},
    {"number": 6,  "name": "DefensiveHalf", "type": "MF", "side": "L", "pair": 7},
    {"number": 7,  "name": "DefensiveHalf", "type": "MF", "side": "R", "pair": 6},
    {"number": 8,  "name": "SideHalf",      "type": "MF", "side": "R", "pair": 5},
    {"number": 9,  "name": "SideForward",   "type": "FW", "side": "L", "pair": 10},
    {"number": 10, "name": "SideForward",   "type": "FW", "side": "R", "pair": 9},
    {"number": 11, "name": "CenterForward", "type": "FW", "side": "C", "pair": 0},
]

# before-kick-off.conf uses static "Unknown"-typed roles in helios's
# default but the name+number must still resolve in the engine; copy
# the same names with type="Unknown" per the helios convention for
# this phase.
KICKOFF_ROLES = [
    {**r, "type": "Unknown", "pair": 0} for r in ROLES
]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def positions(ball_x: float, ball_y: float) -> dict:
    """Compute the 11 player positions for a given ball position.

    f in [-1, +1] is the "attacking phase" indicator:
      f = -1 : ball deep in our half  -> low block 5-3-2 shape
      f =  0 : ball at midfield       -> 3-2-5 transition
      f = +1 : ball deep in their half -> 3-2-5 with WBs at the FW line

    Key refinement: wb_x now climbs to +28 at f=+1 so the wing-backs
    sit on the forward line (5-FW shape: WB-L, SF-L, CF, SF-R, WB-R),
    not 10 m behind it as in the first iteration.
    """
    f = clamp(ball_x / 30.0, -1.0, 1.0)
    y_lean = clamp(ball_y * 0.15, -6.0, 6.0)

    # Back 3 -- push up aggressively in attack
    cb_x = -32.0 + 25.0 * (f + 1) / 2          # [-32, -7]
    cb_l = (cb_x, -10.0 + y_lean)
    cb_c = (cb_x - 2.5, 0.0 + y_lean * 0.6)
    cb_r = (cb_x, +10.0 + y_lean)

    # Wing-backs -- TRUE 3-2-5 means WBs are on the FW line in attack
    wb_x = -22.0 + 50.0 * (f + 1) / 2          # [-22, +28]
    wb_l = (wb_x, -26.0 + y_lean * 0.3)
    wb_r = (wb_x, +26.0 + y_lean * 0.3)

    # 2 central defensive midfielders, with build-up drop
    cm_x = -10.0 + 30.0 * (f + 1) / 2          # [-10, +20]
    buildup_drop = max(0.0, -f - 0.2) * 8.0
    cm_l = (cm_x - 2.0 - buildup_drop, -6.0 + y_lean)
    cm_r = (cm_x - 2.0 - buildup_drop, +6.0 + y_lean)

    # 3 forwards
    fw_x = 12.0 + 24.0 * (f + 1) / 2           # [12, +36]
    fw_l = (fw_x, -16.0 + y_lean * 0.4)
    fw_r = (fw_x, +16.0 + y_lean * 0.4)
    cf   = (fw_x + 4.0, 0.0 + y_lean * 0.4)

    gk = (-50.0, clamp(ball_y * 0.05, -3.0, 3.0))

    return {
        1: gk, 2: cb_l, 3: cb_c, 4: cb_r,
        5: wb_l, 6: cm_l, 7: cm_r, 8: wb_r,
        9: fw_l, 10: fw_r, 11: cf,
    }


def build_delaunay_data() -> list:
    points = []
    idx = 0
    xs = [-50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50]
    ys = [-30, -15, 0, +15, +30]
    for bx in xs:
        for by in ys:
            pos = positions(bx, by)
            rec = {"index": idx, "ball": {"x": float(bx), "y": float(by)}}
            for unum in range(1, 12):
                px, py = pos[unum]
                rec[str(unum)] = {
                    "x": round(clamp(px, -51.0, 51.0), 2),
                    "y": round(clamp(py, -32.0, 32.0), 2),
                }
            points.append(rec)
            idx += 1
    return points


def build_kickoff_data() -> list:
    """All 11 players in our half (kickoff rule: all stay home)."""
    return [{
        "index": 0,
        "ball": {"x": 0.0, "y": 0.0},
        # 3-2-5 lineup in our half, mirroring the normal-formation shape
        "1":  {"x": -49.00, "y":   0.00},
        "2":  {"x": -32.00, "y": -12.00},
        "3":  {"x": -34.50, "y":   0.00},
        "4":  {"x": -32.00, "y":  12.00},
        "5":  {"x": -16.00, "y": -26.00},
        "6":  {"x": -12.00, "y":  -6.00},
        "7":  {"x": -12.00, "y":   6.00},
        "8":  {"x": -16.00, "y":  26.00},
        "9":  {"x":  -2.00, "y": -16.00},
        "10": {"x":  -2.00, "y":  16.00},
        "11": {"x":  -1.00, "y":   0.00},
    }]


def write_normal(path: Path):
    formation = {
        "version": "3-2-5 wingback-fluid v2 (WBs join FW line in attack)",
        "method": "DelaunayTriangulation",
        "role": ROLES,
        "data": build_delaunay_data(),
    }
    path.write_text(json.dumps(formation, indent=2) + "\n")
    print(f"wrote {path} ({len(formation['data'])} delaunay points)")


def write_kickoff(path: Path):
    formation = {
        "version": "3-2-5 kickoff v2",
        "method": "Static",
        "role": KICKOFF_ROLES,
        "data": build_kickoff_data(),
    }
    path.write_text(json.dumps(formation, indent=2) + "\n")
    print(f"wrote {path} (static kickoff lineup)")


def main() -> int:
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    write_normal(out_dir / "normal-formation.conf")
    write_kickoff(out_dir / "before-kick-off.conf")
    return 0


if __name__ == "__main__":
    sys.exit(main())

