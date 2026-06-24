#!/usr/bin/env python3
"""aggregate_results.py - aggregate per-match metrics into summary files.

Walks `<experiment_dir>/matches/match_*/`, reads `metadata.json` for the
status and `metrics.json` for the score, and writes:

    <experiment_dir>/summary.json   structured aggregate (machine-readable)
    <experiment_dir>/summary.csv    per-match rows (spreadsheet-friendly)

See docs/EVALUATION_PROTOCOL.md for what counts as "completed", what
SMOKE_ONLY means, and which fields you may use to make claims.

The aggregator never crashes on missing or partial data. Missing
`metrics.json` is recorded as `unknown_results` and contributes to
`match_status_counts` via the matching `metadata.json::match_status`
(falling back to `unknown_failure` when even that is missing).
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path

SCHEMA_VERSION = "0.1.0"
MIN_COMPLETED_FOR_CLAIMS = 30

KNOWN_STATUSES = (
    "match_completed",
    "timeout",
    "dependency_missing",
    "server_failed_to_start",
    "teams_failed_to_start",
    "unknown_failure",
)


def _read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except json.JSONDecodeError:
        return None


def _mean(xs: list[float]) -> float | None:
    return sum(xs) / len(xs) if xs else None


def _sample_std(xs: list[float]) -> float | None:
    if len(xs) < 2:
        return None
    m = sum(xs) / len(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def aggregate(experiment_dir: Path) -> tuple[dict, list[dict]]:
    """Return (summary_dict, per_match_rows)."""
    notes: list[str] = []
    matches_dir = experiment_dir / "matches"
    if not matches_dir.is_dir():
        notes.append(f"no matches/ subdir under {experiment_dir}")
        match_dirs: list[Path] = []
    else:
        match_dirs = sorted(p for p in matches_dir.iterdir() if p.is_dir())

    status_counts = {s: 0 for s in KNOWN_STATUSES}
    home_wins = away_wins = draws = unknown_results = 0
    home_scores: list[int] = []
    away_scores: list[int] = []
    goal_diffs: list[int] = []
    rows: list[dict] = []

    for md in match_dirs:
        match_id = md.name
        metadata = _read_json(md / "metadata.json") or {}
        metrics = _read_json(md / "metrics.json")

        status = metadata.get("match_status") or "unknown_failure"
        if status not in status_counts:
            notes.append(f"{match_id}: unrecognized match_status '{status}', folded into unknown_failure")
            status_counts["unknown_failure"] += 1
        else:
            status_counts[status] += 1

        if metrics is None:
            unknown_results += 1
            notes.append(f"{match_id}: no metrics.json")
            rows.append({
                "match_id": match_id,
                "match_status": status,
                "home_team": metadata.get("home_team", "unknown") if False else "unknown",
                "away_team": "unknown",
                "home_score": "",
                "away_score": "",
                "result": "unknown",
                "goal_diff": "",
            })
            continue

        result = metrics.get("result", "unknown")
        if result == "home_win":
            home_wins += 1
        elif result == "away_win":
            away_wins += 1
        elif result == "draw":
            draws += 1
        else:
            unknown_results += 1

        hs = metrics.get("home_score")
        as_ = metrics.get("away_score")
        gd = ""
        if isinstance(hs, int) and isinstance(as_, int):
            home_scores.append(hs)
            away_scores.append(as_)
            goal_diffs.append(hs - as_)
            gd = hs - as_
        else:
            notes.append(f"{match_id}: score missing or non-integer (home={hs!r} away={as_!r})")

        rows.append({
            "match_id": match_id,
            "match_status": status,
            "home_team": metrics.get("home_team", "unknown"),
            "away_team": metrics.get("away_team", "unknown"),
            "home_score": hs if hs is not None else "",
            "away_score": as_ if as_ is not None else "",
            "result": result,
            "goal_diff": gd,
        })

    total_matches = len(match_dirs)
    completed_matches = status_counts["match_completed"]
    failed_matches = total_matches - completed_matches

    mean_gd = _mean(goal_diffs)
    std_gd = _sample_std(goal_diffs)
    n = len(goal_diffs)
    if std_gd is not None and n >= 1:
        se_gd = std_gd / math.sqrt(n)
        ci_low = mean_gd - 1.96 * se_gd
        ci_high = mean_gd + 1.96 * se_gd
    else:
        se_gd = ci_low = ci_high = None

    sample_regime = (
        "SMOKE_ONLY" if completed_matches < MIN_COMPLETED_FOR_CLAIMS else "RESEARCH_GRADE"
    )

    summary = {
        "schema_version":          SCHEMA_VERSION,
        "experiment_dir":          str(experiment_dir),
        "total_matches":           total_matches,
        "completed_matches":       completed_matches,
        "failed_matches":          failed_matches,
        "sample_regime":           sample_regime,
        "min_completed_for_claims": MIN_COMPLETED_FOR_CLAIMS,
        "match_status_counts":     status_counts,
        "home_wins":               home_wins,
        "away_wins":               away_wins,
        "draws":                   draws,
        "unknown_results":         unknown_results,
        "mean_home_score":         _mean(home_scores),
        "mean_away_score":         _mean(away_scores),
        "mean_goal_diff":          mean_gd,
        "std_goal_diff":           std_gd,
        "se_goal_diff":            se_gd,
        "ci95_goal_diff_low":      ci_low,
        "ci95_goal_diff_high":     ci_high,
        "notes":                   notes,
    }
    return summary, rows


def write_summary_csv(rows: list[dict], path: Path) -> None:
    columns = ["match_id", "match_status", "home_team", "away_team",
               "home_score", "away_score", "result", "goal_diff"]
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=columns)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="aggregate_results.py",
        description="Aggregate per-match metrics into summary.json + summary.csv.",
    )
    p.add_argument("--experiment-dir", type=Path, required=True,
                   help="Experiment directory containing matches/match_*/.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.experiment_dir.is_dir():
        print(f"experiment-dir does not exist: {args.experiment_dir}", file=sys.stderr)
        return 2

    summary, rows = aggregate(args.experiment_dir)

    summary_json = args.experiment_dir / "summary.json"
    summary_csv = args.experiment_dir / "summary.csv"
    summary_json.write_text(json.dumps(summary, indent=2) + "\n")
    write_summary_csv(rows, summary_csv)

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
