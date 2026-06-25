# 2026-06-24 — Phase 2.6: Reality Attestation

## Goal

`run_reality_status = real_rcssserver` is no longer a YAML
self-declaration. It has to be earned by runtime evidence.

Phase 2.5 closed the declared-vs-applied gap for `server_options` but
left `reality_assertion` as a single field the operator set in the
YAML — and trusted as-is. That meant a CI run with a 200-byte stub
rcssserver could in principle have ended up tagged "real" if someone
flipped the YAML field. Phase 2.6 turns that field into the *claim*
and adds an independent *observation* gate.

## What landed

### Pin terminology + lock as commit target

- `externals/EXTERNALS.md` now distinguishes `requested_ref`
  (operator intent: tag, branch, or commit) from `resolved_commit`
  (what the fetch script actually checked out). A branch name like
  `master` is no longer called a pin.
- `externals/EXTERNALS.lock` is treated like `package-lock.json`:
  fetch script writes it, humans commit it. Removed from
  `externals/.gitignore` so the first real fetch can be checked in
  and downstream attestation can read its commit hashes.

### Attestation

- `scripts/attest_runtime.py` — gathers observable evidence from a
  run directory and merges it back into `metadata.json`:
  `observed_reality_status`, `reality_evidence`,
  `reality_evidence_missing`. Tolerant: never raises on missing
  inputs.
- `docs/REALITY_ATTESTATION.md` — the contract: evidence ladder,
  stub detection ladder, schema, what aggregator does with it.

Required for `observed_reality_status = real_rcssserver`:
- server binary resolves under `externals/install/bin`
- ELF magic + size > 10 KiB + version has no stub keyword
- `externals/EXTERNALS.lock` exists and lists rcssserver
- at least one non-empty `.rcg` and `.rcl`
- both team start commands resolve to existing files

Stub indicators (non-ELF, < 10 KiB, version contains `fake`/`stub`/
`mock`/`dummy`) force `synthetic_or_stubbed` rather than the
"evidence missing" fallback.

### Smoke / parser / batch / YAML wiring

- `scripts/run_smoke_match.sh`: renamed `--reality-assertion` to
  `--declared-reality-assertion`; `metadata.json` schema 1.2 → 1.3
  (`reality_assertion` → `declared_reality_assertion`);
  `write_metadata` now reads-then-merges so attestation fields
  survive trap re-writes; calls `attest_runtime.py` after every
  match regardless of `match_status`.
- `evaluation/parse_match_result.py`: schema 1.2 → 1.3;
  `METADATA_KEYS` gains the three attestation fields and the
  `declared_reality_assertion` rename; `DICT_KEYS` added for
  `reality_evidence`.
- `scripts/run_batch_matches.sh`: reads
  `yaml.declared_reality_assertion`, passes
  `--declared-reality-assertion` to smoke, writes the renamed field
  into `experiment.json`.
- `experiments/cyrus_vs_cyrus_smoke.yaml`: field renamed and the
  inline comment updated to "claim alone is never enough".

### Aggregator + summary

- `evaluation/aggregate_results.py` at schema 0.3.0.
- New fields: `observed_reality_status_counts`,
  `run_reality_block_reasons`.
- `run_reality_status` is now ternary (`real_rcssserver` /
  `synthetic_or_stubbed` / `unknown_or_unverified`) and is set by
  observation, not declaration.
- `RESEARCH_GRADE` adds the explicit per-completed-match observed
  check, so the gate is six conditions long and every one of them
  is named in `block_reasons` when missed.

### Documentation

- `docs/REAL_INTEGRATION.md` rewritten around the three regimes and
  the attestation-gated promotion ladder.
- `docs/REALITY_ATTESTATION.md` is new (above).

## Schema bumps

| File              | Old     | New     | Notable changes                                            |
|-------------------|---------|---------|------------------------------------------------------------|
| `metadata.json`   | 1.2     | 1.3     | `reality_assertion` → `declared_reality_assertion`; +`observed_reality_status`, `reality_evidence`, `reality_evidence_missing` |
| `metrics.json`    | 1.2     | 1.3     | mirrors metadata; parser DICT_KEYS added                   |
| `experiment.json` | 0.2.0   | 0.2.0   | one field renamed (`reality_assertion` → `declared_reality_assertion`); no schema bump |
| `summary.json`    | 0.2.0   | 0.3.0   | +`observed_reality_status_counts`, `run_reality_block_reasons`; `run_reality_status` is ternary |

## Acceptance criteria check

| Criterion                                                                                  | Status     |
|--------------------------------------------------------------------------------------------|------------|
| Existing synthetic/stub tests still pass                                                   | Verified   |
| Stand-in rcssserver with `declared_reality_assertion: real_rcssserver` does NOT promote    | Verified   |
| Dry-run `make real-smoke` records declared but not observed=`real_rcssserver`              | Verified   |
| `python scripts/attest_runtime.py --help` works                                            | Verified   |
| Aggregator explains why a run was not promoted to `real_rcssserver`                        | Verified (`run_reality_block_reasons` per match) |

### Scenarios verified end-to-end

1. **Declared real, observed stub.** Real-claim YAML + bash-script
   "rcssserver" (200-byte non-ELF, version `fake-rcssserver 18`),
   running through batch:
   - 2 / 2 matches reach `match_completed` (the harness doesn't
     refuse to run).
   - `observed_reality_status_counts = {real: 0, synthetic: 2,
     unknown: 0}` (attestation catches all three stub indicators).
   - `run_reality_status = synthetic_or_stubbed`.
   - `run_reality_block_reasons` lists each match by name, each with
     the first attestation failure ("server binary is not an ELF
     executable").
   - `sample_regime = SMOKE_ONLY`.
2. **Dry-run `make real-smoke`.** No matches executed.
   `declared_reality_assertion = real_rcssserver` recorded in
   `experiment.json`. Aggregator runs and reports
   `run_reality_status = unknown_or_unverified`,
   `block_reasons = ["completed_matches == 0; no observation to
   verify"]`, `sample_regime = SMOKE_ONLY`.
3. **Single-match smoke with a fake binary** (the standing Phase 2.5
   test): `match_status = match_completed`,
   `observed_reality_status = synthetic_or_stubbed`,
   `reality_evidence_missing` lists nine specific gaps, `metrics.json`
   propagates both reality fields under the new 1.3 schema.

## Still UNVERIFIED

- An end-to-end run with a real `rcssserver` binary under
  `externals/install/bin/`. This is the first thing Phase 2.7
  exercises; until then, the
  `server_binary_under_externals_install` check has never returned
  `True`.
- The `EXTERNALS.lock` parser's resilience to lock-line variations.
  We only know our own fetch-script-written format works.
- Whether `attest_runtime.py`'s `MIN_BINARY_SIZE = 10 KiB` threshold
  is too low. A stripped helios_player binary is several MB; an
  rcssserver binary is similar. 10 KiB catches every stub we have
  written so far without false-positive risk on a real build.

## Intentionally NOT done

- Inlining `EXTERNALS.lock` into every `metadata.json`. The
  aggregator already pulls the commit hashes through
  `reality_evidence.externals_commits`; we don't yet duplicate them
  per match. Phase 3 can revisit if downstream reports demand it.
- Versioning the attestation evidence schema separately from
  metadata's `schema_version`. Today `reality_evidence` rides under
  the metadata schema; if/when the evidence set grows, splitting may
  be worth it.
- Performance evaluation. Still forbidden under `SMOKE_ONLY`.

## Updated path to `RESEARCH_GRADE`

The Phase 2.5 sequence is unchanged; one new explicit check sits in
the middle:

1. `make fetch-externals && make build-externals` on a Linux dev box.
2. Commit `externals/EXTERNALS.lock` with the resolved commits.
3. Edit `experiments/cyrus_vs_cyrus_smoke.yaml`: remove the
   `UNVERIFIED:` prefixes on the two start commands and point them at
   `externals/src/cyrus2dbase/start.sh` (or wherever Cyrus2DBase
   actually lands its launcher).
4. `make real-smoke`. Confirm in `metadata.json` that
   `observed_reality_status == real_rcssserver` and
   `reality_evidence.server_binary_under_externals_install == true`.
   **This is the new acceptance gate.**
5. `make real-smoke NUM_MATCHES=3`. Confirm
   `summary.run_reality_status == real_rcssserver` and
   `run_reality_block_reasons == []`.
6. `make real-smoke NUM_MATCHES=30`. `sample_regime` flips to
   `RESEARCH_GRADE`; CI bounds become quotable per
   `docs/EVALUATION_PROTOCOL.md`.

Until step 4 prints both required evidence fields, the harness will
keep saying SMOKE_ONLY no matter how many matches run.
