# 2026-06-24 — Harness Phase 1

## Goal

Stand up the minimal reproducible match harness described in CLAUDE.md, without
touching agent behavior or implementing RL.

## What landed

- `CLAUDE.md`, `.gitignore`, `logs/runs/.gitkeep`.
- `setup/SETUP.md` (Ubuntu + manual build walkthrough) and
  `setup/DEPENDENCIES.md` (table of required tools and env vars).
- `Makefile` with `help` (default), `doctor`, `smoke`, `build-baseline`
  (stub), and `clean`.
- `scripts/doctor.sh` — required-vs-optional dependency check with `--help`
  and actionable install URLs. Exits non-zero if anything required is
  missing. Verified locally.
- `scripts/run_smoke_match.sh` — single-match runner. Writes
  `server.out`, `*.rcg`, `*.rcl`, and `metrics.json` into
  `logs/runs/<UTC-timestamp>/`. Verified to fail fast and clearly when
  `rcssserver` is not on PATH; the actual match execution path is
  **unverified**.
- `evaluation/parse_match_result.py` — tolerant parser, emits the
  minimal `metrics.json` schema (home/away team, score, result, rcg/rcl
  paths, server_version, notes). Falls back to parsing the rcg filename;
  records the reason for any unknown field in `notes`.
- `experiments/baseline_smoke.yaml` — declarative form of the smoke
  match. Phase 1 doesn't read it programmatically, but Phase 2 will.

## Acceptance criteria check

| Criterion                                      | Status                        |
|------------------------------------------------|-------------------------------|
| `make doctor` checks binaries/deps             | Verified, exits 1 on missing  |
| `make smoke` runs match or precise missing-dep | Verified for missing-dep path |
| `python evaluation/parse_match_result.py --help` works | Verified              |
| Repo explains what remains manual              | `setup/SETUP.md` section 7    |

## Unverified

- rcssserver flag combo
  (`server::auto_mode=true`, `server::team_l_start`, `server::team_r_start`,
  `server::game_log_dir`, `server::text_log_dir`, `server::game_log_compression=0`,
  `server::port`) against rcssserver-18. Canonical pattern for older
  releases, but not confirmed against the latest. If it breaks, fall back
  to launching teams manually in separate shells.
- helios-base build instructions in `setup/SETUP.md` have not been run on
  a clean machine.
- 2027 server target version. We track upstream `master` and will re-pin
  once the 2027 CFP names a version.

## Out of scope for Phase 1

- Batch matches, seed sweeps, summary statistics (→ Phase 2).
- Agent or strategy changes (→ later).
- RL or learning (→ much later, if ever for this paper).
- Replacing helios-base with Cyrus2D / Gliders2D / Pyrus.

## Next step

When a machine has rcssserver + helios-base built, drive `make smoke`
end-to-end, confirm `metrics.json` is populated, and mark the rcssserver
flag combo verified in a follow-up commit. After that, Phase 2:
`scripts/run_batch_matches.sh`, `evaluation/aggregate_results.py`,
`docs/EVALUATION_PROTOCOL.md`.

---

## Phase 1.5 — Server Contract Verification (2026-06-24)

Goal: lock down which server we ran, which options we passed, and what
exactly happened, before scaling out to batch evaluation.

### Added

- `setup/SERVER_CONTRACT.md` — canonical list of every `server::*` flag
  the harness passes, with a verified-or-not column. Documents the
  config-file lookup order, the timeout policy, and the
  process-tree-cleanup contract that rests on `setsid`.
- `scripts/probe_rcssserver.sh` — read-only diagnostic. Prints the
  rcssserver path, version (tolerant of `--version`/`-V` differences),
  whether `--help` responds, which documented HOME config files exist,
  and the launch options the harness will pass. Exposed as `make probe`.
- `doctor.sh` gains `timeout` (GNU coreutils) and `setsid` (util-linux)
  as required checks — the smoke runner needs both for hardening.

### Schema bump: 1.0 → 1.1

`scripts/run_smoke_match.sh` now writes `metadata.json` and
`evaluation/parse_match_result.py` merges it into `metrics.json`. Common
fields: `schema_version`, `run_id`, `created_at_utc`, `server_binary`,
`server_version`, `server_options`, `home_start_command`,
`away_start_command`. `metadata.json` additionally carries
`timeout_secs` and `match_status`; `metrics.json` additionally carries
`home_team`/`away_team`/scores, `result`, `rcg_files`, `rcl_files`,
`parser_notes` (list, not string).

### Hardening of `run_smoke_match.sh`

- `set -euo pipefail` (kept).
- `--timeout SECONDS` (default 120, also via `TIMEOUT_SECS`).
- Server runs under `setsid timeout --kill-after=5 …` so the harness can
  signal the whole process group on exit.
- `trap on_exit EXIT INT TERM` sends SIGTERM then SIGKILL to the
  process group, writes `metadata.json` with the latest `match_status`,
  then exits.
- `match_status` is one of:
  `dependency_missing`, `server_failed_to_start`, `teams_failed_to_start`,
  `match_completed`, `timeout`, `unknown_failure`.

### Verified locally (with stand-in rcssserver binaries)

| Scenario                                    | Resulting match_status     | Exit |
|---------------------------------------------|----------------------------|------|
| HOME_TEAM_START not executable              | `dependency_missing`       | 1    |
| rcssserver exits non-zero                   | `server_failed_to_start`   | 1    |
| rcssserver exits 0 but writes no `.rcg`     | `teams_failed_to_start`    | 1    |
| rcssserver exits 0 and writes `.rcg`/`.rcl` | `match_completed`          | 0    |
| rcssserver hangs past `--timeout 2`         | `timeout`                  | 1    |

No orphan processes left behind after the timeout case.

### Still UNVERIFIED

- The `server::auto_mode=true` + `team_l_start` + `team_r_start`
  combination against a real rcssserver-18 binary. This is what
  Phase 1.5 was designed to *isolate*, not yet *clear*.
- Whether HOME config files override command-line `server::*` options or
  vice versa on the installed version. The probe lists what's there;
  whoever runs the first real `make smoke` should compare.
- helios-base build path in `setup/SETUP.md` on a clean machine.
- 2027 server target version.

### Out of scope (kept)

Batch matches, agent code changes, RL. None of the Phase 1.5 work
touches behavior.
