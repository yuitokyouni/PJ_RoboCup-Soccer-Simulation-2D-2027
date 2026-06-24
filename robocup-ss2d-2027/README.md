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

## Harness scripts (Phase 1)

Entry points are exposed through `make`. See `setup/SETUP.md` for install
prerequisites and `setup/DEPENDENCIES.md` for the dependency table.

- `make doctor` — `scripts/doctor.sh`. Checks that rcssserver, helios-base
  binaries, librcsc, python3 and jq are installed. Prints actionable
  install URLs for anything missing. Non-zero exit on any required miss.
- `make smoke` — `scripts/run_smoke_match.sh`. Runs a single
  helios-base vs helios-base match and writes
  `logs/runs/<UTC-timestamp>/{server.out,*.rcg,*.rcl,metrics.json}`.
  Requires `HELIOS_BASE_DIR` (or `HOME_TEAM_START` / `AWAY_TEAM_START`).
- `python evaluation/parse_match_result.py --help` — produces the
  minimal `metrics.json` from a run directory. Tolerant of missing fields.
- `make build-baseline` — not automated; points at `setup/SETUP.md`.
- `make clean` — wipes `logs/runs/*` but keeps the `.gitkeep`.

All scripts support `--help`. The rcssserver invocation flags inside
`run_smoke_match.sh` are marked UNVERIFIED against rcssserver-18 until a
real match has been driven through the harness.
