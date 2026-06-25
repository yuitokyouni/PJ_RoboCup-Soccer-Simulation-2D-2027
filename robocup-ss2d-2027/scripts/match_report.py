#!/usr/bin/env python3
"""match_report.py - per-match tactical report from a finished match dir.

Inputs
------
A match run directory containing:
  - <stamp>-<HOME>_<hs>-vs-<AWAY>_<as>.rcl   (text command log)
  - <stamp>-<HOME>_<hs>-vs-<AWAY>_<as>.rcg   (binary game log, unused
                                             in v1; informs v2)
  - metrics.json                              (score + result)
  - metadata.json                             (declared options)
  - server.out                                (final score line)

Output
------
  report.md in the same directory.

Sections (v1):
  1. Score line + result (draw / win)
  2. Goals: per-goal cycle + scoring side + the 10 preceding kicks
  3. Cards / fouls per team
  4. Set-piece counts: kick_in, goal_kick, corner_kick, free_kick,
     offside (split by side)
  5. Activity proxy stats:
       - kick count per team (possession proxy; upper bound)
       - dash count per team (stamina expenditure proxy)
       - turn  count per team
  6. Play-mode time distribution (% of cycles spent in play_on vs
     various set-piece modes).

What is NOT in v1 (because it requires .rcg position parsing):
  - ball-loss heat-map by zone
  - actual stamina at full time (from .rcg player_type)
  - possession share by ball position
  - per-pass success / completion rate

The script is intentionally pure-stdlib: re + collections + pathlib.

Usage
-----
  python3 scripts/match_report.py <match_dir>
  python3 scripts/match_report.py <match_dir> --out alt-name.md
"""
from __future__ import annotations
import argparse
import collections
import json
import pathlib
import re
import sys


RCL_LINE = re.compile(
    r"^(?P<cycle>\d+),(?P<stop>\d+)\t(?P<rest>.*)$"
)
REF_EVENT = re.compile(r"^\(referee\s+(?P<ev>\S+)\)\s*$")
RECV_CMD = re.compile(
    r"^Recv\s+(?P<team>[A-Za-z0-9_+\-]+)_(?P<unum>\d+):\s+(?P<body>.*)$"
)
CMD_TOKEN = re.compile(r"\((kick|dash|turn|turn_neck|catch|tackle)\b")


def parse_match_filename(rcl_path: pathlib.Path):
    """20260625060005-CYRUS_VANILLA_1-vs-CYRUS_IMPROVED_0.rcl
       -> ('CYRUS_VANILLA', 1, 'CYRUS_IMPROVED', 0)"""
    stem = rcl_path.stem
    m = re.match(
        r"\d+-(?P<h>[^-]+(?:_[A-Z]+)*)_(?P<hs>\d+)-vs-(?P<a>[^-]+(?:_[A-Z]+)*)_(?P<as>\d+)$",
        stem,
    )
    if not m:
        return None
    return m.group("h"), int(m.group("hs")), m.group("a"), int(m.group("as"))


def scan_rcl(rcl_path: pathlib.Path, home: str, away: str):
    """Single pass over the .rcl. Counts what we need.

    Returns a dict with keys:
      goals          : [(cycle, side, kick_history)]
      kicks_by_team  : {team: int}
      dashes_by_team : {team: int}
      turns_by_team  : {team: int}
      cards_by_side  : Counter({'l': n, 'r': m})
      fouls_by_side  : Counter
      set_pieces     : Counter({event: n})
      playmode_durations : Counter({mode: n_cycles})
      total_cycles   : int
      recent_kicks   : last 10 kicks before each goal,
                       as (cycle, team, unum, body)
    """
    goals = []
    kicks_by_team = collections.Counter()
    dashes_by_team = collections.Counter()
    turns_by_team = collections.Counter()
    cards_by_side = collections.Counter()
    fouls_by_side = collections.Counter()
    set_pieces = collections.Counter()
    playmode_dur = collections.Counter()
    recent_kicks_buf = collections.deque(maxlen=10)
    total_cycles = 0
    cur_mode = "before_kick_off"
    last_mode_start = 0

    home_prefix = home + "_"
    away_prefix = away + "_"

    with rcl_path.open() as f:
        for raw in f:
            m = RCL_LINE.match(raw)
            if not m:
                continue
            cycle = int(m["cycle"])
            total_cycles = max(total_cycles, cycle)
            body = m["rest"]

            ref = REF_EVENT.match(body)
            if ref:
                ev = ref["ev"]
                if ev.startswith("goal_l_"):
                    goals.append((cycle, "l", list(recent_kicks_buf)))
                elif ev.startswith("goal_r_"):
                    goals.append((cycle, "r", list(recent_kicks_buf)))
                elif ev.startswith("yellow_card_"):
                    side = ev.split("_")[2]
                    cards_by_side[side] += 1
                elif ev.startswith("foul_charge_") or ev.startswith("foul_push_"):
                    side = ev.split("_")[2]
                    fouls_by_side[side] += 1
                elif ev in ("kick_in_l", "kick_in_r",
                            "corner_kick_l", "corner_kick_r",
                            "goal_kick_l", "goal_kick_r",
                            "free_kick_l", "free_kick_r",
                            "offside_l", "offside_r",
                            "back_pass_l", "back_pass_r"):
                    set_pieces[ev] += 1

                # play_mode duration accounting
                if ev == "play_on" or ev.startswith("kick_off_"):
                    playmode_dur[cur_mode] += cycle - last_mode_start
                    cur_mode = "play_on" if ev == "play_on" else "kick_off"
                    last_mode_start = cycle
                elif ev in ("kick_in_l", "kick_in_r",
                            "corner_kick_l", "corner_kick_r",
                            "goal_kick_l", "goal_kick_r",
                            "free_kick_l", "free_kick_r",
                            "before_kick_off"):
                    playmode_dur[cur_mode] += cycle - last_mode_start
                    cur_mode = ev
                    last_mode_start = cycle
                continue

            recv = RECV_CMD.match(body)
            if not recv:
                continue
            team_tok = recv["team"]
            unum = int(recv["unum"])
            cmd_body = recv["body"]

            # Figure out which side. team_tok like "CYRUS_VANILLA"
            # without unum suffix.
            team = team_tok
            # Normalise: home/away match by team name.
            if team == home:
                bucket = "home"
            elif team == away:
                bucket = "away"
            else:
                # Some rcssserver versions add a trailing digit to
                # disambiguate identical names; tolerate.
                if team.startswith(home):
                    bucket = "home"
                elif team.startswith(away):
                    bucket = "away"
                else:
                    continue

            for tok in CMD_TOKEN.finditer(cmd_body):
                kind = tok.group(1)
                if kind == "kick":
                    kicks_by_team[bucket] += 1
                    recent_kicks_buf.append((cycle, bucket, unum, cmd_body[:80]))
                elif kind == "dash":
                    dashes_by_team[bucket] += 1
                elif kind in ("turn", "turn_neck"):
                    turns_by_team[bucket] += 1

    # Final mode duration (game ended in cur_mode).
    if total_cycles > last_mode_start:
        playmode_dur[cur_mode] += total_cycles - last_mode_start

    return {
        "goals": goals,
        "kicks_by_team": dict(kicks_by_team),
        "dashes_by_team": dict(dashes_by_team),
        "turns_by_team": dict(turns_by_team),
        "cards_by_side": dict(cards_by_side),
        "fouls_by_side": dict(fouls_by_side),
        "set_pieces": dict(set_pieces),
        "playmode_durations": dict(playmode_dur),
        "total_cycles": total_cycles,
    }


def fmt_int(n):
    return f"{n:,}"


def render(stats, home, hs, away, as_):
    L = []
    A = L.append

    A(f"# Match report: {home} {hs} - {as_} {away}")
    A("")

    # 1. Result
    if hs > as_:
        result = f"{home} win ({hs}-{as_})"
    elif hs < as_:
        result = f"{away} win ({hs}-{as_})"
    else:
        result = f"draw ({hs}-{as_})"
    A(f"**Result**: {result}")
    A("")
    A(f"**Total cycles**: {fmt_int(stats['total_cycles'])} "
      f"(~{stats['total_cycles']/600:.1f} min sim time)")
    A("")

    # 2. Goals
    A("## Goals")
    if not stats["goals"]:
        A("- (no normal-time goals)")
    else:
        for i, (cycle, side, recent) in enumerate(stats["goals"], 1):
            side_label = home if side == "l" else away
            mins = cycle / 600 * 6  # rough: 6000 cycle = full match, ~6 sim-min
            A(f"### Goal {i} — {side_label} at cycle {cycle} (~{mins:.1f} min)")
            if recent:
                A("Preceding 10 ball touches:")
                for c, bucket, unum, body in recent[-10:]:
                    bucket_label = home if bucket == "home" else away
                    short = re.sub(r"\s+", " ", body)[:60]
                    A(f"  - cycle {c}: {bucket_label}#{unum}  `{short}…`")
            A("")
    A("")

    # 3. Activity proxy
    A("## Activity (possession & stamina proxy)")
    A("")
    A("| metric | home (" + home + ") | away (" + away + ") |")
    A("|---|---|---|")
    for label, key in [("kicks", "kicks_by_team"),
                       ("dashes", "dashes_by_team"),
                       ("turns", "turns_by_team")]:
        hv = stats[key].get("home", 0)
        av = stats[key].get("away", 0)
        A(f"| {label} | {fmt_int(hv)} | {fmt_int(av)} |")
    tot_kicks = (stats["kicks_by_team"].get("home", 0)
                 + stats["kicks_by_team"].get("away", 0))
    if tot_kicks > 0:
        hp = stats["kicks_by_team"].get("home", 0) / tot_kicks * 100
        ap = stats["kicks_by_team"].get("away", 0) / tot_kicks * 100
        A(f"| kick share | {hp:.0f}% | {ap:.0f}% |")
    A("")

    # 4. Set pieces
    A("## Set pieces")
    sp = stats["set_pieces"]
    if not sp:
        A("- (none)")
    else:
        # group by event family.
        families = collections.defaultdict(lambda: collections.Counter())
        for ev, n in sp.items():
            # ev = "kick_in_l" -> family "kick_in", side "l"
            parts = ev.rsplit("_", 1)
            family, side = parts[0], parts[1]
            families[family][side] += n
        A("| event | home side (l) | away side (r) |")
        A("|---|---|---|")
        for family in sorted(families):
            l = families[family].get("l", 0)
            r = families[family].get("r", 0)
            A(f"| {family} | {l} | {r} |")
    A("")

    # 5. Cards & fouls
    A("## Discipline")
    fouls = stats["fouls_by_side"]
    cards = stats["cards_by_side"]
    A(f"- **Fouls**: home (l) {fouls.get('l', 0)} | away (r) {fouls.get('r', 0)}")
    A(f"- **Yellow cards**: home (l) {cards.get('l', 0)} | away (r) {cards.get('r', 0)}")
    A("")

    # 6. Play-mode share
    A("## Play-mode time distribution")
    pm = stats["playmode_durations"]
    tot = sum(pm.values()) or 1
    A("| mode | cycles | % |")
    A("|---|---|---|")
    for mode, n in sorted(pm.items(), key=lambda kv: -kv[1]):
        A(f"| {mode} | {fmt_int(n)} | {n/tot*100:.1f}% |")
    A("")

    A("---")
    A("Generated by `scripts/match_report.py` from the .rcl text log.")
    A("Position-based stats (ball-loss zones, stamina, possession-by-region)")
    A("require .rcg parsing and are not in v1.")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("match_dir", type=pathlib.Path)
    ap.add_argument("--out", default=None,
                    help="Output filename (default: report.md in match_dir)")
    args = ap.parse_args()

    if not args.match_dir.is_dir():
        sys.exit(f"not a directory: {args.match_dir}")

    rcls = list(args.match_dir.glob("*.rcl"))
    if not rcls:
        sys.exit(f"no .rcl in {args.match_dir}")
    rcl_path = rcls[0]

    parsed_name = parse_match_filename(rcl_path)
    if not parsed_name:
        sys.exit(f"could not parse team names from filename: {rcl_path.name}")
    home, hs, away, as_ = parsed_name

    stats = scan_rcl(rcl_path, home, away)
    out = render(stats, home, hs, away, as_)
    out_path = args.match_dir / (args.out or "report.md")
    out_path.write_text(out)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
