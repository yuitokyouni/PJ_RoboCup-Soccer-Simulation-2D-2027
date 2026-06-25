#!/usr/bin/env python3
"""combine_balanced_legs.py - aggregate two balanced-eval legs.

Phase 8 / handoff 2026-06-25 introduced the balanced-eval methodology:
because cross-binary cyrus-vs-cyrus has a ~40pp LEFT-side advantage,
single-leg n=20 comparisons are confounded by side assignment. The fix
is to run two n=15 batches with the variant team on opposite sides and
combine.

This script reads the two batch summary.json files and prints the
side-corrected per-team statistics.

Convention used by the experiments shipped with this repo:
  leg1 = balanced_vanilla_left   (home=CYRUS_VANILLA, away=SPICA325)
  leg2 = balanced_spica325_left  (home=SPICA325, away=CYRUS_VANILLA)

Pass them in that order (or pass them in any order with --variant=NAME
to declare which one is the variant team name).

Usage:
  combine_balanced_legs.py LEG1_SUMMARY LEG2_SUMMARY [--variant NAME]
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


def load(p: Path) -> dict:
    return json.loads(p.read_text())


def variant_per_match_diffs(summary: dict, variant_name: str) -> list[int]:
    """Per-match goal differential from the variant team's POV.

    Iterates the summary rows. summary.json itself doesn't contain rows
    -- they live in summary.csv. We pick them up by walking the matches
    via the per-match metrics list embedded in summary.json (rows in
    'per_match' if present), or fall back to deriving from home_team /
    aggregate stats (when no row-level data is available).
    """
    rows = summary.get("per_match") or summary.get("rows") or []
    if not rows:
        return []
    diffs: list[int] = []
    for r in rows:
        hs = r.get("home_score")
        as_ = r.get("away_score")
        if not isinstance(hs, int) or not isinstance(as_, int):
            continue
        if r.get("home_team") == variant_name:
            diffs.append(hs - as_)
        elif r.get("away_team") == variant_name:
            diffs.append(as_ - hs)
    return diffs


def variant_diffs_from_csv(summary_path: Path, variant_name: str) -> list[int]:
    csv_path = summary_path.with_name("summary.csv")
    if not csv_path.is_file():
        return []
    import csv
    out: list[int] = []
    with csv_path.open() as f:
        for row in csv.DictReader(f):
            try:
                hs = int(row.get("home_score") or "")
                as_ = int(row.get("away_score") or "")
            except (TypeError, ValueError):
                continue
            if row.get("home_team") == variant_name:
                out.append(hs - as_)
            elif row.get("away_team") == variant_name:
                out.append(as_ - hs)
    return out


def stats(diffs: list[int]) -> tuple[float, float, float]:
    """Return (mean, std, se)."""
    n = len(diffs)
    if n == 0:
        return float("nan"), float("nan"), float("nan")
    mean = sum(diffs) / n
    if n < 2:
        return mean, float("nan"), float("nan")
    var = sum((x - mean) ** 2 for x in diffs) / (n - 1)
    std = math.sqrt(var)
    se = std / math.sqrt(n)
    return mean, std, se


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="combine_balanced_legs.py")
    ap.add_argument("leg1", type=Path, help="First leg summary.json (e.g. balanced_vanilla_left)")
    ap.add_argument("leg2", type=Path, help="Second leg summary.json (e.g. balanced_spica325_left)")
    ap.add_argument("--variant", default="SPICA325",
                    help="Team name to treat as the variant (default: SPICA325)")
    args = ap.parse_args(argv)

    if not args.leg1.is_file():
        print(f"leg1 summary not found: {args.leg1}", file=sys.stderr)
        return 2
    if not args.leg2.is_file():
        print(f"leg2 summary not found: {args.leg2}", file=sys.stderr)
        return 2

    s1 = load(args.leg1)
    s2 = load(args.leg2)

    d1 = variant_diffs_from_csv(args.leg1, args.variant) or variant_per_match_diffs(s1, args.variant)
    d2 = variant_diffs_from_csv(args.leg2, args.variant) or variant_per_match_diffs(s2, args.variant)

    if not d1 and not d2:
        print(f"no rows found for variant={args.variant} in either leg", file=sys.stderr)
        return 1

    m1, sd1, se1 = stats(d1)
    m2, sd2, se2 = stats(d2)
    combined = d1 + d2
    mc, sdc, sec = stats(combined)
    ci95 = 1.96 * sec if not math.isnan(sec) else float("nan")
    z = mc / sec if (sec and not math.isnan(sec) and sec > 0) else float("nan")

    print(f"variant team: {args.variant}")
    print(f"leg1 ({args.leg1.parent.name}): n={len(d1):2d} mean_diff={m1:+.3f} sd={sd1:.3f} se={se1:.3f}")
    print(f"leg2 ({args.leg2.parent.name}): n={len(d2):2d} mean_diff={m2:+.3f} sd={sd2:.3f} se={se2:.3f}")
    print(f"COMBINED          : n={len(combined):2d} mean_diff={mc:+.3f} sd={sdc:.3f} se={sec:.3f} 95%CI=±{ci95:.3f}")
    print(f"approx z (mean/se): {z:+.3f}   (|z|>=1.96 -> p<0.05; |z|>=2.58 -> p<0.01)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
