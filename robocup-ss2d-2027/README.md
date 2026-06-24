# robocup-ss2d-2027

Goal: Build and evaluate a RoboCup Soccer Simulation 2D team for RoboCup 2027, with emphasis on statistically robust multi-agent strategy evaluation and opponent modeling.

## Deadline Assumption

RoboCup 2027 Soccer Simulation 2D qualification is expected around Feb-Mar 2027, based on RoboCup 2026 timelines.

## Near-term milestones

- [ ] Run rcssserver locally
- [ ] Run a baseline team
- [ ] Collect official logs and binaries
- [ ] Build match evaluation scripts
- [ ] Choose base code: HELIOS / Cyrus2D / Pyrus / Gliders
- [ ] Produce first TDP skeleton

## Harness scripts (Phase 1 + 2)

Entry points are exposed through `make`. See `setup/SETUP.md` for install
prerequisites and `setup/DEPENDENCIES.md` for the dependency table.

- `make doctor` — `scripts/doctor.sh`. Checks that rcssserver, helios-base
  binaries, librcsc, python3, GNU `timeout`, `setsid`, and jq are installed.
  Prints actionable install URLs for anything missing. Non-zero exit on
  any required miss.
- `make probe` — `scripts/probe_rcssserver.sh`. Read-only inspection of
  the installed rcssserver: path, version, `--help` behavior, which
  documented config files exist under `$HOME`, and the exact command-line
  options the smoke runner will pass (with UNVERIFIED markers). See
  `setup/SERVER_CONTRACT.md` for the rationale behind each option.
- `make smoke` — `scripts/run_smoke_match.sh`. Runs a single
  helios-base vs helios-base match and writes
  `logs/runs/<UTC-timestamp>/{server.out,*.rcg,*.rcl,metrics.json}`.
  Requires `HELIOS_BASE_DIR` (or `HOME_TEAM_START` / `AWAY_TEAM_START`).
- `python evaluation/parse_match_result.py --help` — produces the
  minimal `metrics.json` from a run directory. Tolerant of missing fields.
- `make batch EXPERIMENT=experiments/baseline_vs_baseline.yaml` —
  `scripts/run_batch_matches.sh`. Runs an N-match experiment under one
  experiment_id and lays it out as
  `logs/experiments/<id>/matches/match_NNNNNN/`. Resumable (skips
  matches whose `metrics.json` already exists; pass `FORCE=1` to
  override). Failure-tolerant: a failed match never stops the batch.
  Optional `NUM_MATCHES=`, `TIMEOUT=`, `FORCE=1`, `DRY_RUN=1`.
- `make aggregate EXPERIMENT_DIR=logs/experiments/<id>` —
  `evaluation/aggregate_results.py`. Re-emits `summary.csv` and
  `summary.json` from the per-match outputs. `make batch` calls this
  automatically; `make aggregate` is for re-running after edits.
- `make build-baseline` — not automated; points at `setup/SETUP.md`.
- `make clean` — wipes `logs/runs/*` but keeps the `.gitkeep`.

All scripts support `--help`. The rcssserver invocation flags inside
`run_smoke_match.sh` are marked UNVERIFIED against rcssserver-18 until a
real match has been driven through the harness. Phase 2 evaluation
semantics — when scores may be claimed, what `SMOKE_ONLY` means, what
counts as "completed" — live in `docs/EVALUATION_PROTOCOL.md`.
