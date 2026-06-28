# PSG-loop iter-62 batch evaluation results

Date: 2026-06-28
Status: **IN PROGRESS** — will be filled in as batches complete.

## Setup

- Binaries built from `claude/iter62-third-man-run-eval` branch in this
  container.
- Three cyrus-team snapshots:
  - `cyrus-team-vanilla-snapshot` = upstream cyrus-team + rapidjson vendor
    patch only. No Phase 5 anywhere.
  - `cyrus-team-v3-snapshot` = full apply_phase5.sh including Step 7b
    (PHASE5_FEVAL_PATH third-man run path bonus). This is the **iter-62
    variant**.
  - `cyrus-team-v3-noTMR-snapshot` = same as v3-snapshot but with the
    Step 7b block (the `else { ... if (TMR) result += 40; ... }` block
    in `operator()`) reverted before rebuild. This is the **baseline**.
- Externals lock: cyrus-team @ `7283c0decd77c81d15de46aab2a3a3bd90eddfe0`.
- Server: rcssserver 19.0.0 from upstream tag.
- librcsc fork (cyrus-lib) @ `6bafd9b9241a11c3149d449a2b8d8c04fc13f31e`.

## Contrast

Both runs are unbalanced (Spica325 on LEFT, Vanilla on RIGHT). The
contrast is between iter-62 variant and baseline against the SAME
Vanilla on the SAME side. Per `docs/CHANGE_EVALUATION_PROTOCOL.md`, the
delta CI assumes independent samples — this holds because the two
batches use fresh server seeds.

| label | binary | N | W / D / L | mean_goal_diff | se | ci95 |
|-------|--------|---|-----------|----------------|----|------|
| iter-62 variant  | v3-snapshot           | 30 | 1 / 13 / 16 | **-0.633** | 0.148 | [-0.923, -0.344] |
| baseline         | v3-noTMR-snapshot     | TBD | TBD | TBD | TBD | TBD |

| delta | mean | combined se | 95 % ci |
|-------|------|-------------|---------|
| variant − baseline | TBD | TBD | TBD |

## iter-62 variant — score distribution (N=30)

| score | count |
|-------|-------|
| 0-0 | 11 |
| 0-1 | 13 |
| 0-2 |  2 |
| 0-3 |  1 |
| 1-0 |  1 |
| 1-1 |  2 |

Total goals scored by Spica325-iter62: 4.
Total goals conceded:                  22.
mean home goals: 0.10. mean away goals: 0.73.

## Match-by-match (baseline)

| # | home_score | away_score | result | notes |
|---|------------|------------|--------|-------|
| TBD | | | | |

## Detector-firing verification

The iter-62 binary's path-bonus block runs unconditionally when the
geometric conditions match. The `dlog.addText(...)` call inside the
block is gated by `#ifdef DEBUG_PRINT`, which is **disabled in the
binaries used for this evaluation** (Release build, no `-DDEBUG_PRINT`).
Consequence: the path-bonus is applied at runtime, but is not visible
in dlog files.

If the batch result is null (variant ≈ baseline), a follow-up debug
build with `#define DEBUG_PRINT` enabled is needed to confirm the
geometric conditions ever match in a real match.

## Verdict (placeholder)

TBD — populated after `make compare` runs on both summary.json files.

## Rollback if regression

Delete the Step 7b block in `apply_phase5.sh` and re-run
`setup_cyrus_snapshots.sh`. Or just continue using the
`cyrus-team-v3-noTMR-snapshot` binary as the production Spica325.
