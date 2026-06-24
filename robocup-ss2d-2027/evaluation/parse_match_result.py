#!/usr/bin/env python3
"""parse_match_result.py - extract a match result and merge runtime metadata.

The output schema (`schema_version: "1.3"`) augments the parsed score with
the runtime metadata recorded by `scripts/run_smoke_match.sh` and the
attestation written by `scripts/attest_runtime.py`. The merge order is:

    metrics.json = metadata.json (if present)  +  parsed score  +  file lists

Every metrics.json contains the same keys regardless of whether the match
completed. Unknown values are emitted as null (numbers), "unknown"
(strings), [] (lists), or {} (dicts); the reason is appended to
`parser_notes`.

    {
      "schema_version":             "1.3",
      "run_id":                     "...",
      "created_at_utc":             "...",
      "server_binary":              "...",
      "server_version":             "...",
      "applied_server_options":     [...],
      "declared_reality_assertion": "synthetic_or_stubbed" | "real_rcssserver",
      "observed_reality_status":    "real_rcssserver" | "synthetic_or_stubbed"
                                    | "unknown_or_unverified",
      "reality_evidence":           { ... },
      "reality_evidence_missing":   [...],
      "home_start_command":         "...",
      "away_start_command":         "...",
      "home_team":                  "...",
      "away_team":                  "...",
      "home_score":                 0,
      "away_score":                 0,
      "result":                     "home_win" | "away_win" | "draw" | "unknown",
      "rcg_files":                  [...],
      "rcl_files":                  [...],
      "parser_notes":               [...]
    }
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SCHEMA_VERSION = "1.3"

# Matches end-of-game lines from rcssserver-ish servers, e.g.
#   "Result: helios 2 - 1 helios"
#   "Final score helios_left 0 vs 0 helios_right"
SCORE_LINE = re.compile(
    r"(?:result|final\s*score)[^0-9A-Za-z_-]*"
    r"([A-Za-z0-9_-]+)\s+([0-9]+)\s*[-:vs]+\s*([0-9]+)\s+([A-Za-z0-9_-]+)",
    re.IGNORECASE,
)

# Default rcg filename emitted by rcssserver, e.g.
#   202606241530-helios_2-helios_1.rcg          (rcssserver-18 and earlier)
#   20260624153012-HELIOS_L_2-vs-HELIOS_R_1.rcg (rcssserver-19)
#   20260624153012-HELIOS_L_32-vs-null.rcg      (rcssserver-19 when one side fails to connect)
# The optional "-vs-" + optional "null" right side cover both releases.
RCG_FILENAME = re.compile(
    r"^[0-9]{8,14}-"
    r"([A-Za-z0-9_]+?)_([0-9]+)"
    r"-(?:vs-)?"
    r"(?:([A-Za-z0-9_]+?)_([0-9]+)|null)"
    r"\.rcg(?:\.gz)?$"
)

METADATA_KEYS = (
    "run_id",
    "created_at_utc",
    "server_binary",
    "server_version",
    "applied_server_options",
    "declared_reality_assertion",
    "observed_reality_status",
    "reality_evidence",
    "reality_evidence_missing",
    "home_start_command",
    "away_start_command",
)
LIST_KEYS = ("applied_server_options", "reality_evidence_missing")
DICT_KEYS = ("reality_evidence",)


def parse_score_from_text(text: str) -> dict | None:
    m = SCORE_LINE.search(text)
    if not m:
        return None
    home, hs, as_, away = m.groups()
    return {"home_team": home, "away_team": away,
            "home_score": int(hs), "away_score": int(as_)}


def parse_score_from_rcg_name(path: Path) -> dict | None:
    m = RCG_FILENAME.match(path.name)
    if not m:
        return None
    home, hs, away, as_ = m.groups()
    if away is None:
        # rcssserver-19 marks an unconnected side as "null". We retain
        # the home name and score and record the other side as
        # explicitly absent rather than guessing.
        return {"home_team": home, "away_team": "null",
                "home_score": int(hs), "away_score": None}
    return {"home_team": home, "away_team": away,
            "home_score": int(hs), "away_score": int(as_)}


def classify(home: int, away: int) -> str:
    if home > away:
        return "home_win"
    if home < away:
        return "away_win"
    return "draw"


def _default_for(key: str):
    if key in LIST_KEYS:
        return []
    if key in DICT_KEYS:
        return {}
    return "unknown"


def load_metadata(run_dir: Path, notes: list[str]) -> dict:
    """Load metadata.json if present; otherwise fill with placeholders."""
    metadata_path = run_dir / "metadata.json"
    defaults = {k: _default_for(k) for k in METADATA_KEYS}
    if not metadata_path.is_file():
        notes.append("metadata.json not found; runtime fields default to 'unknown'")
        return defaults
    try:
        raw = json.loads(metadata_path.read_text())
    except json.JSONDecodeError as e:
        notes.append(f"metadata.json present but unreadable ({e}); runtime fields default to 'unknown'")
        return defaults
    merged = dict(defaults)
    for k in METADATA_KEYS:
        if k in raw:
            merged[k] = raw[k]
    return merged


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="parse_match_result.py",
        description="Extract a match result and merge runtime metadata.",
    )
    p.add_argument("--run-dir", type=Path, required=True,
                   help="Directory containing server.out, metadata.json, rcg/rcl logs.")
    p.add_argument("--rcg", type=Path, default=None,
                   help="Explicit path to the .rcg game log (optional).")
    p.add_argument("--rcl", type=Path, default=None,
                   help="Explicit path to the .rcl text log (optional).")
    p.add_argument("--output", type=Path, required=True,
                   help="Where to write metrics.json.")
    p.add_argument("--notes", type=str, default="",
                   help="Extra note to record in metrics.json::parser_notes.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.run_dir.is_dir():
        print(f"run-dir does not exist: {args.run_dir}", file=sys.stderr)
        return 2

    parser_notes: list[str] = []
    if args.notes:
        parser_notes.append(args.notes)

    metadata_fields = load_metadata(args.run_dir, parser_notes)

    score: dict | None = None
    server_out = args.run_dir / "server.out"
    if server_out.is_file():
        score = parse_score_from_text(server_out.read_text(errors="replace"))
        if score is None:
            parser_notes.append("no score line found in server.out")
    else:
        parser_notes.append("server.out not found")

    # Locate the rcg/rcl files. Lists, not singletons -- a run dir is
    # allowed to contain >1 (e.g. server retry, partial logs).
    rcg_files = sorted(
        list(args.run_dir.glob("*.rcg")) + list(args.run_dir.glob("*.rcg.gz"))
    )
    rcl_files = sorted(args.run_dir.glob("*.rcl"))
    if args.rcg and args.rcg not in rcg_files:
        rcg_files.insert(0, args.rcg)
    if args.rcl and args.rcl not in rcl_files:
        rcl_files.insert(0, args.rcl)

    if score is None and rcg_files:
        score = parse_score_from_rcg_name(rcg_files[0])
        if score is None:
            parser_notes.append("could not parse score from rcg filename")

    if score and score.get("away_score") is None:
        # One side never connected. We have the home score but not a
        # comparable away score; classify cannot resolve the result.
        result = "unknown"
        parser_notes.append(
            f"away_team={score.get('away_team')!r}; treating result as unknown"
        )
    elif score:
        result = classify(score["home_score"], score["away_score"])
    else:
        result = "unknown"

    metrics = {
        "schema_version": SCHEMA_VERSION,
        **metadata_fields,
        "home_team":   (score or {}).get("home_team", "unknown"),
        "away_team":   (score or {}).get("away_team", "unknown"),
        "home_score":  (score or {}).get("home_score"),
        "away_score":  (score or {}).get("away_score"),
        "result":      result,
        "rcg_files":   [str(p) for p in rcg_files],
        "rcl_files":   [str(p) for p in rcl_files],
        "parser_notes": parser_notes,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(metrics, indent=2) + "\n")
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
