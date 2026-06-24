# Real Integration

Phase 2.5 turns the harness from "passes its own stand-in tests" into
"runs one real match against a real rcssserver and admits it". This
document is the contract for that transition.

## Why this phase exists

Phase 2 records `server_options` in `experiment.json` but the smoke
runner uses its own hardcoded set. That is fine as long as nobody calls
the resulting numbers "real": once they do, declared conditions and
actual conditions have diverged, and every downstream number is suspect.

Phase 2.5 closes that gap **before** any 30-match run. Until it is
closed, `summary.json::sample_regime` can never legitimately read
`RESEARCH_GRADE` — the tightened rule below blocks it.

## Two regimes, named honestly

Every batch records `run_reality_status` in `summary.json`. One of:

| Status                  | Meaning                                                   |
|-------------------------|-----------------------------------------------------------|
| `synthetic_or_stubbed`  | Default. The harness ran, but the server / teams may be   |
|                         | stand-ins (CI, smoke, local self-test).                   |
| `real_rcssserver`       | All matches in this batch ran against the rcssserver+team |
|                         | binaries built from `externals/install/` by               |
|                         | `make build-externals`, and `applied_server_options`      |
|                         | matches `declared_server_options`.                        |

The batch runner sets `run_reality_status="real_rcssserver"` only when:

1. `PATH` resolves `rcssserver` to `externals/install/bin/rcssserver`,
   **or** the binary's `--version` line matches the lock file's
   recorded version, **and**
2. Every match completed with `unapplied_server_options` empty.

Anything else is `synthetic_or_stubbed`. Tests run by this repo's CI
stay in that bucket forever.

## The declared / applied / unapplied split

The `server_options` field in YAML expresses **intent**. The
`rcssserver` command line expresses **reality**. The harness keeps both
visible:

| Field (where)                             | Source                          |
|-------------------------------------------|---------------------------------|
| `declared_server_options` (experiment.json) | The YAML, verbatim            |
| `applied_server_options` (metadata.json)  | What `run_smoke_match.sh` actually passed to `rcssserver` |
| `unapplied_server_options` (summary.json) | declared minus applied, plus anything in YAML that starts with `"UNVERIFIED:"` or fails option-shape validation |

Concretely:

- The batch runner reads YAML `server_options`, strips entries that begin
  with `UNVERIFIED:` (or fail the `^server::[A-Za-z_]+=.*$` shape), and
  passes the remaining entries to `run_smoke_match.sh` as
  `--server-option key=value` flags.
- The smoke runner appends its own required runtime flags
  (`game_log_dir`, `text_log_dir`, `game_log_compression`, `port`,
  `auto_mode`, `team_l_start`, `team_r_start`) and records the merged
  list as `metadata.json::applied_server_options`.
- The aggregator compares `experiment.declared_server_options` against
  each match's `applied_server_options`, records anything declared but
  not applied as `unapplied_server_options`, and surfaces the union in
  `summary.json`.

If any declared option fails to round-trip, the summary says so out
loud. `sample_regime` cannot flip to `RESEARCH_GRADE` while that list
is non-empty.

## Tightened RESEARCH_GRADE rule

`evaluation/aggregate_results.py::sample_regime` returns
`RESEARCH_GRADE` **iff all** of the following hold:

1. `completed_matches >= MIN_COMPLETED_FOR_CLAIMS` (= 30).
2. `run_reality_status == "real_rcssserver"`.
3. `unapplied_server_options == []`.
4. `unknown_results == 0`.
5. `match_status_counts["timeout"] == 0` **or** `summary.notes`
   explicitly lists every timed-out match with a reason. The aggregator
   adds a default note in the latter case so the regime change is never
   silent.

Otherwise the regime is `SMOKE_ONLY`. The same threshold is referenced
from this doc and from `MIN_COMPLETED_FOR_CLAIMS` so it cannot drift.

## Recommended workflow

```sh
# One-time, on a developer machine
sudo apt install -y autoconf automake libtool pkg-config flex bison \
                    build-essential libboost-all-dev qtbase5-dev qt5-qmake

make fetch-externals          # clones rcssserver, librcsc, helios-base, cyrus2dbase
make build-externals          # builds them into externals/install/
export PATH="$PWD/externals/install/bin:$PATH"

make doctor                   # should now report all green
make probe                    # should now print a real rcssserver version

# Phase 2.5: 1-3 real matches
make real-smoke               # writes 1 real match into a real-smoke run dir

# Phase 3+ (only after Phase 2.5 passes)
make batch EXPERIMENT=experiments/cyrus_vs_cyrus_smoke.yaml NUM_MATCHES=3
```

## What "verified" looks like

A Phase 2.5 commit may remove an `UNVERIFIED:` marker from
`setup/SERVER_CONTRACT.md` or `experiments/*.yaml` **only** when:

- The commit message references a successful `make real-smoke` run.
- The `metadata.json` from that run is reachable from the commit body
  (path + commit hashes of all four externals).
- `applied_server_options` round-trips back into the YAML (no surprise
  flags).

Until those three are true, the markers stay. The point is not to look
clean; the point is not to lie.
