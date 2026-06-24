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
