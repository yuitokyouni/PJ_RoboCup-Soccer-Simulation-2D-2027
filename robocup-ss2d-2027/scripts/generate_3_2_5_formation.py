#!/usr/bin/env python3
"""Generate a 3-2-5 normal-formation.conf for helios-base.

Output format matches helios-base/src/formations-dt/normal-formation.conf:
  {"version", "method": "DelaunayTriangulation",
   "role": [11 role dicts],
   "data": [{"index","ball","1","2",...,"11"}, ...]}

Tactical design (per user spec 2026-06-24):
- 3 CenterBacks (#2 L, #3 C sweeper, #4 R) hold the line.
- 2 CentralDefensiveMidfielders (#6, #7) start as a flat pair, drop
  into the back line during build-up (ball deep in our half).
- 2 WingBacks (#5 L, #8 R) sit low when defending, advance to a
  wide-forward line when the ball is in the opponent half.
- 3 Forwards (#9 left winger, #10 right winger, #11 striker) hold
  the attacking width and depth.

The Delaunay triangulation interpolates between (ball -> 11 positions)
training points. We emit a grid of ball positions across the pitch
and parametrically compute each player's intended position from the
ball's x-axis (defensive third <-> middle third <-> attacking third)
and a small lateral lean toward the ball's y side.
"""
import json
import sys
from pathlib import Path

# Field is 105x68; x in [-52.5, +52.5], y in [-34, +34]. Our goal at x=-52.5.

# helios-base's strategy.cpp accepts only these role names (see
# M_role_factory entries in player/strategy.cpp). "WingBack" is not in
# the set, so our wing-backs are typed as SideHalf -- the closest
# match in spirit: a wide midfielder that the role's own positioning
# logic already drives both vertically (defensive vs offensive
# halves) and laterally.
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


def positions(ball_x: float, ball_y: float) -> dict:
    """Compute the 11 player positions for a given ball position.

    f in [-1, +1] is the "attacking phase" indicator:
      f = -1 : ball deep in our half  -> low block 5-3-2 shape
      f =  0 : ball at midfield       -> 3-2-5 transition
      f = +1 : ball deep in their half -> 3-2-5 with WBs high
    """
    f = clamp(ball_x / 30.0, -1.0, 1.0)

    # Small lateral lean toward the ball side (keeps the shape compact,
    # never lets a player cross to the other touchline).
    y_lean = clamp(ball_y * 0.15, -6.0, 6.0)

    # --- back 3 (3 CBs) ---
    cb_x = -32.0 + 18.0 * (f + 1) / 2          # [-32, -14]
    cb_l = (cb_x, -10.0 + y_lean)
    cb_c = (cb_x - 2.5, 0.0 + y_lean * 0.6)    # sweeper slightly deeper
    cb_r = (cb_x, +10.0 + y_lean)

    # --- 2 wing-backs ---
    # When defending (f<0) WBs are LOW (near CB line + a bit forward).
    # When attacking (f>0) WBs are HIGH on the forward line.
    wb_x = -22.0 + 38.0 * (f + 1) / 2          # [-22, +16]
    wb_l = (wb_x, -27.0 + y_lean * 0.4)
    wb_r = (wb_x, +27.0 + y_lean * 0.4)

    # --- 2 central defensive midfielders ---
    # In build-up (f<0) one DM "drops" into the back line by sliding
    # toward the CB line; in attack (f>0) they push to the half-spaces.
    cm_x = -10.0 + 24.0 * (f + 1) / 2          # [-10, +14]
    buildup_drop = max(0.0, -f - 0.2) * 8.0    # extra retreat in build-up
    cm_l = (cm_x - 2.0 - buildup_drop, -6.0 + y_lean)
    cm_r = (cm_x - 2.0 - buildup_drop, +6.0 + y_lean)

    # --- 3 forwards ---
    fw_x = 10.0 + 22.0 * (f + 1) / 2           # [10, +32]
    fw_l = (fw_x, -16.0 + y_lean * 0.5)
    fw_r = (fw_x, +16.0 + y_lean * 0.5)
    cf   = (fw_x + 6.0, 0.0 + y_lean * 0.5)

    # --- Goalie ---
    gk = (-50.0, clamp(ball_y * 0.05, -3.0, 3.0))

    return {
        1:  gk,
        2:  cb_l,
        3:  cb_c,
        4:  cb_r,
        5:  wb_l,
        6:  cm_l,
        7:  cm_r,
        8:  wb_r,
        9:  fw_l,
        10: fw_r,
        11: cf,
    }


def build_data_points() -> list:
    """Grid of ball positions across the pitch, mirrored across y=0."""
    points = []
    idx = 0
    # x grid: defensive third / middle third / attacking third + extremes
    xs = [-50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50]
    # y grid: top sideline / wing / centre / wing / bottom sideline
    ys = [-30, -15, 0, +15, +30]
    for bx in xs:
        for by in ys:
            pos = positions(bx, by)
            record = {"index": idx, "ball": {"x": float(bx), "y": float(by)}}
            for unum in range(1, 12):
                px, py = pos[unum]
                # Clamp to pitch boundaries with a 1 m margin so players
                # never end up off the field in the training points.
                px = clamp(px, -51.0, 51.0)
                py = clamp(py, -32.0, 32.0)
                record[str(unum)] = {"x": round(px, 2), "y": round(py, 2)}
            points.append(record)
            idx += 1
    return points


def main() -> int:
    out = Path(sys.argv[1])
    data = build_data_points()
    formation = {
        "version": "3-2-5 wingback-fluid generated 2026-06-24",
        "method": "DelaunayTriangulation",
        "role": ROLES,
        "data": data,
    }
    out.write_text(json.dumps(formation, indent=2) + "\n")
    print(f"wrote {out} ({len(data)} training points)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
