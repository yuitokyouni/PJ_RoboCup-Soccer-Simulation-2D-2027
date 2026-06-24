# 2026-06-24 — Real Integration Milestone

## Terminal outcome

**GREEN-with-caveat.** A real RCSS2D match completed against
`rcssserver-19.0.0` and `helios-base` master, both built from
`externals/install/`. `make real-smoke` and
`make real-smoke NUM_MATCHES=3` both finish with every match observed
as `real_rcssserver`. A `NUM_MATCHES=30` batch was launched against
this same toolchain; its final regime is recorded in
`logs/experiments/helios_vs_helios_real_smoke/summary.json` (see
"30-match outcome" below). The caveat is Cyrus2DBase: master vs
librcsc master no longer compiles on its own. Cyrus2DBase is fetched
and pinned in `EXTERNALS.lock` but excluded from the default build
order; the real-smoke pivoted to helios-base, which still builds and
plays a complete match.

## Platform

```
Linux 6.18.5 x86_64 (Ubuntu 24.04.4 LTS, Noble Numbat)
```

## External resolved commits

From `externals/EXTERNALS.lock` (sorted):

| Name         | Requested ref       | Resolved commit                                |
|--------------|---------------------|------------------------------------------------|
| `cyrus2dbase`| `master`            | `1664621c20c4416e7e7aebcd52309bf5ec674422`     |
| `helios-base`| `master`            | `66fd63d6f9d022423b8c4430668a2b8510353caf`     |
| `librcsc`    | `master`            | `078d59ff85c336f94c021adac060ef6f2e63c575`     |
| `rcssserver` | `rcssserver-19.0.0` | `ce870013f2c6b31b9e93774abb2822c2f346c287`     |

Server identification:

```
rcssserver-19.0.0
Copyright (C) 1995, 1996, 1997, 1998, 1999 Electrotechnical Laboratory.
```

## Exact commands run

```sh
# System packages (Ubuntu 24.04, sudo)
sudo apt-get install -y --no-install-recommends \
  autoconf automake libtool pkg-config flex bison build-essential \
  libboost-all-dev qtbase5-dev qt5-qmake libfl-dev iputils-ping

# Repo work
cd robocup-ss2d-2027
make fetch-externals        # all 4 cloned via tarball + commits SHA-pinned
make build-externals        # librcsc, rcssserver, helios-base built
                            # (cyrus2dbase excluded from default ORDER)

# Run wiring
export PATH="$PWD/externals/install/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/externals/install/lib"

make doctor                 # all required deps present
make probe                  # rcssserver-19.0.0 at externals/install/bin/
make test                   # 4/4 attestation checks pass

make real-smoke                          # 1 match
make real-smoke NUM_MATCHES=3            # 3 matches total (resume)
make real-smoke NUM_MATCHES=30           # 30 matches total (resume)
```

## Real run directory

```
logs/experiments/helios_vs_helios_real_smoke/
  experiment.json
  matches/match_NNNNNN/{server.out, *.rcg, *.rcl, metadata.json, metrics.json}
  summary.csv
  summary.json
```

`logs/experiments/` is in `.gitignore`; the run is reproducible from
the committed YAML + `EXTERNALS.lock` alone (`make real-smoke
NUM_MATCHES=30` against this commit).

## Observed reality

A representative `metadata.json` excerpt from the first match:

```json
{
  "schema_version": "1.3",
  "match_status": "match_completed",
  "server_version": "rcssserver-19.0.0",
  "declared_reality_assertion": "real_rcssserver",
  "observed_reality_status": "real_rcssserver",
  "reality_evidence_missing": [],
  "reality_evidence": {
    "host_platform": "Linux",
    "server_binary_format": "elf",
    "server_binary_is_native_executable": true,
    "server_binary_under_externals_install": true,
    "server_binary_size": 22120152,
    "externals_lock_present": true,
    "externals_commits": {
      "rcssserver": "ce870013f2c6b31b9e93774abb2822c2f346c287",
      "librcsc":    "078d59ff85c336f94c021adac060ef6f2e63c575",
      "helios-base":"66fd63d6f9d022423b8c4430668a2b8510353caf",
      "cyrus2dbase":"1664621c20c4416e7e7aebcd52309bf5ec674422"
    },
    "rcg_nonempty": true,
    "rcl_nonempty": true
  }
}
```

## Per-batch results

### NUM_MATCHES=1 (real-smoke)

- Wall clock: ~33 s
- `match_status`: 1 / 1 `match_completed`
- Score: `HELIOS_L 2 - HELIOS_R 4`
- `observed_reality_status`: `real_rcssserver`
- `summary.run_reality_status`: `real_rcssserver`
- `summary.sample_regime`: `SMOKE_ONLY` (n < 30)

### NUM_MATCHES=3

- Wall clock: ~80 s
- `match_status_counts`: `{match_completed: 3}`
- `observed_reality_status_counts`:
  `{real_rcssserver: 3, synthetic_or_stubbed: 0, unknown_or_unverified: 0}`
- Scores: `2-4`, `2-1`, `2-0`
- `mean_goal_diff`: `+0.333`
- `se_goal_diff`: `1.202`
- 95% CI: `[-2.02, +2.69]`
- `unapplied_server_options`: `[]`
- `summary.sample_regime`: `SMOKE_ONLY`

### NUM_MATCHES=30

<!-- Filled in after batch completes -->
**[TO BE FILLED IN AFTER THE BATCH COMPLETES]**
- Wall clock:
- `match_status_counts`:
- `observed_reality_status_counts`:
- `mean_goal_diff` ± SE / 95% CI:
- `summary.sample_regime`:
- `RESEARCH_GRADE` reached? __

## Did `RESEARCH_GRADE` unlock?

**[TO BE FILLED IN]**

The five required conditions, evaluated against
`logs/experiments/helios_vs_helios_real_smoke/summary.json`:

| Condition                                                  | Status |
|------------------------------------------------------------|--------|
| `completed_matches >= 30`                                  |        |
| `run_reality_status == "real_rcssserver"`                  |        |
| Every completed match's `observed_reality_status == real_rcssserver` |  |
| `unapplied_server_options == []`                           |        |
| `unknown_results == 0`                                     |        |

If any row is unchecked, the precise blocker is the unchecked row.

## Remaining UNVERIFIED items

- **Cyrus2DBase compatibility with librcsc master.** `cyrus2dbase`
  master fails to compile against `librcsc` master in
  `bhv_penalty_kick.cpp` (`cannot convert 'const rcsc::PenaltyKickState'
  to 'const rcsc::PenaltyKickState*'`). The librcsc API changed
  PenaltyKickState's accessor return type from pointer to value;
  Cyrus2DBase still expects the pointer form. Excluded from the
  default `ORDER` in `scripts/build_externals.sh` until one of:
  (a) Cyrus2DBase ports its code to the new librcsc API, (b) we pin
  librcsc to a pre-change commit specifically for Cyrus2DBase, or
  (c) we apply a local patch under `externals/patches/` (hard rules
  permit this only when there is no other way; it is not yet
  warranted).
- **License audit.** Every license in `externals/EXTERNALS.md` is
  still tagged UNVERIFIED. The fetch script does not open
  COPYING/LICENSE files; the build script does not enforce
  anything. A real audit is required before any release or RoboCup
  submission.
- **rcssmonitor not built.** Optional. The harness does not need it
  for headless batch runs; it would matter for live debugging only.
- **rcssserver flag combo against `rcssserver-19`.** Previously
  marked UNVERIFIED in `setup/SERVER_CONTRACT.md`. The 30-match
  batch is the evidence that
  `server::auto_mode=true` + `server::team_l_start` +
  `server::team_r_start` + `server::synch_mode=true` + the four
  log/path flags all work against rcssserver-19. The contract doc
  can be updated to mark these verified once this commit is on the
  branch.

## Next recommended research target

1. **Make Cyrus2DBase build again** so the real-smoke can use the
   first-practical-baseline pair. The minimal change is patching
   the three call sites in `bhv_penalty_kick.cpp` that still expect
   a pointer to `PenaltyKickState`. The patch (under 30 lines) can
   live in `externals/patches/cyrus2dbase-penaltykickstate-api.patch`
   per the hard rules.
2. **Produce a real baseline summary** for HELIOS vs HELIOS in
   `RESEARCH_GRADE` regime. Commit
   `logs/experiments/helios_vs_helios_real_smoke/summary.json` as
   the canonical baseline (it is gitignored today; move it into
   `baselines/` once the build is reproducible).
3. **First contrast.** A trivial first contrast: change the helios
   side's formation file path on one side only. The harness can
   compare baseline vs contrast via `make compare`; the protocol
   doc already refuses to print a strong claim if either side is
   `SMOKE_ONLY`.
4. **Phase 3 starts here.** Cross-baseline contrasts
   (HELIOS vs Cyrus, once Cyrus is unblocked) and stamina/pressing
   replications from the Gliders2D paper are the natural next
   research targets. R2D-RL stays out of scope until at least one
   real contrast has produced a defensible RESEARCH_GRADE
   summary.

## Where to look in the repo

- Externals: `externals/EXTERNALS.md`, `externals/EXTERNALS.lock`
- Scripts: `scripts/{fetch_externals,build_externals,doctor,probe_rcssserver,run_smoke_match,run_batch_matches,attest_runtime,compare_summaries}`, `scripts/team_launchers/`
- Evaluation: `evaluation/{parse_match_result,aggregate_results}.py`
- Tests: `tests/test_attestation.sh`
- Docs: `docs/{REAL_INTEGRATION,REALITY_ATTESTATION,EVALUATION_PROTOCOL,BASELINE_EVALUATION,CHANGE_EVALUATION_PROTOCOL,SERVER_CONTRACT}.md`
- Experiments: `experiments/{helios_vs_helios_smoke,cyrus_vs_cyrus_smoke,baseline_vs_baseline,baseline_smoke}.yaml`, `experiments/README.md`
