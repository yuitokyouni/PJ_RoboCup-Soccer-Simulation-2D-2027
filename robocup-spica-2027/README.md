# Spica2D

Spica2D is a RoboCup Soccer Simulation 2D project targeting RoboCup 2027.

The current research model, Spica325, is a variable 4-3-3/3-2-5 tactical overlay evaluated against a Cyrus-style Vanilla baseline using a reproducible batch evaluation harness.

## Deadline Assumption

RoboCup 2027 Soccer Simulation 2D qualification is expected around Feb-Mar 2027, based on RoboCup 2026 timelines.

## Naming

| Concept    | Name                       | Notes |
|------------|----------------------------|-------|
| Team       | Spica2D                    | Project / team name. |
| Research model | Spica325               | Current tactical overlay (variable 4-3-3 ↔ 3-2-5). |
| Baseline   | Vanilla (Cyrus-style)      | Built from the upstream cyrus-soccer-simulation-team tree with only the rapidjson vendor patch. |
| Project ID | robocup-spica-2027         | Future rename target for this repository. |

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
- `make fetch-externals` — `scripts/fetch_externals.sh`. Clones the
  pinned set from `externals/EXTERNALS.md`
  (rcssserver / librcsc / helios-base / cyrus2dbase) into
  `externals/src/` and writes the resolved commits to
  `externals/EXTERNALS.lock`.
- `make build-externals` — `scripts/build_externals.sh`. Pre-flights
  required system packages, then builds the fetched externals into
  `externals/install/`. Order: librcsc → rcssserver → helios-base →
  cyrus2dbase. Add `externals/install/bin` to `PATH` afterwards.
- `make real-smoke` — runs `scripts/run_batch_matches.sh` with
  `experiments/cyrus_vs_cyrus_smoke.yaml` (default `NUM_MATCHES=1`).
  Requires the externals to be on `PATH` and the UNVERIFIED prefixes on
  the YAML start commands to have been removed. See
  `docs/REAL_INTEGRATION.md` for the declared-vs-applied contract and
  `docs/REALITY_ATTESTATION.md` for the declared-vs-observed contract
  (Phase 2.6): a YAML self-declaration is no longer enough to call a
  run real; `scripts/attest_runtime.py` runs automatically after each
  match and the aggregator only promotes
  `summary.run_reality_status = real_rcssserver` when observed
  evidence matches.
- `make build-baseline` — not automated; points at `setup/SETUP.md`
  and the Phase 2.5 fetch+build path.
- `make clean` — wipes `logs/runs/*` but keeps the `.gitkeep`.

All scripts support `--help`. The rcssserver invocation flags inside
`run_smoke_match.sh` are marked UNVERIFIED against rcssserver-18 until a
real match has been driven through the harness. Phase 2 evaluation
semantics — when scores may be claimed, what `SMOKE_ONLY` means, what
counts as "completed" — live in `docs/EVALUATION_PROTOCOL.md`.
