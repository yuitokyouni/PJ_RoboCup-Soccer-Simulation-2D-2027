#!/usr/bin/env python3
"""
Convert helios_3_2_5_formations/*.conf into Cyrus-compatible
F325_*.conf files.

Cyrus formation .conf format constraints (vs helios):
  - role[].name MUST be "Player" (or "Goalie" for #1)
  - role[].type MUST be "G" for goalie, "MF" for every field player
    (Cyrus doesn't use "DF" / "FW")
  - everything else (number, side, pair, data[]) stays untouched

Output mapping:
  helios before-kick-off.conf     -> F325_before-kick-off.conf
                                  -> F325_before-kick-off_for_our_kick.conf (copy)
  helios defense-formation.conf   -> F325_defense-formation.conf
  helios offense-formation.conf   -> F325_offense-formation.conf
  helios normal-formation.conf    -> (dropped; Cyrus does not use a "normal" file;
                                      offense-formation covers it via situation switch)
  helios goal-kick-opp.conf       -> F325_goal-kick-opp.conf
  helios goal-kick-our.conf       -> F325_goal-kick-our.conf
  helios kickin-our-formation.conf -> F325_kickin-our-formation.conf
  helios setplay-opp-formation.conf -> F325_setplay-opp-formation.conf
  helios setplay-our-formation.conf -> F325_setplay-our-formation.conf

Run from project root:
  python3 externals/patches/cyrus-team/src/build_f325_formations.py
"""
import json
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[4]
SRC_DIR = REPO_ROOT / "experiments" / "helios_3_2_5_formations"
DEST_DIR = REPO_ROOT / "externals" / "patches" / "cyrus-team" / "src" / "formations-dt"

MAPPING = {
    "before-kick-off.conf":           ["F325_before-kick-off.conf",
                                       "F325_before-kick-off_for_our_kick.conf"],
    "defense-formation.conf":         ["F325_defense-formation.conf"],
    "offense-formation.conf":         ["F325_offense-formation.conf"],
    "goal-kick-opp.conf":             ["F325_goal-kick-opp.conf"],
    "goal-kick-our.conf":             ["F325_goal-kick-our.conf"],
    "kickin-our-formation.conf":      ["F325_kickin-our-formation.conf"],
    "setplay-opp-formation.conf":     ["F325_setplay-opp-formation.conf"],
    "setplay-our-formation.conf":     ["F325_setplay-our-formation.conf"],
}


def convert(role_list):
    """Rewrite role[] entries to Cyrus's flat 'Player/MF' convention."""
    for r in role_list:
        if r["number"] == 1:
            r["name"] = "Goalie"
            r["type"] = "G"
        else:
            r["name"] = "Player"
            r["type"] = "MF"
    return role_list


def process(src_path, dest_paths):
    raw = json.loads(src_path.read_text())
    raw["role"] = convert(raw["role"])
    raw["version"] = f"F325 ({raw.get('version', 'v?')})"
    for dest in dest_paths:
        DEST_DIR.mkdir(parents=True, exist_ok=True)
        dest_full = DEST_DIR / dest
        dest_full.write_text(json.dumps(raw, indent=2) + "\n")
        print(f"  wrote {dest_full.relative_to(REPO_ROOT)}")


def main():
    missing = []
    for src, dests in MAPPING.items():
        src_path = SRC_DIR / src
        if not src_path.exists():
            missing.append(src)
            continue
        print(f"converting {src} -> {len(dests)} F325 file(s)")
        process(src_path, dests)
    if missing:
        print(f"WARNING: missing source files: {missing}", file=sys.stderr)
    print(f"done. {sum(len(v) for v in MAPPING.items())} F325 files in {DEST_DIR.relative_to(REPO_ROOT)}/")


if __name__ == "__main__":
    main()
