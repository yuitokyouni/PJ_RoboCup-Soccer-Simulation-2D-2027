#!/usr/bin/env python3
"""Deep analysis of REV (Spica Y-sym F433 + defensive kickoff) tournament matches.

For each match that REV participated in:
  1. Parse rcl (text command log) for referee events: goals, kick-offs, set pieces.
  2. Parse rcg via rcg2txt for ball / player positions per cycle.
  3. For each goal CONCEDED by REV, extract the 20-cycle preamble:
       - Ball trajectory (where attack originated, x/y at goal time)
       - Defensive shape (CB/WB positions vs ball)
       - Set-piece origin if any
  4. For each goal SCORED by REV, same.
  5. Aggregate: where does REV concede / score?

Run from project root with rcssserver tools in PATH:
  PATH="$PWD/externals/install/bin:$PATH" python3 scripts/analyze_rev_matches.py
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXP = ROOT / "logs/experiments"
RCG2TXT = ROOT / "externals/install/bin/rcg2txt"


@dataclass
class MatchRefereeEvents:
    match_dir: pathlib.Path
    rev_side: str  # "l" or "r"
    opp: str
    rev_score: int = 0
    opp_score: int = 0
    # Each goal: (cycle, scoring_side ['l'/'r'], goal_num)
    goals: list = field(default_factory=list)
    # Each set-piece: (cycle, mode, side ['l'/'r'])
    set_pieces: list = field(default_factory=list)
    # offsides
    offsides: list = field(default_factory=list)
    fouls: list = field(default_factory=list)


def parse_rcl(rcl_path: pathlib.Path) -> list[tuple[int, str]]:
    """Return list of (cycle, referee_event_str)."""
    events = []
    with open(rcl_path) as f:
        for line in f:
            # Format: "cycle,subcycle\t(referee EVENT)"
            m = re.match(r"^(\d+),\d+\s+\(referee\s+([^)]+)\)", line)
            if m:
                events.append((int(m.group(1)), m.group(2)))
    return events


def parse_rcg_at_cycles(rcg_path: pathlib.Path, target_cycles: set[int]) -> dict:
    """Run rcg2txt and parse Info lines, returning {cycle: state_dict}."""
    states = {}
    proc = subprocess.run(
        [str(RCG2TXT), str(rcg_path)],
        capture_output=True, text=True, check=False
    )
    # Patterns
    info_re = re.compile(r"\(Info \(state (\d+) (\w+) \d+ \d+\) \(ball ([-\d.]+) ([-\d.]+)")
    player_re = re.compile(r"\(player (l|r) (\d+) (g)?\s?\(position ([-\d.]+) ([-\d.]+)")
    for line in proc.stdout.splitlines():
        m = info_re.match(line)
        if not m:
            continue
        cycle = int(m.group(1))
        if cycle not in target_cycles:
            continue
        play_mode = m.group(2)
        ball_x, ball_y = float(m.group(3)), float(m.group(4))
        players = {}  # (side, unum) -> (x, y, is_goalie)
        for pm in player_re.finditer(line):
            side, unum, is_g, x, y = pm.group(1), int(pm.group(2)), bool(pm.group(3)), float(pm.group(4)), float(pm.group(5))
            players[(side, unum)] = (x, y, is_g)
        states[cycle] = {
            "play_mode": play_mode,
            "ball": (ball_x, ball_y),
            "players": players,
        }
    return states


def find_rev_matches() -> list[tuple[pathlib.Path, str, str]]:
    """Return list of (match_dir, rev_side, opp_label) for all matches REV played in."""
    matches = []
    for exp_dir in sorted(EXP.glob("tourney_*")):
        if not exp_dir.is_dir():
            continue
        meta = json.loads((exp_dir / "experiment.json").read_text())
        yc = meta["yaml_content"]
        home = yc["home_team"]
        away = yc["away_team"]
        if "REV" not in (home, away):
            continue
        if home == "REV": rev_side, opp = "l", away
        elif away == "REV": rev_side, opp = "r", home
        else: continue
        for md in sorted((exp_dir / "matches").glob("match_*")):
            matches.append((md, rev_side, opp))
    return matches


def zone(x: float, y: float) -> str:
    """Bin pitch position into a 3x3 grid (REV-attack-+x perspective)."""
    # x: -52.5 to +52.5; y: -34 to +34
    col = "L" if y < -11 else ("R" if y > 11 else "C")
    if x < -17.5: row = "DEF"
    elif x > 17.5: row = "ATT"
    else: row = "MID"
    return f"{row}-{col}"


def analyze():
    if not RCG2TXT.exists():
        print(f"ERROR: rcg2txt not found at {RCG2TXT}", file=sys.stderr)
        sys.exit(1)

    matches = find_rev_matches()
    print(f"Found {len(matches)} REV matches\n")

    # Aggregates
    total_rev_score = 0
    total_opp_score = 0
    conceded_zones = Counter()
    scored_zones = Counter()
    conceded_phases = Counter()  # early/mid/late
    scored_phases = Counter()
    conceded_play_modes = Counter()  # what mode was active right before goal
    scored_play_modes = Counter()
    setpiece_won_lost = Counter()  # by mode
    per_match_summary = []
    score_situation_at_goal = []  # (cycle, rev_score, opp_score, ball_pos)
    conceded_preamble_modes = []  # list of (cycle, sequence of last 5 set-piece events)
    half_1_conceded = 0
    half_2_conceded = 0
    early_conceded = 0  # within 200 cycles of a kickoff (after goal or restart)

    for md, rev_side, opp in matches:
        metrics = json.loads((md / "metrics.json").read_text())
        h, a = metrics["home_score"], metrics["away_score"]
        rev_score = h if rev_side == "l" else a
        opp_score = a if rev_side == "l" else h
        total_rev_score += rev_score
        total_opp_score += opp_score

        # Parse referee events
        rcl_files = list(md.glob("*.rcl"))
        if not rcl_files: continue
        events = parse_rcl(rcl_files[0])
        # Identify goal cycles for ball-pos lookup
        opp_side = "r" if rev_side == "l" else "l"
        goal_cycles_rev = []
        goal_cycles_opp = []
        last_kickoff = 0
        seq_so_far = []
        for cyc, ev in events:
            seq_so_far.append((cyc, ev))
            if re.match(r"^goal_[lr]_\d+$", ev):
                # goal_l_N or goal_r_N (actual goal, not goal_kick_*)
                scorer = "l" if ev.startswith("goal_l") else "r"
                if scorer == rev_side: goal_cycles_rev.append(cyc)
                else:
                    goal_cycles_opp.append(cyc)
                    # Record context
                    # Halves: first half 0-3000, second 3000-6000
                    if cyc < 3000: half_1_conceded += 1
                    else: half_2_conceded += 1
                    if cyc - last_kickoff < 200:
                        early_conceded += 1
                    # last 5 events before this goal
                    pre = [e for c, e in seq_so_far[-6:-1]]
                    conceded_preamble_modes.append((cyc, pre))
            elif ev.startswith("kick_off"):
                last_kickoff = cyc
            elif ev.startswith("free_kick_") or ev.startswith("kick_in_") or ev.startswith("indirect_free_") or ev.startswith("goal_kick_"):
                sp_side = ev.split("_")[-1]
                setpiece_won_lost[("won" if sp_side == rev_side else "lost", ev.rsplit("_", 1)[0])] += 1

        # Parse ball positions at goals
        target = set(goal_cycles_rev + goal_cycles_opp)
        # also fetch 20 cycles before each goal for context
        for g in goal_cycles_rev + goal_cycles_opp:
            for d in range(0, 21, 5):
                target.add(max(0, g - d))
        rcg_files = list(md.glob("*.rcg"))
        if rcg_files:
            states = parse_rcg_at_cycles(rcg_files[0], target)
        else:
            states = {}

        for g in goal_cycles_opp:
            # Find the ball position 5 cycles before the goal (when shot was likely taken)
            for d in [5, 10, 0, 15, 20]:
                if g - d in states:
                    st = states[g - d]
                    bx, by = st["ball"]
                    # convert to REV-attack-+x perspective
                    if rev_side == "r":
                        bx, by = -bx, -by
                    conceded_zones[zone(bx, by)] += 1
                    # Collect REV's defender positions (also flipped if rev=r)
                    rev_defs = []
                    for (s, u), (x, y, isg) in st["players"].items():
                        if s == rev_side and u in (1, 2, 3, 4, 5, 6, 7, 8):  # GK + 2-8 (defenders + CDMs)
                            xx, yy = (x, y) if rev_side == "l" else (-x, -y)
                            rev_defs.append((u, xx, yy))
                    score_situation_at_goal.append((md.name, g, rev_score, opp_score, (bx, by), "conceded", rev_defs))
                    break
            # Phase
            phase = "early" if g < 2000 else ("mid" if g < 4000 else "late")
            conceded_phases[phase] += 1
            # Play mode at goal
            if g in states:
                conceded_play_modes[states[g]["play_mode"]] += 1

        for g in goal_cycles_rev:
            for d in [5, 10, 0, 15, 20]:
                if g - d in states:
                    bx, by = states[g - d]["ball"]
                    if rev_side == "r":
                        bx, by = -bx, -by
                    scored_zones[zone(bx, by)] += 1
                    score_situation_at_goal.append((md.name, g, rev_score, opp_score, (bx, by), "scored"))
                    break
            phase = "early" if g < 2000 else ("mid" if g < 4000 else "late")
            scored_phases[phase] += 1
            if g in states:
                scored_play_modes[states[g]["play_mode"]] += 1

        per_match_summary.append({
            "match": str(md.relative_to(EXP)),
            "opp": opp,
            "rev_side": rev_side,
            "score": (rev_score, opp_score),
            "goals_rev": goal_cycles_rev,
            "goals_opp": goal_cycles_opp,
        })

    # Print report
    print("=" * 70)
    print(f"REV totals: scored {total_rev_score}, conceded {total_opp_score} over {len(matches)} matches")
    print(f"  mean scored: {total_rev_score/len(matches):.2f}")
    print(f"  mean conceded: {total_opp_score/len(matches):.2f}")
    print()
    print(f"Halves: half-1 conceded={half_1_conceded}, half-2 conceded={half_2_conceded}")
    print(f"Early-restart-conceded (within 200 cycles of any kickoff): {early_conceded}/{total_opp_score}")
    print()
    print("Conceded by phase (early=0-2000, mid=2000-4000, late=4000-6000):")
    for k in ["early", "mid", "late"]:
        print(f"  {k:5s}: {conceded_phases[k]}")
    print("Scored by phase:")
    for k in ["early", "mid", "late"]:
        print(f"  {k:5s}: {scored_phases[k]}")
    print()
    print("Conceded by pitch zone (REV-attack-+x):")
    for z in ["DEF-L", "DEF-C", "DEF-R", "MID-L", "MID-C", "MID-R", "ATT-L", "ATT-C", "ATT-R"]:
        print(f"  {z}: {conceded_zones[z]}")
    print()
    print("Conceded play_mode at goal:")
    for m, c in conceded_play_modes.most_common():
        print(f"  {m}: {c}")
    print("Scored play_mode at goal:")
    for m, c in scored_play_modes.most_common():
        print(f"  {m}: {c}")
    print()
    print("Set-piece counts (REV-perspective):")
    for (wl, mode), c in sorted(setpiece_won_lost.items()):
        print(f"  {wl:4s} {mode}: {c}")
    print()
    print("Per-match summary:")
    for ms in per_match_summary:
        marker = "+" if ms["score"][0] > ms["score"][1] else ("=" if ms["score"][0] == ms["score"][1] else "-")
        print(f"  {marker} {ms['match']}: vs {ms['opp']} (rev={ms['rev_side']}) {ms['score'][0]}-{ms['score'][1]}")
        if ms["goals_rev"]:
            print(f"      REV goals at cycles: {ms['goals_rev']}")
        if ms["goals_opp"]:
            print(f"      OPP goals at cycles: {ms['goals_opp']}")
    print()
    print("Conceded-goal preambles (last 5 referee events before each conceded goal):")
    for cyc, pre in conceded_preamble_modes:
        print(f"  cyc={cyc}: {pre}")
    print()
    print("Goal ball-position details:")
    for s in score_situation_at_goal:
        if len(s) == 7:
            match, gcyc, rs, os, (bx, by), side, defs = s
        else:
            match, gcyc, rs, os, (bx, by), side = s
            defs = None
        side_marker = "SCORE" if side == "scored" else "CONCEDE"
        print(f"  [{side_marker:7s}] {match}: cyc={gcyc} ball=({bx:+6.2f},{by:+6.2f}) zone={zone(bx, by)}")
        if defs:
            # Sort by unum
            defs.sort()
            posn = "  ".join(f"u{u}({x:+5.1f},{y:+5.1f})" for u, x, y in defs)
            print(f"    REV defenders: {posn}")


if __name__ == "__main__":
    analyze()
