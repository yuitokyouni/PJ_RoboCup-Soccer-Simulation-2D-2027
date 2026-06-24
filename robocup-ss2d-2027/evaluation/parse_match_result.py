#!/usr/bin/env python3
"""parse_match_result.py - extract a coarse match result from rcssserver outputs.

Reads the server stdout file and/or the .rcg filename and writes a minimal
machine-readable metrics.json:

    {
      "home_team":      "...",
      "away_team":      "...",
      "home_score":     0,
      "away_score":     0,
      "result":         "home_win" | "away_win" | "draw" | "unknown",
      "rcg_path":       "...",
      "rcl_path":       "...",
      "server_version": "unknown",
      "notes":          "..."
    }

The parser is deliberately tolerant: if a field cannot be determined it is
emitted as null (or "unknown") and the reason is appended to "notes" rather
than raising. This keeps the harness output well-formed even when the server
crashed early or named files unexpectedly.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Matches lines emitted by rcssserver-ish servers at end of game, e.g.
#   "Result: helios 2 - 1 helios"
#   "Final score helios_left 0 vs 0 helios_right"
SCORE_LINE = re.compile(
    r"(?:result|final\s*score)[^0-9A-Za-z_-]*"
    r"([A-Za-z0-9_-]+)\s+([0-9]+)\s*[-:vs]+\s*([0-9]+)\s+([A-Za-z0-9_-]+)",
    re.IGNORECASE,
)

# Default rcg filename format from rcssserver, e.g.
#   202606241530-helios_2-helios_1.rcg
#   202606241530-helios_0-helios_0.rcg.gz
RCG_FILENAME = re.compile(
    r"^[0-9]{8,14}-([A-Za-z0-9_]+?)_([0-9]+)-([A-Za-z0-9_]+?)_([0-9]+)\.rcg(?:\.gz)?$"
)


def parse_score_from_text(text: str) -> dict | None:
    m = SCORE_LINE.search(text)
    if not m:
        return None
    home, hs, as_, away = m.groups()
    return {
        "home_team": home,
        "away_team": away,
        "home_score": int(hs),
        "away_score": int(as_),
    }


def parse_score_from_rcg_name(path: Path) -> dict | None:
    m = RCG_FILENAME.match(path.name)
    if not m:
        return None
    home, hs, away, as_ = m.groups()
    return {
        "home_team": home,
        "away_team": away,
        "home_score": int(hs),
        "away_score": int(as_),
    }


def classify(home: int, away: int) -> str:
    if home > away:
        return "home_win"
    if home < away:
        return "away_win"
    return "draw"


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="parse_match_result.py",
        description="Extract a coarse match result from rcssserver outputs.",
    )
    p.add_argument("--run-dir", type=Path, required=True,
                   help="Directory containing server.out and the rcg/rcl logs.")
    p.add_argument("--rcg", type=Path, default=None,
                   help="Explicit path to the .rcg game log (optional).")
    p.add_argument("--rcl", type=Path, default=None,
                   help="Explicit path to the .rcl text log (optional).")
    p.add_argument("--output", type=Path, required=True,
                   help="Where to write metrics.json.")
    p.add_argument("--notes", type=str, default="",
                   help="Extra free-form notes recorded in metrics.json.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.run_dir.is_dir():
        print(f"run-dir does not exist: {args.run_dir}", file=sys.stderr)
        return 2

    parsed: dict | None = None
    why: list[str] = []

    server_out = args.run_dir / "server.out"
    if server_out.is_file():
        parsed = parse_score_from_text(server_out.read_text(errors="replace"))
        if parsed is None:
            why.append("no score line found in server.out")
    else:
        why.append("server.out not found")

    rcg = args.rcg
    if rcg is None:
        candidates = sorted(args.run_dir.glob("*.rcg")) + sorted(args.run_dir.glob("*.rcg.gz"))
        rcg = candidates[0] if candidates else None
    if parsed is None and rcg is not None:
        parsed = parse_score_from_rcg_name(rcg)
        if parsed is None:
            why.append("could not parse score from rcg filename")

    rcl = args.rcl
    if rcl is None:
        candidates = sorted(args.run_dir.glob("*.rcl"))
        rcl = candidates[0] if candidates else None

    if parsed:
        result = classify(parsed["home_score"], parsed["away_score"])
    else:
        result = "unknown"

    metrics = {
        "home_team":      (parsed or {}).get("home_team", "unknown"),
        "away_team":      (parsed or {}).get("away_team", "unknown"),
        "home_score":     (parsed or {}).get("home_score"),
        "away_score":     (parsed or {}).get("away_score"),
        "result":         result,
        "rcg_path":       str(rcg) if rcg else None,
        "rcl_path":       str(rcl) if rcl else None,
        "server_version": "unknown",
        "notes":          "; ".join(s for s in ([args.notes] + why) if s),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(metrics, indent=2) + "\n")
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
