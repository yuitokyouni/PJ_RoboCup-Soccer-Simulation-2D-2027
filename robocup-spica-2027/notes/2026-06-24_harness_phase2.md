# 2026-06-24 — Harness Phase 2

## Goal

Extend the smoke harness from one match to an N-match resumable
experiment, without touching agent behavior, without parallelism, and
without claiming "stronger / weaker" until we hit the threshold the
protocol document sets.

## What landed

- `scripts/run_smoke_match.sh` gains `--run-dir PATH` (no other behavior
  change). The basename of PATH becomes `metadata.json::run_id`.
- `scripts/doctor.sh` adds a check for the Python `yaml` module.
- `experiments/baseline_vs_baseline.yaml` — schema 0.1.0, intentionally
  unresolved (`UNVERIFIED: path/...`) so a fresh machine produces
  `match_status=dependency_missing` rather than silently no-oping.
- `docs/EVALUATION_PROTOCOL.md` — the contract that ties summary output
  to claims. Defines `SMOKE_ONLY` vs `RESEARCH_GRADE`, the
  `MIN_COMPLETED_FOR_CLAIMS = 30` threshold, the goal_diff stats, and
  the "question 1 before question 2" rule (was the run real, *then*
  what does the score say).
- `evaluation/aggregate_results.py` — walks `<exp>/matches/match_*/`,
  emits `summary.json` (schema 0.1.0) with `match_status_counts`,
  win/draw counts, mean home/away score, mean goal_diff with sample
  std (n-1) → SE → 95% CI, `sample_regime`, and `notes` for every
  missing-or-malformed field. Also emits `summary.csv` (per-match rows).
- `scripts/run_batch_matches.sh` — Phase 2 entry point. Reads YAML,
  resolves overrides, writes `experiment.json`, runs N matches into
  `matches/match_NNNNNN/`, runs the aggregator, prints
  `match_status_counts` and `sample_regime`.
- `Makefile` gains `batch` and `aggregate`; `make help` describes them.
- `.gitignore` ignores `logs/experiments/`.
- README harness section now covers Phase 1 + 2.

## Output layout

```
logs/experiments/<experiment_id>/
  experiment.json
  matches/
    match_000001/{server.out, *.rcg, *.rcl, metadata.json, metrics.json}
    match_000002/
    ...
  summary.csv
  summary.json
```

## Acceptance criteria check

| Criterion                                          | Status                                |
|----------------------------------------------------|---------------------------------------|
| `make help` lists `batch` and `aggregate`          | Verified                              |
| `scripts/run_batch_matches.sh --help` works        | Verified                              |
| `python evaluation/aggregate_results.py --help` works | Verified                           |
| `make batch EXPERIMENT=... NUM_MATCHES=3` runs or fails clearly | Verified (4 scenarios, see below) |
| Same batch command twice skips completed matches   | Verified (resume path)                |
| Batch system works even when individual matches fail | Verified (UNVERIFIED yaml -> 3 dependency_missing) |

### Scenarios run end-to-end with stand-in rcssserver

1. **Fresh batch, all good** (3 fake matches, scores baked into rcg
   filenames). All 3 → `match_completed`. `summary.json::completed_matches=3`,
   `sample_regime=SMOKE_ONLY` (n < 30).
2. **Resume without --force.** All 3 matches skipped because
   `metrics.json` exists. `summary.json` re-emitted, identical counts.
3. **Resume with --force.** Each match dir wiped and re-run; all 3
   complete again.
4. **Batch against UNVERIFIED yaml.** `home_start_command` literally
   begins `"UNVERIFIED: ..."`, the smoke runner's `[[ -x ]]` test fails,
   each match produces `metadata.json` with `match_status=dependency_missing`
   and no `metrics.json`. `summary.json::match_status_counts.dependency_missing = 3`,
   `completed_matches = 0`. The batch script returns 0 — *the experiment
   is the deliverable*, not any individual match.

## Statistical contract

From `EVALUATION_PROTOCOL.md` (recap):
- `goal_diff = home_score - away_score`
- `mean / std (n-1) / SE = std/sqrt(n) / ci95 = mean ± 1.96 SE`
- `sample_regime = "SMOKE_ONLY" if completed_matches < 30 else "RESEARCH_GRADE"`
- No strength claim under `SMOKE_ONLY`.

`MIN_COMPLETED_FOR_CLAIMS` is one constant in
`aggregate_results.py`, referenced both in `summary.json` and in the
protocol doc so the threshold cannot drift.

## Failure-tolerance contract

`summary.json::match_status_counts` always contains every value in the
known taxonomy (zeros when absent). Code that needs to ask "did the
environment work?" can index unconditionally. This is what stops the
harness from quietly producing "I ran 0 matches; the result is 0-0"
flavored void.

## Intentionally NOT done

- Parallel execution. Serial is fine for Phase 2 and removes a whole
  class of port-collision / log-collision questions.
- Reconciling `experiment.yaml::server_options` with the smoke runner's
  hardcoded `SERVER_OPTIONS`. The runner ignores the YAML field; it is
  recorded into `experiment.json` for the audit trail. Reconciling
  belongs in Phase 3 along with `--server-option` plumbing through the
  smoke runner.
- Per-opponent / paired designs. Out of scope; documented as Phase 3+.
- Any agent-behavior change. The hard rule from CLAUDE.md still holds.

## What unblocks the next session

Real rcssserver + helios-base on a machine. Then:

```
HELIOS_BASE_DIR=/path/to/helios-base \
  make batch \
    EXPERIMENT=experiments/baseline_vs_baseline.yaml \
    NUM_MATCHES=30
```

Set `home_start_command` / `away_start_command` in the YAML to
`$HELIOS_BASE_DIR/src/start.sh` (the `UNVERIFIED:` markers can come
off in the same commit that records "this experiment actually
played"). If `completed_matches` reaches 30, `sample_regime` flips to
`RESEARCH_GRADE` and CI bounds become quotable per the protocol.
