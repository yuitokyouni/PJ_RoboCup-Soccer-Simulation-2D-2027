#!/usr/bin/env python3
"""compare_summaries.py - compare two summary.json files.

Reads two summaries produced by `evaluation/aggregate_results.py`, lays
out the side-by-side numbers, and computes the delta in mean_goal_diff
with a combined-SE 95% CI assuming the two batches are independent.

Strong claims about which side is "better" are refused unless **both**
summaries are RESEARCH_GRADE and have `run_reality_status ==
real_rcssserver`. The refusal lists the specific condition each side
failed, so the operator does not have to guess what needs fixing.

Usage:
  compare_summaries.py BASELINE_SUMMARY_JSON VARIANT_SUMMARY_JSON
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

REQUIRED_REGIME = "RESEARCH_GRADE"
REQUIRED_REALITY = "real_rcssserver"


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def fmt(v, digits: int = 3) -> str:
    if v is None:
        return "n/a"
    if isinstance(v, float):
        return f"{v:.{digits}f}"
    return str(v)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="compare_summaries.py",
        description="Compare two summary.json files; refuse strong claims under SMOKE_ONLY.",
    )
    p.add_argument("baseline", type=Path,
                   help="Path to the baseline summary.json")
    p.add_argument("variant", type=Path,
                   help="Path to the variant summary.json")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.baseline.is_file():
        print(f"baseline summary not found: {args.baseline}", file=sys.stderr)
        return 2
    if not args.variant.is_file():
        print(f"variant summary not found: {args.variant}", file=sys.stderr)
        return 2

    b = load(args.baseline)
    v = load(args.variant)

    rows = (
        ("baseline", b, args.baseline),
        ("variant",  v, args.variant),
    )

    print(f"{'metric':<25} {'baseline':<28} {'variant':<28}")
    print("-" * 81)
    print(f"{'path':<25} {str(args.baseline)[-28:]:<28} {str(args.variant)[-28:]:<28}")
    for k in ("completed_matches", "sample_regime",
              "run_reality_status", "declared_reality_assertion"):
        bs = b.get(k, "?")
        vs = v.get(k, "?")
        print(f"{k:<25} {str(bs):<28} {str(vs):<28}")
    for k in ("mean_goal_diff", "se_goal_diff",
              "ci95_goal_diff_low", "ci95_goal_diff_high"):
        print(f"{k:<25} {fmt(b.get(k)):<28} {fmt(v.get(k)):<28}")

    # Delta
    print()
    bm, vm = b.get("mean_goal_diff"), v.get("mean_goal_diff")
    bse, vse = b.get("se_goal_diff"), v.get("se_goal_diff")
    if None in (bm, vm, bse, vse):
        print("delta mean_goal_diff: unavailable (one side missing mean or SE)")
    else:
        delta = vm - bm
        combined_se = math.sqrt(bse * bse + vse * vse)
        lo = delta - 1.96 * combined_se
        hi = delta + 1.96 * combined_se
        print(f"delta mean_goal_diff (variant - baseline): {delta:.3f}")
        print(f"combined SE (independent samples):         {combined_se:.3f}")
        print(f"delta 95% CI:                              [{lo:.3f}, {hi:.3f}]")

    # Strong-claim gate
    reasons: list[str] = []
    for label, s, _ in rows:
        if s.get("sample_regime") != REQUIRED_REGIME:
            reasons.append(f"{label}: sample_regime is {s.get('sample_regime')!r}, not {REQUIRED_REGIME!r}")
        if s.get("run_reality_status") != REQUIRED_REALITY:
            reasons.append(f"{label}: run_reality_status is {s.get('run_reality_status')!r}, not {REQUIRED_REALITY!r}")

    print()
    if not reasons:
        print(f"ALLOWED  strong claim about delta is permitted (both sides {REQUIRED_REGIME} and {REQUIRED_REALITY}).")
        return 0

    print("REFUSED  strong claim about delta is NOT permitted. Reasons:")
    for r in reasons:
        print(f"  - {r}")
    print()
    print("See docs/EVALUATION_PROTOCOL.md and docs/REAL_INTEGRATION.md for the gates.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
