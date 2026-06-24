#!/usr/bin/env bash
# run_batch_matches.sh - run N smoke matches under one experiment id and
# fold the per-match outputs into summary.csv / summary.json.
#
# Phase 2 contract:
#   - Serial execution.
#   - Resumable: skip matches that already have metrics.json unless --force.
#   - Failure-tolerant: a failed match never stops the batch.
#   - Output layout:
#       logs/experiments/<experiment_id>/
#         experiment.json
#         matches/match_000001/
#           server.out, *.rcg, *.rcl, metadata.json, metrics.json
#         summary.csv
#         summary.json
set -euo pipefail

usage() {
  cat <<'EOF'
run_batch_matches.sh - run an N-match experiment under one experiment_id

Usage:
  run_batch_matches.sh --experiment PATH [--num-matches N]
                       [--timeout SECONDS] [--force] [--dry-run] [--help]

Required:
  --experiment PATH    Path to a YAML experiment definition. Required keys:
                       experiment_id, num_matches, timeout_secs,
                       home_start_command, away_start_command.

Optional overrides:
  --num-matches N      Override yaml.num_matches.
  --timeout SECONDS    Override yaml.timeout_secs.
  --force              Re-run matches whose metrics.json already exists
                       (their directory is wiped first).
  --dry-run            Resolve config, write experiment.json, list what
                       would be run, then exit. No matches are executed
                       and no aggregation runs.

Output (under logs/experiments/<experiment_id>/):
  experiment.json      merged config + runtime context (start/end, counts)
  matches/match_NNNNNN/ per-match dir written by run_smoke_match.sh
  summary.csv          per-match table (written by aggregate_results.py)
  summary.json         aggregate (status counts, mean_goal_diff, ci95, ...)

Exit status:
  0  batch ran to completion (regardless of individual match outcomes)
  1  fatal setup error (bad yaml, missing python deps, missing files)
EOF
}

EXPERIMENT_PATH=""
NUM_MATCHES_OVERRIDE=""
TIMEOUT_OVERRIDE=""
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --experiment) shift; EXPERIMENT_PATH="${1:-}"; shift ;;
    --experiment=*) EXPERIMENT_PATH="${1#*=}"; shift ;;
    --num-matches) shift; NUM_MATCHES_OVERRIDE="${1:-}"; shift ;;
    --num-matches=*) NUM_MATCHES_OVERRIDE="${1#*=}"; shift ;;
    --timeout) shift; TIMEOUT_OVERRIDE="${1:-}"; shift ;;
    --timeout=*) TIMEOUT_OVERRIDE="${1#*=}"; shift ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "run_batch_matches.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "[batch] ERROR: $*" >&2; exit 1; }

[[ -n "$EXPERIMENT_PATH" ]] || { usage >&2; die "--experiment is required"; }
[[ -f "$EXPERIMENT_PATH" ]] || die "experiment file not found: $EXPERIMENT_PATH"

command -v python3 >/dev/null 2>&1 || die "python3 not in PATH"
python3 -c "import yaml" >/dev/null 2>&1 \
  || die "python3 yaml module missing; install with: pip install pyyaml"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="$ROOT/scripts/run_smoke_match.sh"
AGGREGATE="$ROOT/evaluation/aggregate_results.py"
[[ -x "$SMOKE" ]] || die "$SMOKE not executable"
[[ -f "$AGGREGATE" ]] || die "$AGGREGATE not found"

# Parse YAML -> JSON once, then read individual fields from that JSON so
# we never re-shell into yaml.safe_load.
YAML_JSON="$(python3 -c "import sys, yaml, json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$EXPERIMENT_PATH")"

# Read a top-level scalar field with a default. We invoke python once per
# call because the values may contain shell-significant characters; this
# is fine at config-load time.
yaml_get() {
  python3 -c "
import json, sys
d = json.loads(sys.argv[1]) or {}
v = d.get(sys.argv[2])
sys.stdout.write('' if v is None else str(v))
" "$YAML_JSON" "$1"
}

EXP_ID="$(yaml_get experiment_id)"
[[ -n "$EXP_ID" ]] || die "yaml missing experiment_id"
NUM_MATCHES="${NUM_MATCHES_OVERRIDE:-$(yaml_get num_matches)}"
TIMEOUT_SECS="${TIMEOUT_OVERRIDE:-$(yaml_get timeout_secs)}"
HOME_CMD="$(yaml_get home_start_command)"
AWAY_CMD="$(yaml_get away_start_command)"

[[ -n "$NUM_MATCHES" ]] || die "num_matches not set (yaml or --num-matches)"
[[ -n "$TIMEOUT_SECS" ]] || die "timeout_secs not set (yaml or --timeout)"
[[ "$NUM_MATCHES" =~ ^[1-9][0-9]*$ ]] \
  || die "num_matches must be a positive integer, got '$NUM_MATCHES'"
[[ "$TIMEOUT_SECS" =~ ^[1-9][0-9]*$ ]] \
  || die "timeout_secs must be a positive integer, got '$TIMEOUT_SECS'"

# yaml.declared_reality_assertion (default synthetic_or_stubbed).
# Validated here so a malformed value is caught before any match runs.
DECLARED_REALITY="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]) or {}; v=d.get("declared_reality_assertion") or "synthetic_or_stubbed"; sys.stdout.write(v)' "$YAML_JSON")"
case "$DECLARED_REALITY" in
  synthetic_or_stubbed|real_rcssserver) ;;
  *) die "yaml declared_reality_assertion must be 'synthetic_or_stubbed' or 'real_rcssserver', got '$DECLARED_REALITY'" ;;
esac

# Filter yaml.server_options: strip entries that begin with "UNVERIFIED:"
# or fail the server::namespace[::sub]=value shape. The stripped entries
# are recorded in experiment.json::declared_server_options_filter_notes
# and the union of unapplied options surfaces in summary.json. See
# docs/REAL_INTEGRATION.md for why this split exists.
FILTER_JSON="$(python3 - "$YAML_JSON" <<'PYEOF'
import json, re, sys
d = json.loads(sys.argv[1]) or {}
declared = d.get("server_options") or []
SHAPE = re.compile(r'^server::[A-Za-z_][A-Za-z_0-9]*(::[A-Za-z_][A-Za-z_0-9]*)?=.+$')
kept, notes = [], []
for o in declared:
    if not isinstance(o, str):
        notes.append(f"stripped non-string server_options entry: {o!r}")
        continue
    if o.startswith("UNVERIFIED:"):
        notes.append(f"stripped UNVERIFIED-prefixed server_options entry: {o}")
        continue
    if not SHAPE.match(o):
        notes.append(f"stripped malformed server_options entry: {o!r}")
        continue
    kept.append(o)
print(json.dumps({"declared": declared, "kept": kept, "filter_notes": notes}))
PYEOF
)"
KEPT_SERVER_OPTIONS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && KEPT_SERVER_OPTIONS+=("$line")
done < <(python3 -c 'import json,sys; [print(o) for o in json.loads(sys.argv[1])["kept"]]' "$FILTER_JSON")

EXP_DIR="$ROOT/logs/experiments/$EXP_ID"
mkdir -p "$EXP_DIR/matches"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_experiment_json() {
  # ended_at / counts may be empty during the initial write and filled in
  # at the end of the loop; we pass them as positional args so Python
  # never has to re-shell into bash.
  local ended_at="$1" run="$2" skipped="$3" total_seen="$4"
  python3 - \
    "$EXP_DIR/experiment.json" \
    "$EXP_ID" "$EXPERIMENT_PATH" "$YAML_JSON" \
    "$STARTED_AT" "$ended_at" \
    "$NUM_MATCHES" "$TIMEOUT_SECS" \
    "$FORCE" "$DRY_RUN" \
    "$run" "$skipped" "$total_seen" \
    "$DECLARED_REALITY" \
    "$FILTER_JSON" <<'PYEOF'
import json, sys
(path, exp_id, yaml_source, yaml_json,
 started_at, ended_at,
 num_matches, timeout_secs,
 force, dry_run,
 num_run, num_skipped, num_seen,
 declared_reality, filter_json) = sys.argv[1:]
def _maybe_int(s):
    try: return int(s)
    except ValueError: return None
filt = json.loads(filter_json)
data = {
    "schema_version": "0.2.0",
    "experiment_id": exp_id,
    "yaml_source": yaml_source,
    "yaml_content": json.loads(yaml_json),
    "declared_reality_assertion": declared_reality,
    "declared_server_options": filt["declared"],
    "applied_server_options_subset": filt["kept"],
    "declared_server_options_filter_notes": filt["filter_notes"],
    "runtime": {
        "started_at_utc": started_at,
        "ended_at_utc": ended_at or None,
        "num_matches_requested": int(num_matches),
        "timeout_secs": int(timeout_secs),
        "force": force == "true",
        "dry_run": dry_run == "true",
        "num_matches_run": _maybe_int(num_run) if num_run else None,
        "num_matches_skipped": _maybe_int(num_skipped) if num_skipped else None,
        "num_match_dirs_seen": _maybe_int(num_seen) if num_seen else None,
    },
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
}

# Initial write so a crash mid-loop still leaves the config record.
write_experiment_json "" "" "" ""

echo "[batch] experiment_id:    $EXP_ID"
echo "[batch] num_matches:      $NUM_MATCHES"
echo "[batch] timeout_secs:     $TIMEOUT_SECS"
echo "[batch] home_command:     $HOME_CMD"
echo "[batch] away_command:     $AWAY_CMD"
echo "[batch] declared_reality:  $DECLARED_REALITY"
echo "[batch] kept server_options: ${#KEPT_SERVER_OPTIONS[@]} (filter_notes recorded in experiment.json)"
echo "[batch] experiment_dir:   $EXP_DIR"
[[ "$FORCE"   == true ]] && echo "[batch] --force: re-running completed matches"
[[ "$DRY_RUN" == true ]] && echo "[batch] --dry-run: no matches will be executed"

NUM_RUN=0
NUM_SKIPPED=0

for i in $(seq 1 "$NUM_MATCHES"); do
  MATCH_ID=$(printf "match_%06d" "$i")
  MATCH_DIR="$EXP_DIR/matches/$MATCH_ID"

  if [[ -f "$MATCH_DIR/metrics.json" && "$FORCE" != true ]]; then
    echo "[batch] skip  $MATCH_ID  (already has metrics.json)"
    NUM_SKIPPED=$((NUM_SKIPPED + 1))
    continue
  fi

  if [[ "$FORCE" == true && -d "$MATCH_DIR" ]]; then
    rm -rf "$MATCH_DIR"
  fi
  mkdir -p "$MATCH_DIR"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[batch] DRY   $MATCH_ID  (would call run_smoke_match.sh --run-dir $MATCH_DIR)"
    continue
  fi

  # Build the --server-option flag list. Empty arrays expand to nothing
  # under set -u, so an experiment with no kept options is fine.
  SMOKE_EXTRA_FLAGS=()
  for opt in ${KEPT_SERVER_OPTIONS[@]+"${KEPT_SERVER_OPTIONS[@]}"}; do
    SMOKE_EXTRA_FLAGS+=(--server-option "$opt")
  done

  echo "[batch] run   $MATCH_ID"
  # The smoke runner returns non-zero on any non-match_completed outcome.
  # We intentionally ignore that: the batch must continue and the truth
  # lives in MATCH_DIR/metadata.json::match_status.
  HOME_TEAM_START="$HOME_CMD" AWAY_TEAM_START="$AWAY_CMD" \
    bash "$SMOKE" \
      --timeout "$TIMEOUT_SECS" \
      --run-dir "$MATCH_DIR" \
      --declared-reality-assertion "$DECLARED_REALITY" \
      ${SMOKE_EXTRA_FLAGS[@]+"${SMOKE_EXTRA_FLAGS[@]}"} \
    || true
  NUM_RUN=$((NUM_RUN + 1))
done

ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TOTAL_SEEN=$(find "$EXP_DIR/matches" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
write_experiment_json "$ENDED_AT" "$NUM_RUN" "$NUM_SKIPPED" "$TOTAL_SEEN"

if [[ "$DRY_RUN" == true ]]; then
  echo "[batch] dry run complete. $NUM_MATCHES match(es) would have been considered."
  exit 0
fi

python3 "$AGGREGATE" --experiment-dir "$EXP_DIR" > /dev/null

# Print the part of summary.json that actually answers question 1:
# "was the run real?" -- before any score talk.
python3 - "$EXP_DIR/summary.json" <<'PYEOF'
import json, sys
s = json.load(open(sys.argv[1]))
print(f"[batch] sample_regime: {s.get('sample_regime')}")
print(f"[batch] completed_matches: {s.get('completed_matches')} / {s.get('total_matches')}")
print("[batch] match_status_counts:")
for k, v in (s.get("match_status_counts") or {}).items():
    print(f"  {k}: {v}")
PYEOF

echo "[batch] done: $EXP_DIR/summary.json"
echo "[batch]       $EXP_DIR/summary.csv"
