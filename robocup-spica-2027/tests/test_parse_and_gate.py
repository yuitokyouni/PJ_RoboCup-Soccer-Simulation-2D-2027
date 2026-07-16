#!/usr/bin/env python3
"""Unit tests for parse_match_result.py and aggregate_results.py.

Plain stdlib, no pytest. Non-zero exit on first failure. Run via
`make test` or directly: python3 tests/test_parse_and_gate.py

Added by the 2026-07 audit (docs/REPO_AUDIT_2026-07.md): the score
parser had matched 0 of 211 real server outputs, the aggregate pooled
non-completed matches, and pseudo-matches (one side unconnected)
reached statistics — none of which any test would have allowed.
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "evaluation"))

import parse_match_result as pmr  # noqa: E402
import aggregate_results as agg   # noqa: E402

FAILURES = []


def check(name: str, cond: bool, detail: str = ""):
    if cond:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}  {detail}")
        FAILURES.append(name)


# ------------------------------------------------------------------
# parse_score_from_text — the REAL rcssserver-19 multi-line format
# ------------------------------------------------------------------
REAL_SERVER_OUT = """rcssserver-19.0.0
Simulator Random Seed: 1782639376
...
Game Results:
\t'SPICA325' vs 'CYRUS_VANILLA'
\tScore: 0 - 1
"""
s = pmr.parse_score_from_text(REAL_SERVER_OUT)
check("real multi-line block parses", s is not None)
check("teams extracted", s and s["home_team"] == "SPICA325" and s["away_team"] == "CYRUS_VANILLA", repr(s))
check("score extracted", s and s["home_score"] == 0 and s["away_score"] == 1, repr(s))

# one-side-unconnected form
NULL_OUT = "Game Results:\n\t'CYRUS_VANILLA' vs 'null'\n\tScore: 32 - 0\n"
s = pmr.parse_score_from_text(NULL_OUT)
check("null away parsed as away_score None", s and s["away_team"] == "null" and s["away_score"] is None, repr(s))

# legacy single-line form still supported
s = pmr.parse_score_from_text("Result: helios 2 - 1 gliders")
check("legacy single-line still parses", s and s["home_score"] == 2 and s["away_score"] == 1, repr(s))

# multiple Game Results blocks -> LAST wins
DOUBLE = ("Game Results:\n\t'A' vs 'B'\n\tScore: 1 - 0\n"
          "Game Results:\n\t'A' vs 'B'\n\tScore: 2 - 2\n")
s = pmr.parse_score_from_text(DOUBLE)
check("last results block wins", s and s["home_score"] == 2 and s["away_score"] == 2, repr(s))

# ------------------------------------------------------------------
# validate_match — pseudo-match rejection
# ------------------------------------------------------------------
ok, why = pmr.validate_match({"home_team": "A", "away_team": "B", "home_score": 1, "away_score": 0})
check("normal match valid", ok, why or "")
ok, why = pmr.validate_match({"home_team": "A", "away_team": "null", "home_score": 32, "away_score": None})
check("null away invalid", not ok, "")
ok, why = pmr.validate_match({"home_team": "X", "away_team": "X", "home_score": 3, "away_score": 2})
check("identical team names invalid", not ok, "")
ok, why = pmr.validate_match(None)
check("no score invalid", not ok, "")

# ------------------------------------------------------------------
# t critical values
# ------------------------------------------------------------------
check("t(29) = 2.045 not 1.96", abs(agg.t_crit_95(29) - 2.045) < 0.001, str(agg.t_crit_95(29)))
check("t(inf) -> 1.96", abs(agg.t_crit_95(10**8) - 1.960) < 0.001, str(agg.t_crit_95(10**8)))
check("t(1) = 12.706", abs(agg.t_crit_95(1) - 12.706) < 0.001, str(agg.t_crit_95(1)))

# ------------------------------------------------------------------
# aggregate: status filter + gate
# ------------------------------------------------------------------
def make_match(root: Path, i: int, status: str, hs, as_, valid=True, result=None):
    d = root / "matches" / f"match_{i:06d}"
    d.mkdir(parents=True)
    (d / "metadata.json").write_text(json.dumps({
        "match_status": status,
        "observed_reality_status": "real_rcssserver",
        "applied_server_options": [],
    }))
    if result is None:
        result = ("draw" if hs == as_ else ("home_win" if (as_ is not None and hs > as_) else "away_win")) \
            if isinstance(hs, int) and isinstance(as_, int) else "unknown"
    (d / "metrics.json").write_text(json.dumps({
        "home_team": "A" if valid else "A",
        "away_team": "B" if valid else "null",
        "home_score": hs, "away_score": as_,
        "result": result, "match_valid": valid,
        "invalid_reason": None if valid else "away side never connected",
    }))


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / "experiment.json").write_text(json.dumps({
        "declared_reality_assertion": "real_rcssserver", "server_options": [],
    }))
    # 30 completed valid draws + 1 timeout WITH a partial parseable score
    for i in range(1, 31):
        make_match(root, i, "match_completed", 0, 0)
    make_match(root, 31, "timeout", 3, 0)
    summary, rows = agg.aggregate(root)
    check("timeout score NOT pooled",
          summary["mean_goal_diff"] == 0.0,
          f"mean={summary['mean_goal_diff']}")
    check("completed count excludes timeout", summary["completed_matches"] == 30, str(summary["completed_matches"]))

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / "experiment.json").write_text(json.dumps({
        "declared_reality_assertion": "real_rcssserver", "server_options": [],
    }))
    # 30 completed but one is an INVALID pseudo-match (away null)
    for i in range(1, 30):
        make_match(root, i, "match_completed", 0, 0)
    make_match(root, 30, "match_completed", 32, None, valid=False, result="unknown")
    summary, rows = agg.aggregate(root)
    check("invalid completed match blocks RESEARCH_GRADE",
          summary["sample_regime"] == "SMOKE_ONLY",
          summary["sample_regime"])
    check("invalid match not in goal_diff pool",
          summary["mean_goal_diff"] == 0.0,
          f"mean={summary['mean_goal_diff']}")

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / "experiment.json").write_text(json.dumps({
        "declared_reality_assertion": "real_rcssserver", "server_options": [],
    }))
    # clean 30 valid completed -> RESEARCH_GRADE with t-based CI
    for i in range(1, 31):
        make_match(root, i, "match_completed", (i % 3) - 1 + 1, 1)  # scores 0..2 vs 1
    summary, rows = agg.aggregate(root)
    check("clean batch reaches RESEARCH_GRADE",
          summary["sample_regime"] == "RESEARCH_GRADE",
          json.dumps({k: summary[k] for k in ("sample_regime", "completed_matches", "unknown_results")}))
    if summary["se_goal_diff"]:
        width = summary["ci95_goal_diff_high"] - summary["mean_goal_diff"]
        expected = 2.045 * summary["se_goal_diff"]
        check("CI uses t(29) not z", abs(width - expected) < 1e-9, f"width={width} expected={expected}")

print()
if FAILURES:
    print(f"{len(FAILURES)} test(s) FAILED: {FAILURES}")
    sys.exit(1)
print("all tests passed")
