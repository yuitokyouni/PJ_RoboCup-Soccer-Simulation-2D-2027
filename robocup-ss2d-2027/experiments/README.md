# Experiments

Each YAML file in this directory describes one experiment the harness
can run via `make batch EXPERIMENT=experiments/<name>.yaml`.

## File shape

Every experiment YAML must define:

| Field                         | Meaning                                                          |
|-------------------------------|------------------------------------------------------------------|
| `schema_version`              | YAML schema version, currently `"0.1.0"`.                       |
| `experiment_id`               | Short slug used as the run-dir name under `logs/experiments/`.   |
| `description`                 | One- or two-sentence human description.                         |
| `home_team` / `away_team`     | Team names for the metadata.                                    |
| `home_start_command` / `away_start_command` | Executable that launches each side. `UNVERIFIED:` prefix means the harness will refuse to execute it; the match becomes `dependency_missing`. |
| `num_matches`                 | Default match count. Overridable by `NUM_MATCHES=`.             |
| `timeout_secs`                | Per-match wall-clock cap. Overridable by `TIMEOUT=`.            |
| `declared_reality_assertion`  | `synthetic_or_stubbed` (default) or `real_rcssserver`. A YAML self-declaration is not enough; see `docs/REALITY_ATTESTATION.md`. |
| `server_options`              | List of `server::namespace[::sub]=value` strings. Entries beginning with `UNVERIFIED:` or failing the option-shape regex are stripped, and the stripped reasons land in `experiment.json::declared_server_options_filter_notes`. |
| `notes`                       | Free-form operator notes; recorded verbatim into `experiment.json`. |

## Naming convention

`experiments/<contrast>_smoke.yaml` for verification runs (small N,
`SMOKE_ONLY` regime); `experiments/<contrast>.yaml` for production
batches (N ≥ 30 intended). Examples:

- `baseline_smoke.yaml` — single-match harness sanity check
  (synthetic).
- `baseline_vs_baseline.yaml` — Phase 2 batch sanity check
  (intentionally `UNVERIFIED:` on start commands).
- `cyrus_vs_cyrus_smoke.yaml` — Phase 2.5/2.6 real-integration
  spike (1–3 matches against the real `rcssserver` +
  `cyrus2dbase` built by `make build-externals`).

## Result location

Output lands under `logs/experiments/<experiment_id>/`:

```
logs/experiments/<experiment_id>/
  experiment.json
  matches/match_NNNNNN/
    metadata.json
    metrics.json
    server.out
    *.rcg, *.rcl
  summary.csv
  summary.json
```

`logs/experiments/` is in `.gitignore`; only the per-experiment YAML
lives in the repo. Notes documenting a real run should record the run
directory path and the four external commits from
`externals/EXTERNALS.lock`.

## Pre-flight before running

```sh
make doctor            # required binaries
make probe             # rcssserver inspection
make test              # attestation self-tests
```

## Defining a new experiment

1. Copy the closest existing YAML (most likely
   `cyrus_vs_cyrus_smoke.yaml`).
2. Rename `experiment_id` (slug, no spaces).
3. Edit `home_start_command` / `away_start_command` to point at the
   real `start.sh` you have built.
4. Set `declared_reality_assertion: real_rcssserver` only if you
   intend the run to be observed real; the aggregator will downgrade
   automatically if the attestation does not agree.
5. Add anything you genuinely want under `server_options`. Leave
   `UNVERIFIED:` prefixes on entries you have not exercised yet — the
   batch runner records but does not apply them.

## Don't

- Add experiments that change agent behavior; that belongs in the
  team source, not in the harness.
- Carry secrets in YAML — the file is committed.
- Reuse an `experiment_id` for a different contrast; create a new
  slug so the run dir is fresh.
