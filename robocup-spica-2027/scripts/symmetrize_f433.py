#!/usr/bin/env python3
"""Symmetrize F433 .conf files by cloning the strong-side (-Y) response
to the weak-side (+Y).

Empirical finding (notes/2026-06-27_side_clone.md): the F433 Delaunay
conf files have a Y-axis BIAS — players retreat ~10m toward -Y when the
ball is at -Y, but only ~6m toward +Y when the ball is at +Y. This makes
the team defend -Y wing attacks well but +Y wing attacks weakly.

User directive (2026-06-27): clone strong-side settings (-Y) onto
weak-side settings (+Y) by overwriting each (bx, +by) sample with the
Y-mirror of the corresponding (bx, -by) sample.

Operation per ball sample (bx, by) with by > 0:
  1. Find sibling sample at (bx, -by). If missing, skip.
  2. For each unum, compute mirrored position:
       if unum has pair p (p > 0):
           target.x = sibling[p].x
           target.y = -sibling[p].y
       else:
           target.x = sibling[unum].x
           target.y = -sibling[unum].y
  3. Overwrite (bx, +by) sample's player positions with the mirror.

Run from project root:
  python3 scripts/symmetrize_f433.py            # dry-run: list changes
  python3 scripts/symmetrize_f433.py --apply    # write back
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Snapshots that contain the F433 conf set
SNAPSHOTS = [
    "externals/src/cyrus-team-v3-snapshot/src/formations-dt",
    "externals/src/cyrus-team-v3-snapshot/build/src/formations-dt",
]

# kickoff conf files only have one sample, no Y-symmetrization needed
SYMMETRIZE_PATTERNS = [
    "F433_defense-formation.conf",
    "F433_offense-formation.conf",
    "F433_offense-formation_for_mt.conf",
    "F433_offense-formation_for_oxsy.conf",
    "F433_offense-formation_for_yush.conf",
    "F433_setplay-opp-formation.conf",
    "F433_setplay-our-formation.conf",
    "F433_kickin-our-formation.conf",
]


def build_mirror_table(roles: list) -> dict:
    """Build unum -> mirror_unum map.

    Cyrus's Delaunay role pairing:
      pair = 0   -> centered single-side role; mirrors with itself (Y-flip).
      pair = N>0 -> this role is the RIGHT-side counterpart of role N.
                   N has pair=-1 (LEFT-side counterpart).
                   So mirror[this] = N and mirror[N] = this.
      pair = -1  -> LEFT-side role with no direct pair pointer; its mirror
                   is the role whose pair field equals this role's number.
                   We set it implicitly when processing the pair=N>0 side.
    """
    mirror = {}
    for r in roles:
        n, p = r["number"], r["pair"]
        if p == 0:
            mirror[n] = n
        elif p > 0:
            mirror[n] = p
            mirror[p] = n
        # pair = -1 handled implicitly by the pair=N>0 branch above
    return mirror


def symmetrize(conf_path: pathlib.Path) -> tuple[dict, int, int]:
    d = json.loads(conf_path.read_text())
    roles = d["role"]
    mirror = build_mirror_table(roles)
    samples = d["data"]
    by_pos = {(round(s["ball"]["x"], 2), round(s["ball"]["y"], 2)): s for s in samples}

    n_overwritten = 0
    n_missing_sibling = 0

    for s in samples:
        bx, by = s["ball"]["x"], s["ball"]["y"]
        if by <= 0:
            continue
        sibling = by_pos.get((round(bx, 2), round(-by, 2)))
        if sibling is None:
            n_missing_sibling += 1
            continue
        for num in range(1, 12):
            mir = mirror.get(num, num)
            src = sibling[str(mir)]
            s[str(num)] = {"x": src["x"], "y": -src["y"]}
        n_overwritten += 1
    return d, n_overwritten, n_missing_sibling


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="write back; default is dry-run")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    total = 0
    for snap in SNAPSHOTS:
        snap_dir = root / snap
        if not snap_dir.is_dir():
            continue
        for name in SYMMETRIZE_PATTERNS:
            conf = snap_dir / name
            if not conf.is_file():
                continue
            new_d, n_over, n_miss = symmetrize(conf)
            print(f"{conf.relative_to(root)}: rewrote {n_over} +Y samples, "
                  f"{n_miss} missing-sibling skipped")
            if args.apply:
                # add a versioning tag so downstream tools see the change
                new_d["version"] = new_d.get("version", "0") + "+sym-2026-06-27"
                # write with the same compact-ish formatting as Cyrus uses
                conf.write_text(json.dumps(new_d, indent=2) + "\n")
                total += n_over
    if args.apply:
        print(f"applied: {total} samples rewritten across {len(SNAPSHOTS)} snapshot(s)")
    else:
        print("dry run: pass --apply to write back")


if __name__ == "__main__":
    main()
