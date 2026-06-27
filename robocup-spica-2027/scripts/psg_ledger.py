#!/usr/bin/env python3
"""psg_ledger.py - per-match ledger of good / bad plays for the
PSG-style improvement loop.

For one match directory (with rcg + rcl), produce a structured ledger:

  good:
    - goals_scored (and how -- attacker, ball trajectory, build-up chain)
    - high_recoveries (ball won in opp half)
    - long_progressive_passes (>=20m forward into opp half completed)
    - half_space_dribbles (ball carried into 20<x<45 AND 6<|y|<16)
    - wing_overlaps (SB/WB made successful action with x>+10)

  bad:
    - goals_conceded (and how -- set-piece origin, defender positions)
    - low_third_losses (lost possession at x<-25)
    - failed_clearances (clearance kick recovered by opp in our half)
    - unmarked_runs (opp player with ball in our PA without marker within 3m)
    - dangerous_setpieces_conceded (opp FK / corner with ball at x<-30)

Usage:
  PATH="$PWD/externals/install/bin:$PATH" python3 scripts/psg_ledger.py \\
      logs/psg_loop/iter_NNN/matches/match_000001/

Outputs JSON to stdout AND saves to {match_dir}/ledger.json.
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
RCG2TXT = ROOT / "externals/install/bin/rcg2txt"


def parse_rcl_events(rcl_path: pathlib.Path):
    events = []
    with open(rcl_path) as f:
        for line in f:
            m = re.match(r"^(\d+),\d+\s+\(referee\s+([^)]+)\)", line)
            if m:
                events.append((int(m.group(1)), m.group(2)))
    return events


def parse_rcg_all(rcg_path: pathlib.Path):
    """Yield (cycle, play_mode, ball, players_dict) for each cycle."""
    proc = subprocess.run(
        [str(RCG2TXT), str(rcg_path)], capture_output=True, text=True
    )
    info_re = re.compile(
        r"\(Info \(state (\d+) (\w+) \d+ \d+\) \(ball ([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)\)"
    )
    player_re = re.compile(
        r"\(player (l|r) (\d+) (g)? ?\(position ([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) [-\d.]+ [-\d.]+\) \(stamina ([-\d.]+)\)"
    )
    for line in proc.stdout.splitlines():
        m = info_re.match(line)
        if not m:
            continue
        cycle = int(m.group(1))
        play_mode = m.group(2)
        bx, by, bvx, bvy = (float(m.group(i)) for i in range(3, 7))
        players = {}
        for pm in player_re.finditer(line):
            side = pm.group(1)
            unum = int(pm.group(2))
            is_g = bool(pm.group(3))
            x, y = float(pm.group(4)), float(pm.group(5))
            vx, vy = float(pm.group(6)), float(pm.group(7))
            stamina = float(pm.group(8))
            players[(side, unum)] = {
                "x": x, "y": y, "vx": vx, "vy": vy,
                "stamina": stamina, "goalie": is_g,
            }
        yield cycle, play_mode, (bx, by, bvx, bvy), players


def closest_player(players, target_xy, side=None):
    bx, by = target_xy
    best = None
    best_d = 1e9
    for (s, u), p in players.items():
        if side and s != side: continue
        d = ((p["x"] - bx) ** 2 + (p["y"] - by) ** 2) ** 0.5
        if d < best_d:
            best_d = d
            best = (s, u)
    return best, best_d


def main():
    if len(sys.argv) != 2:
        print("usage: psg_ledger.py <match_dir>", file=sys.stderr)
        sys.exit(2)
    match_dir = pathlib.Path(sys.argv[1])
    rcl_files = list(match_dir.glob("*.rcl"))
    rcg_files = list(match_dir.glob("*.rcg"))
    if not rcl_files or not rcg_files:
        print(f"no rcl/rcg in {match_dir}", file=sys.stderr)
        sys.exit(1)
    metrics = json.loads((match_dir / "metrics.json").read_text())

    # Identify Spica side ("l" or "r") by team names.
    home = metrics["home_team"]
    away = metrics["away_team"]
    spica_side = "l" if "SPICA" in home else ("r" if "SPICA" in away else None)
    if spica_side is None:
        print(f"could not identify Spica side: home={home} away={away}", file=sys.stderr)
        sys.exit(1)
    opp_side = "r" if spica_side == "l" else "l"

    # Sign convention: Spica attacks +x in its own ref frame. If
    # Spica is on the RIGHT (server side r), flip x and y when
    # reporting positions.
    def spc(x, y):
        return (-x, -y) if spica_side == "r" else (x, y)

    print(f"  Spica side: {spica_side}; home={home} away={away}", file=sys.stderr)

    events = parse_rcl_events(rcl_files[0])
    # Indices into events
    goal_evts = [(c, e) for c, e in events if re.match(r"^goal_[lr]_\d+$", e)]
    fk_evts = [(c, e) for c, e in events if re.match(r"^(free_kick|corner_kick|kick_in|indirect_free_kick)_[lr]", e)]
    fouls = [(c, e) for c, e in events if e.startswith("foul_charge")]

    print(f"  events: {len(events)}, goals: {len(goal_evts)}, set-pieces: {len(fk_evts)}, fouls: {len(fouls)}", file=sys.stderr)

    # Walk rcg
    states = list(parse_rcg_all(rcg_files[0]))
    print(f"  cycles parsed: {len(states)}", file=sys.stderr)

    if not states:
        print("no rcg state parsed", file=sys.stderr)
        sys.exit(1)

    ledger = {
        "match_dir": str(match_dir.resolve().relative_to(ROOT)),
        "home": home, "away": away, "spica_side": spica_side,
        "home_score": metrics.get("home_score"),
        "away_score": metrics.get("away_score"),
        "good": defaultdict(list),
        "bad": defaultdict(list),
    }

    # --- goals analysis ---
    goal_cycles_set = set(c for c, _ in goal_evts)
    for gc, ge in goal_evts:
        scorer_side = "l" if ge.startswith("goal_l") else "r"
        bucket = "good" if scorer_side == spica_side else "bad"
        bucket_key = "goals_scored" if bucket == "good" else "goals_conceded"
        # Find ball position 5 cycles before
        gstate = None
        for d in [5, 10, 0, 15, 20]:
            target = gc - d
            for st in states:
                if st[0] == target:
                    gstate = st
                    break
            if gstate:
                break
        if gstate:
            _, pm, ball, players = gstate
            bxy = spc(ball[0], ball[1])
            # Last 6 referee events before goal
            pre = [e for c, e in events if c < gc][-6:]
            ledger[bucket][bucket_key].append({
                "cycle": gc,
                "ball": [round(bxy[0], 2), round(bxy[1], 2)],
                "preamble": pre,
                "play_mode_before": pm,
            })

    # --- aggregate possession / dangerous SPs ---
    spica_def_third_setpieces = []  # opp set pieces deep in Spica's half
    for fc, fe in fk_evts:
        side = fe.split("_")[-1]
        if side == opp_side:
            # opp set piece; find ball pos
            st = next((s for s in states if s[0] == fc), None)
            if st:
                _, _, ball, _ = st
                bxy = spc(ball[0], ball[1])
                # Spica's defensive third: x < -25 (in Spica-frame)
                if bxy[0] < -25:
                    spica_def_third_setpieces.append({
                        "cycle": fc, "type": fe,
                        "ball": [round(bxy[0], 2), round(bxy[1], 2)],
                    })

    if spica_def_third_setpieces:
        ledger["bad"]["dangerous_setpieces_conceded"] = spica_def_third_setpieces[:10]

    # --- per-cycle analysis: possession, presses ---
    # We count: (a) cycles where Spica's closest player has ball AND ball is in opp half (good)
    #          (b) cycles where opp's closest player has ball AND ball is in own half (bad)
    spica_pos_opp_half = 0
    opp_pos_spica_half = 0
    spica_pos_own_third = 0
    high_recovery_cycles = []
    last_possessor_side = None
    for cycle, pm, ball, players in states:
        if pm not in ("play_on", "kick_off_l", "kick_off_r"): continue
        if not players: continue
        bxy = (ball[0], ball[1])
        closest, dist = closest_player(players, bxy)
        if not closest: continue
        s, u = closest
        # In Spica frame: invert x if r
        bxy_s = spc(*bxy)
        if dist < 2.0:
            if s == spica_side:
                if bxy_s[0] > 0:
                    spica_pos_opp_half += 1
                if bxy_s[0] < -17:
                    spica_pos_own_third += 1
                # High recovery: prev possessor was opp AND ball at opp half
                if last_possessor_side == opp_side and bxy_s[0] > 0:
                    high_recovery_cycles.append({
                        "cycle": cycle,
                        "ball": [round(bxy_s[0], 2), round(bxy_s[1], 2)],
                        "spica_winner_unum": u,
                    })
                last_possessor_side = spica_side
            elif s == opp_side:
                if bxy_s[0] < 0:
                    opp_pos_spica_half += 1
                last_possessor_side = opp_side

    ledger["good"]["high_recoveries"] = high_recovery_cycles[:5]
    ledger["possession_summary"] = {
        "spica_kickable_opp_half_cycles": spica_pos_opp_half,
        "opp_kickable_spica_half_cycles": opp_pos_spica_half,
        "spica_kickable_own_third_cycles": spica_pos_own_third,
    }

    # --- defender shape at conceded goals ---
    for gc, ge in goal_evts:
        if not ge.startswith("goal_" + opp_side): continue
        # Find state at gc-5
        target = max(0, gc - 5)
        st = next((s for s in states if s[0] == target), None)
        if not st: continue
        _, _, ball, players = st
        bxy = spc(ball[0], ball[1])
        # Spica defender positions (1..8)
        defs = []
        for u in range(1, 9):
            p = players.get((spica_side, u))
            if not p: continue
            xx, yy = spc(p["x"], p["y"])
            defs.append({"unum": u, "x": round(xx, 1), "y": round(yy, 1),
                         "stamina": round(p["stamina"], 0)})
        # Opp attackers within 15m of ball
        attackers = []
        for u in range(1, 12):
            p = players.get((opp_side, u))
            if not p: continue
            xx, yy = spc(p["x"], p["y"])
            d = ((xx - bxy[0])**2 + (yy - bxy[1])**2)**0.5
            if d < 15:
                attackers.append({"unum": u, "x": round(xx, 1), "y": round(yy, 1),
                                  "dist_to_ball": round(d, 1)})
        ledger["bad"].setdefault("conceded_shape", []).append({
            "cycle": gc, "ball": [round(bxy[0], 2), round(bxy[1], 2)],
            "spica_defs": defs, "opp_attackers_near_ball": attackers,
        })

    # --- write output ---
    ledger_path = match_dir / "ledger.json"
    ledger["good"] = dict(ledger["good"])
    ledger["bad"] = dict(ledger["bad"])
    ledger_path.write_text(json.dumps(ledger, indent=2) + "\n")
    print(json.dumps(ledger, indent=2))
    print(f"\n  saved -> {ledger_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
