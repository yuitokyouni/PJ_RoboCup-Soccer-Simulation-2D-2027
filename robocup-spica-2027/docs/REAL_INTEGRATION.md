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

## Three regimes, named honestly

Every batch records `run_reality_status` in `summary.json`. One of:

| Status                   | Meaning                                                  |
|--------------------------|----------------------------------------------------------|
| `synthetic_or_stubbed`   | At least one completed match was observed to be a stub. CI, smoke, local self-test. |
| `unknown_or_unverified`  | Not enough evidence to certify either way -- e.g. no matches completed, or evidence missing without stub indicators. |
| `real_rcssserver`        | Every completed match was observed as real, declared as real, and no declared server option went unapplied. |

Promotion is gated by `scripts/attest_runtime.py`, **not** by the
YAML claim. The full ladder is documented in
`docs/REALITY_ATTESTATION.md`. A self-declared
`declared_reality_assertion: real_rcssserver` is necessary but not
sufficient: every completed match must also carry an observed
`real_rcssserver` from attestation, and `unapplied_server_options`
must be empty.

Concretely, the aggregator promotes only when **all** of:

1. `declared_reality_assertion == "real_rcssserver"`.
2. `completed_matches > 0`.
3. Every `match_completed` row has
   `observed_reality_status == "real_rcssserver"` in its metadata.
4. `unapplied_server_options == []`.

`summary.run_reality_block_reasons` names every condition that
failed so an honest "no" arrives with its receipt.

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
2. `run_reality_status == "real_rcssserver"` (which already implies
   declared + observed for every completed match).
3. Every `match_completed` row carries
   `observed_reality_status == "real_rcssserver"` (explicit; the
   aggregator checks this on top of `run_reality_status`).
4. `unapplied_server_options == []`.
5. `unknown_results == 0`.
6. Timeouts are listed in `summary.notes` (the aggregator adds the
   default note automatically so the regime change is never silent).

Otherwise the regime is `SMOKE_ONLY`. The same threshold is referenced
from this doc and from `MIN_COMPLETED_FOR_CLAIMS` so it cannot drift.

## Recommended workflow

```sh
# One-time, on a developer machine (Ubuntu 24.04 verified)
sudo apt install -y autoconf automake libtool pkg-config flex bison \
                    build-essential libboost-all-dev qtbase5-dev qt5-qmake \
                    libfl-dev iputils-ping

make fetch-externals          # fetches rcssserver, librcsc, helios-base, cyrus2dbase tarballs + SHA-pins
make build-externals          # builds librcsc, rcssserver, helios-base into externals/install/
                              # (Cyrus2DBase is excluded by default; see milestone notes)
export PATH="$PWD/externals/install/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/externals/install/lib"

make doctor                   # should now report all green
make probe                    # should now print a real rcssserver version
make test                     # attestation self-tests

# Phase 2.7 verified path: helios-base vs helios-base
make real-smoke                          # 1 real match (~30 s wall clock with synch_mode)
make real-smoke NUM_MATCHES=3            # small batch (~80 s)
make real-smoke NUM_MATCHES=30           # research-grade batch (~15 min)
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
