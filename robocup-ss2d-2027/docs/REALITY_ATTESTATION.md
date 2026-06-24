# Reality Attestation

Phase 2.5 made the harness honest about declared vs applied options.
Phase 2.6 makes it honest about declared vs **observed** reality.

## Why this exists

Phase 2.5 promoted `run_reality_status` to `real_rcssserver` based on
the operator's `reality_assertion` in YAML plus a few config checks.
That is unsafe: a stand-in rcssserver used in CI (a 200-byte bash
script in `/tmp/`) can technically pass those checks. A YAML
self-declaration is not evidence.

Phase 2.6 splits the claim from the observation:

| Field                          | Source                                          | Layer       |
|--------------------------------|-------------------------------------------------|-------------|
| `declared_reality_assertion`   | YAML / batch CLI                                | experiment + match |
| `observed_reality_status`      | `scripts/attest_runtime.py` after each match    | match       |
| `run_reality_status`           | aggregator, combining declared + observed       | summary     |

Promotion ladder:

    declared = real  AND  observed = real for every completed match
              AND  unapplied_server_options == []
              AND  completed_matches > 0
              => run_reality_status = real_rcssserver
    any completed observation = synthetic_or_stubbed
              => run_reality_status = synthetic_or_stubbed
    otherwise => run_reality_status = unknown_or_unverified

`real_rcssserver` cannot be reached by writing a YAML field. Every
promotion requires runtime observation.

## What attestation checks

`scripts/attest_runtime.py` is called automatically by
`scripts/run_smoke_match.sh` after the match finishes. It reads the
run's `metadata.json`, gathers the facts below, and writes them back.

Required for `observed_reality_status = real_rcssserver`:

1. **Server binary identity.** `metadata.server_binary` resolves to a
   real file. The resolved path lives under
   `externals/install/bin/`. The file's first four bytes are the ELF
   magic `\x7fELF`. The file is larger than 10 KiB.
2. **Server version is not a known stub.** The `server_version`
   string contains none of `fake`, `stub`, `mock`, `dummy`
   (case-insensitive).
3. **External lock is present.** `externals/EXTERNALS.lock` exists
   and contains a line for `rcssserver` (one of the fields is the
   resolved commit hash).
4. **Logs are non-empty.** At least one `.rcg` (or `.rcg.gz`) and at
   least one `.rcl` under the run directory are larger than 0 bytes.
5. **Team start commands resolve.** Both `home_start_command` and
   `away_start_command` point at existing files. Anything starting
   with `UNVERIFIED:` fails this check by construction.

All of these together (plus declared = real, unapplied = [], any
completed match) flip `run_reality_status` to `real_rcssserver`.

## Stub detection

Some failures are not just "evidence missing" — they actively indicate
the binary is a stub. When any of these triggers,
`observed_reality_status` is `synthetic_or_stubbed`, **not**
`unknown_or_unverified`:

- Binary is not an ELF executable.
- Binary is smaller than 10 KiB.
- `server_version` contains a stub keyword.

The first batch of synthetic harness tests in this repository — fake
rcssserver bash scripts in `/tmp/` reporting version
`fake-rcssserver 18` — hit all three checks. They cannot accidentally
promote.

## Evidence schema (metadata.json, 1.3)

```jsonc
{
  "schema_version": "1.3",
  ...,
  "declared_reality_assertion": "real_rcssserver",        // from YAML / batch
  "observed_reality_status":    "real_rcssserver",        // from attest_runtime.py
  "reality_evidence": {
    "server_binary_realpath":   "...",
    "server_binary_size":       NNN,
    "server_binary_sha256":     "...",
    "server_binary_is_elf":     true,
    "server_binary_under_externals_install": true,
    "externals_lock_path":      "...",
    "externals_lock_present":   true,
    "externals_commits":        {"rcssserver": "...", "librcsc": "...", ...},
    "home_start_command_realpath": "...",
    "away_start_command_realpath": "...",
    "rcg_nonempty":             true,
    "rcl_nonempty":             true
  },
  "reality_evidence_missing": []
}
```

When a check fails, the relevant evidence field is `null` (or `false`)
and a human-readable reason appears in `reality_evidence_missing`.

## How the aggregator uses this

`evaluation/aggregate_results.py` produces `summary.json` (schema
0.3.0) with:

- `declared_reality_assertion` (from `experiment.json`).
- `observed_reality_status_counts` per-match histogram.
- `run_reality_status` per the promotion ladder above.
- `run_reality_block_reasons`: explanations, one per blocking check
  (matches with `observed_reality_status != real_rcssserver`, the
  union of their `reality_evidence_missing` lists, plus any
  declared-but-not-applied options).

`sample_regime` reaches `RESEARCH_GRADE` only when **all** of:

1. `completed_matches >= 30`
2. `run_reality_status == "real_rcssserver"`
3. Every completed match has
   `observed_reality_status == "real_rcssserver"`
4. `unapplied_server_options == []`
5. `unknown_results == 0`

Otherwise the regime is `SMOKE_ONLY`. The user-facing rule from
`docs/EVALUATION_PROTOCOL.md` (no strength claims under
`SMOKE_ONLY`) still holds.

## When attestation cannot run

If `metadata.json` is missing or unreadable, the smoke runner records
nothing and the aggregator falls back to `observed_reality_status =
unknown_or_unverified`. Aggregation always succeeds; the
`run_reality_block_reasons` field will name the gap.

## What an `UNVERIFIED:` prefix means now

An `UNVERIFIED:` prefix on a YAML `*_start_command` does double duty:

- The smoke runner refuses to execute it (the `[[ -x ]]` test fails),
  so the match is marked `dependency_missing`.
- Even if it slipped through (it cannot), attestation's "team start
  commands resolve" check would catch it, so the run would be
  `unknown_or_unverified`.

The marker is therefore safe to leave in a checked-in experiment
file. The harness will refuse to call the result real until both
gates open.
