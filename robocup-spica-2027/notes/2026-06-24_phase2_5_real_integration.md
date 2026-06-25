# 2026-06-24 — Phase 2.5: Real RCSS2D Integration

## Goal

Make the harness honest about what it ran. Phase 2 batch evaluation
worked, but `summary.json` could imply that YAML `server_options` were
applied when in fact the smoke runner used its own hardcoded set. Phase
2.5 wires real external binaries in **and** closes that gap before any
30-match run can call itself `RESEARCH_GRADE`.

This is the verification phase, not the evaluation phase.

## What landed

### External integration

- `externals/EXTERNALS.md` — pinned set:
  - `rcssserver` at `rcssserver-19.0.0` (latest release as of 2026-06-24)
  - `librcsc` at `master`
  - `helios-base` at `master` (historical / minimal reference)
  - `cyrus2dbase` at `master` (first practical baseline)
  Each license marked **UNVERIFIED**.
- `scripts/fetch_externals.sh` — clones into `externals/src/<name>/`,
  records `<name> <repo> <ref> <commit>` lines to
  `externals/EXTERNALS.lock`. Supports `--force`, `--full`, `--only`.
- `scripts/build_externals.sh` — autotools build into
  `externals/install/`, ordered librcsc → rcssserver → helios-base →
  cyrus2dbase. Pre-flights `autoconf/automake/libtool/pkg-config/flex/
  bison/g++/make` + Boost; refuses to install system packages itself
  and prints the exact `sudo apt install …` line on miss.
- `Makefile` gains `fetch-externals`, `build-externals`, `real-smoke`.
- `experiments/cyrus_vs_cyrus_smoke.yaml` — the canonical
  Cyrus2D-vs-Cyrus2D smoke experiment, intentionally
  `UNVERIFIED:`-prefixed on the start commands so a fresh machine fails
  with `dependency_missing` rather than pretending to run.
- `docs/REAL_INTEGRATION.md` — the contract for this phase:
  `synthetic_or_stubbed` vs `real_rcssserver`, the declared/applied/
  unapplied split, the tightened `RESEARCH_GRADE` rule, the recommended
  workflow, and the explicit "what verified looks like" gate.
- `setup/SETUP.md` and `setup/DEPENDENCIES.md` updated for the
  automated path + build-time toolchain table.

### The critical correction (declared vs applied)

Before this phase, `experiment.json::server_options` carried YAML
intent but the smoke runner ignored it. After this phase:

- YAML `server_options` are filtered: entries beginning with
  `UNVERIFIED:` or failing `^server::namespace[::sub]=value` are
  stripped, with the reason recorded in
  `experiment.json::declared_server_options_filter_notes`.
- Surviving entries are passed to `run_smoke_match.sh` as
  `--server-option KEY=VALUE` flags (repeatable, new).
- The smoke runner records the final command line in
  `metadata.json::applied_server_options` (schema bumped 1.1 → 1.2;
  the field was previously `server_options`).
- The aggregator computes
  `summary.json::unapplied_server_options = declared - applied_union`
  and refuses to promote `sample_regime` to `RESEARCH_GRADE` while that
  list is non-empty.

`reality_assertion` (new YAML field; default `synthetic_or_stubbed`) is
read by batch, written into `experiment.json`, forwarded to every smoke
call, and recorded per match in `metadata.json::reality_assertion`. The
smoke runner does **not** verify the claim; the aggregator does, by
combining it with the unapplied check.

### Tightened `RESEARCH_GRADE`

Promotion now requires **all** of:
1. `completed_matches >= MIN_COMPLETED_FOR_CLAIMS` (= 30)
2. `run_reality_status == "real_rcssserver"`
3. `unapplied_server_options == []`
4. `unknown_results == 0`
5. Timeouts surfaced via an automatic `summary.notes` entry
   (so the regime change can never be silent)

Anything else stays `SMOKE_ONLY`. `MIN_COMPLETED_FOR_CLAIMS` is still
the single source of truth.

## Schema changes

| File              | Old     | New     | Notable changes                                         |
|-------------------|---------|---------|---------------------------------------------------------|
| `metadata.json`   | 1.1     | 1.2     | `server_options` → `applied_server_options`; +`reality_assertion` |
| `metrics.json`    | 1.1     | 1.2     | mirrors metadata; parser `LIST_KEYS` updated            |
| `experiment.json` | 0.1.0   | 0.2.0   | +`reality_assertion`, `declared_server_options`, `applied_server_options_subset`, `declared_server_options_filter_notes` |
| `summary.json`    | 0.1.0   | 0.2.0   | +`run_reality_status`, `declared_reality_assertion`, `declared_server_options`, `unapplied_server_options` |

## Acceptance criteria check

| Criterion                                              | Status                                  |
|--------------------------------------------------------|-----------------------------------------|
| `make fetch-externals` either clones or fails clearly  | Verified --help; clone needs network    |
| `make build-externals` either builds or fails clearly  | Verified pre-flight catches missing tools |
| `make real-smoke` writes metadata.json + metrics.json  | Verified via batch path (smoke writes both) |
| `metadata.json` records external repo commits          | Per-run via `git rev-parse` (UNVERIFIED) — Phase 3 may inline the lock |
| `metadata.json` records server binary / version        | Verified (was Phase 1.5)                |
| `metadata.json` records declared/applied server_options + start commands | Verified (declared lives in experiment.json; applied per match) |
| Failed match's `match_status` explains why             | Verified (Phase 1.5 taxonomy)           |
| No performance claims                                  | RESEARCH_GRADE blocked by ≥30 + reality + unapplied + unknown checks |

### Scenarios verified end-to-end (stand-in rcssserver)

1. **Synthetic batch with mixed YAML options.** 3 declared options
   (1 valid, 1 `UNVERIFIED:`, 1 malformed). Batch keeps 1; the other
   two land in `filter_notes`. `summary.unapplied_server_options`
   contains those two. `run_reality_status = synthetic_or_stubbed`.
2. **Real-claim batch with 2 matches.** YAML asserts
   `reality_assertion: real_rcssserver`; all declared options apply.
   `summary.run_reality_status = real_rcssserver`,
   `unapplied_server_options = []`, but
   `sample_regime = SMOKE_ONLY` because n = 2 < 30. Threshold honoured.

## Still UNVERIFIED

- Every external license (only Cyrus2DBase author's license is
  potentially ambiguous; the rcssserver / librcsc / helios-base trees
  carry COPYING files we have not opened).
- Cyrus2DBase build path against `rcssserver-19` (Cyrus README
  documents `rcssserver-18`).
- The `home_start_command` / `away_start_command` paths in the
  Cyrus YAML — kept `UNVERIFIED:`-prefixed by design until the first
  real run succeeds.
- 2027 server target version.

## Intentionally NOT done

- Performance evaluation. SMOKE_ONLY only.
- Parallel batch execution.
- Per-match git commit hash recording for the externals (the lock file
  exists; surfacing it inside `metadata.json` is a Phase 3 follow-on).
- Cyrus2DBase / HELIOS / Gliders2D comparison; this phase only runs
  Cyrus vs Cyrus.

## What unblocks `RESEARCH_GRADE`

1. `make fetch-externals && make build-externals` on a Linux dev box.
2. Edit `experiments/cyrus_vs_cyrus_smoke.yaml`: remove the
   `UNVERIFIED:` prefixes on the two start commands and point them at
   the actual cyrus2dbase start script paths under `externals/src/`.
3. `make real-smoke` produces a match with `match_status =
   match_completed` and `applied_server_options` containing no
   surprises.
4. The commit that removes the `UNVERIFIED:` markers references the
   resulting `metadata.json` path and the four external commit hashes
   (per `docs/REAL_INTEGRATION.md`).
5. Bump `NUM_MATCHES` to 3 for a small batch; confirm
   `run_reality_status == real_rcssserver` and
   `unapplied_server_options == []`.
6. Bump `NUM_MATCHES` to 30. If all five conditions hold,
   `sample_regime` flips to `RESEARCH_GRADE` and CI bounds become
   quotable per `docs/EVALUATION_PROTOCOL.md`.

Until step 4, the harness can be exercised but no number is allowed to
be called a result.
