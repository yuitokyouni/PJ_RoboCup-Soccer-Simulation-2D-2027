# Evaluation Protocol

How the harness decides whether a number means anything, written down so
the rule doesn't drift from one experiment to the next.

## 1. The two questions

Every batch run answers two separate questions, in order:

1. **Was the run real?** How many matches actually played to completion?
   Read this from `summary.json::match_status_counts`. Anything that is
   not `match_completed` says the environment, not the team, decided the
   outcome. This is the first thing to check after every batch.

2. **Given a real run, what does the score say?** Read this from
   `summary.json::mean_goal_diff` and friends.

Skipping question 1 turns the harness into an "automated void"
generator: it produces summaries even when 0 matches played. The status
counts are the load-bearing field that prevents this.

## 2. Definitions

- `goal_diff = home_score - away_score` (per match).
- `mean_goal_diff` = sample mean over `completed_matches`.
- `std_goal_diff` = sample standard deviation, denominator `n - 1`.
- `se_goal_diff = std_goal_diff / sqrt(n)`.
- `ci95_goal_diff = mean ± 1.96 * se`.

The 1.96 multiplier is the normal-approximation CI. It is **only valid
for large enough n** that the central limit theorem starts to bite —
roughly `n >= 30` for tame distributions. RCSS2D scores are integer and
skewed; the true coverage is worse than nominal for small n. Phase 3 may
swap this for a bootstrap CI per match-pair.

## 3. Sample-size regimes

`summary.json::sample_regime` is one of:

| Regime           | Trigger                          | What you may say                  |
|------------------|----------------------------------|-----------------------------------|
| `SMOKE_ONLY`     | `completed_matches < 30`         | "the harness produced output"     |
| `RESEARCH_GRADE` | `completed_matches >= 30`        | "team A's mean goal_diff is X ± Y"|

The threshold lives in
`evaluation/aggregate_results.py::MIN_COMPLETED_FOR_CLAIMS` so it is the
same number every place that needs to consult it.

**Hard rule.** No claim that one team is stronger than another may be
made from a `SMOKE_ONLY` summary. Even at `RESEARCH_GRADE`, always
report the CI; a mean with no uncertainty is not a comparison.

## 4. Status taxonomy

`match_status` (per match, in `metadata.json`) is one of:

| Status                   | Meaning                                                  |
|--------------------------|----------------------------------------------------------|
| `dependency_missing`     | a required tool / start script was not found             |
| `server_failed_to_start` | rcssserver exited non-zero before producing a `.rcg`     |
| `teams_failed_to_start`  | rcssserver exited cleanly but produced no `.rcg`         |
| `match_completed`        | rcssserver exited cleanly and a `.rcg` was produced      |
| `timeout`                | hard wall-clock cap hit; harness killed the process tree |
| `unknown_failure`        | script died for a reason not covered above               |

`summary.json::match_status_counts` aggregates these across the
experiment. The aggregator never crashes on missing fields; it counts
matches without a `metrics.json` against `unknown_failure` (or whatever
their `metadata.json::match_status` says) and adds a note.

## 5. What "completed" means

`completed_matches = match_status_counts["match_completed"]`. It is
**not** the same as "produced a `metrics.json`" — a match can produce a
`metrics.json` with `"result": "unknown"` when the parser cannot find a
score. The aggregator separates `unknown_results` (parser couldn't
decide) from `completed_matches` (server said the match ran).

## 6. Reproducibility checklist

Before reporting any batch result, confirm:

- The experiment YAML is committed.
- `summary.json::experiment_dir` points at a directory that still exists.
- Every `matches/match_*/metadata.json` records the same
  `server_version` (mixed-version batches are unsound).
- `match_status_counts` is dominated by `match_completed`; investigate
  before publishing any other regime.

## 7. Out of scope for Phase 2

- Per-opponent breakdowns (we only run home vs away here).
- Paired designs / common-seed comparisons.
- Bootstrap or rank-based CIs.
- Tournament Elo / TrueSkill aggregation.

If you need any of those, document why in `notes/` and propose the
extension as a Phase 3+ change to this file.
