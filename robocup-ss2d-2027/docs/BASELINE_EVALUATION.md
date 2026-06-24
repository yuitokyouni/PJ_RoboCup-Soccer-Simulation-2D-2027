# Baseline Evaluation

What counts as a usable baseline in this harness, and how to produce
one.

## What a baseline is

A *baseline* is a `summary.json` that:

1. Was produced by `make batch` (or `make real-smoke`, which is a
   one-match alias) against the same external commits the contrast
   side will use.
2. Has `sample_regime == "RESEARCH_GRADE"`.
3. Has `run_reality_status == "real_rcssserver"`.
4. Has `unapplied_server_options == []` and `unknown_results == 0`.

Anything that fails any of those checks is **not** a baseline; it is a
smoke run, and `scripts/compare_summaries.py` will refuse to compare
against it.

## How to produce one

1. `make fetch-externals && make build-externals`.
2. `make doctor && make probe` should both come back clean.
3. Confirm `externals/EXTERNALS.lock` is committed.
4. Update `experiments/cyrus_vs_cyrus_smoke.yaml` (or your own
   `experiments/<id>.yaml`) so the start commands point at the real
   `start.sh` and `declared_reality_assertion: real_rcssserver`.
5. `make real-smoke` to verify
   `metadata.json::observed_reality_status == real_rcssserver` on a
   single match.
6. `make batch EXPERIMENT=experiments/<id>.yaml NUM_MATCHES=3` to
   verify resumability + empty `unapplied_server_options`.
7. `make batch EXPERIMENT=experiments/<id>.yaml NUM_MATCHES=30` for
   the real baseline. Confirm
   `summary.json::sample_regime == "RESEARCH_GRADE"`.

The `summary.json` from step 7 is the file to compare contrasts
against.

## What goes in the commit message for a baseline

Same record-keeping the Phase 2.5/2.6 docs ask for, condensed:

- Run directory (`logs/experiments/<id>/`).
- External commits from `EXTERNALS.lock` (four SHAs).
- `metadata.json::server_version` from any one match.
- Host platform (`uname -a`, or just OS + arch).
- `summary.json::completed_matches` and `match_status_counts`.

That makes the baseline reproducible from the repo state alone.

## Common pitfalls

- **Mixed external commits across matches.** Don't re-run
  `make build-externals` between matches in the same batch. The
  aggregator will not catch a mid-batch toolchain swap.
- **Timeouts buried in the batch.** Always read `match_status_counts`
  before the means. If `timeout > 0`, raise the per-match timeout
  and re-run, even if `RESEARCH_GRADE` was reached.
- **Trusting the YAML claim.** `declared_reality_assertion` is only
  a claim. Look at `summary.json::run_reality_status` for the truth.
