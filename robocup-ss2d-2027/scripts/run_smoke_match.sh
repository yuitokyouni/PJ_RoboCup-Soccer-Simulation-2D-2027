#!/usr/bin/env bash
# run_smoke_match.sh - run a single baseline-vs-baseline match end-to-end.
#
# Phase 1 goal: produce a reproducible run directory under logs/runs/<TS>/
# containing the server output, the .rcg / .rcl logs, metadata.json (what
# the harness ran and how it ended), and metrics.json (what the parser
# extracted). This script is *not* a tournament runner; for batch
# evaluation see Phase 2.
set -euo pipefail

usage() {
  cat <<'EOF'
run_smoke_match.sh - run a single baseline-vs-baseline smoke match

Usage:
  run_smoke_match.sh [--help] [--timeout SECONDS] [--run-dir PATH]
                     [--server-option KEY=VALUE]...
                     [--declared-reality-assertion REALITY]

Options:
  --timeout SECONDS  Hard wall-clock cap for the match. Default: 120
                     (overridable by env TIMEOUT_SECS). The server is run
                     under `timeout --kill-after=5`; on timeout the
                     metadata.json is marked match_status="timeout".
  --run-dir PATH     Use PATH as the run directory instead of generating
                     one under logs/runs/<UTC-timestamp>/. The directory
                     is created if missing. Intended for callers (e.g.
                     scripts/run_batch_matches.sh) that own their own
                     output layout. The basename of PATH becomes
                     metadata.json::run_id.
  --server-option KEY=VALUE
                     Appended verbatim to the rcssserver command line
                     after the harness's required runtime options.
                     May be passed multiple times. Recorded in
                     metadata.json::applied_server_options alongside
                     those required options.
  --declared-reality-assertion REALITY
                     One of 'synthetic_or_stubbed' (default) or
                     'real_rcssserver'. Recorded in
                     metadata.json::declared_reality_assertion. The smoke
                     runner does NOT verify the assertion; it calls
                     scripts/attest_runtime.py after the match and
                     writes the observed verdict to
                     metadata.json::observed_reality_status. See
                     docs/REALITY_ATTESTATION.md.

Environment:
  HELIOS_BASE_DIR  Directory of a built helios-base checkout.
                   Required unless HOME_TEAM_START / AWAY_TEAM_START are set.
  HOME_TEAM_START  Executable that launches the home team.
                   Default: $HELIOS_BASE_DIR/src/start.sh
  AWAY_TEAM_START  Executable that launches the away team.
                   Default: same as HOME_TEAM_START
  RCSS_PORT        rcssserver port. Default: 6000
  TIMEOUT_SECS     Match wall-clock cap in seconds. Default: 120

Output (under logs/runs/<UTC-timestamp>/):
  server.out      rcssserver stdout/stderr
  *.rcg           game log (binary, only if the match progressed)
  *.rcl           text log (only if the match progressed)
  metadata.json   runtime metadata, always written; includes match_status
  metrics.json    machine-readable match result (only when a .rcg exists)

match_status (in metadata.json):
  dependency_missing       a required tool / start script was not found
  server_failed_to_start   rcssserver exited non-zero before a match ran
  teams_failed_to_start    server ran cleanly but produced no .rcg
  match_completed          server exited cleanly and a .rcg was produced
  timeout                  hard wall-clock cap hit; processes killed
  unknown_failure          script died for a reason not covered above

Exit status:
  0  match_completed
  1  any other match_status, or rcssserver / python3 not in PATH
EOF
}

TIMEOUT_SECS="${TIMEOUT_SECS:-120}"
RUN_DIR_OVERRIDE=""
EXTRA_SERVER_OPTIONS=()
DECLARED_REALITY="synthetic_or_stubbed"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --timeout) shift; [[ $# -gt 0 ]] || { echo "--timeout needs a value" >&2; exit 2; }; TIMEOUT_SECS="$1"; shift ;;
    --timeout=*) TIMEOUT_SECS="${1#*=}"; shift ;;
    --run-dir) shift; [[ $# -gt 0 ]] || { echo "--run-dir needs a value" >&2; exit 2; }; RUN_DIR_OVERRIDE="$1"; shift ;;
    --run-dir=*) RUN_DIR_OVERRIDE="${1#*=}"; shift ;;
    --server-option) shift; [[ $# -gt 0 ]] || { echo "--server-option needs a value" >&2; exit 2; }; EXTRA_SERVER_OPTIONS+=("$1"); shift ;;
    --server-option=*) EXTRA_SERVER_OPTIONS+=("${1#*=}"); shift ;;
    --declared-reality-assertion) shift; [[ $# -gt 0 ]] || { echo "--declared-reality-assertion needs a value" >&2; exit 2; }; DECLARED_REALITY="$1"; shift ;;
    --declared-reality-assertion=*) DECLARED_REALITY="${1#*=}"; shift ;;
    *) echo "run_smoke_match.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$TIMEOUT_SECS" =~ ^[1-9][0-9]*$ ]] \
  || { echo "run_smoke_match.sh: --timeout must be a positive integer, got '$TIMEOUT_SECS'" >&2; exit 2; }
case "$DECLARED_REALITY" in
  synthetic_or_stubbed|real_rcssserver) ;;
  *) echo "run_smoke_match.sh: --declared-reality-assertion must be 'synthetic_or_stubbed' or 'real_rcssserver', got '$DECLARED_REALITY'" >&2; exit 2 ;;
esac

die() { echo "[smoke] ERROR: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Critical deps must be present even to set up a run dir.
command -v rcssserver >/dev/null 2>&1 \
  || die "rcssserver not in PATH. Run 'make doctor' and see setup/SETUP.md."
command -v python3 >/dev/null 2>&1 \
  || die "python3 not in PATH (needed for the result parser)."
command -v timeout >/dev/null 2>&1 \
  || die "GNU 'timeout' not in PATH (needed to bound the match wall clock)."
command -v setsid >/dev/null 2>&1 \
  || die "'setsid' not in PATH (needed to clean up the rcssserver process tree)."

BIN="$(command -v rcssserver)"

# Capture server version once, tolerantly.
SERVER_VERSION="$(
  { "$BIN" --version 2>&1 || true; } | head -n1
)"
if [[ -z "$SERVER_VERSION" || "$SERVER_VERSION" =~ [Uu]nrecognized|[Ii]nvalid ]]; then
  SERVER_VERSION="$(
    { "$BIN" -V 2>&1 || true; } | head -n1
  )"
fi
if [[ -z "$SERVER_VERSION" || "$SERVER_VERSION" =~ [Uu]nrecognized|[Ii]nvalid ]]; then
  SERVER_VERSION="unknown"
fi

HOME_TEAM_START="${HOME_TEAM_START:-${HELIOS_BASE_DIR:+$HELIOS_BASE_DIR/src/start.sh}}"
AWAY_TEAM_START="${AWAY_TEAM_START:-$HOME_TEAM_START}"
RCSS_PORT="${RCSS_PORT:-6000}"
CREATED_AT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -n "$RUN_DIR_OVERRIDE" ]]; then
  # Caller (e.g. the batch runner) supplied a dir. Use it verbatim; the
  # basename becomes the run_id so a match dir like
  # logs/experiments/<exp>/matches/match_000001/ surfaces as run_id
  # "match_000001" in metadata.json.
  RUN_DIR="$RUN_DIR_OVERRIDE"
  TS="$(basename "$RUN_DIR")"
else
  TS="$(date -u +%Y-%m-%dT%H%M%SZ)"
  RUN_DIR="$ROOT/logs/runs/$TS"
fi
mkdir -p "$RUN_DIR"

# The harness's required runtime options (paths, port, team-launch
# wiring). Caller-supplied --server-option flags are appended after, so
# they can in principle override anything except what rcssserver itself
# de-duplicates.
SERVER_OPTIONS=(
  "server::game_log_dir=$RUN_DIR"
  "server::text_log_dir=$RUN_DIR"
  "server::game_log_compression=0"
  "server::auto_mode=true"
  "server::port=$RCSS_PORT"
  "server::team_l_start=$HOME_TEAM_START"
  "server::team_r_start=$AWAY_TEAM_START"
)
if (( ${#EXTRA_SERVER_OPTIONS[@]} > 0 )); then
  SERVER_OPTIONS+=("${EXTRA_SERVER_OPTIONS[@]}")
fi

MATCH_STATUS="unknown_failure"
SERVER_PID=""

write_metadata() {
  # Merge-write: read any existing metadata, overwrite the core fields
  # this runner owns, leave any other keys (notably the attestation
  # fields added by scripts/attest_runtime.py) intact. The EXIT trap
  # calls this again, so attestation must survive the re-write.
  python3 - \
    "$RUN_DIR/metadata.json" \
    "$TS" \
    "$CREATED_AT_UTC" \
    "$BIN" \
    "$SERVER_VERSION" \
    "$HOME_TEAM_START" \
    "$AWAY_TEAM_START" \
    "$TIMEOUT_SECS" \
    "$MATCH_STATUS" \
    "$DECLARED_REALITY" \
    "${SERVER_OPTIONS[@]}" <<'PYEOF'
import json, os, sys
(path, run_id, created_at, binary, version,
 home_cmd, away_cmd, timeout_secs, match_status,
 declared_reality, *opts) = sys.argv[1:]
existing = {}
if os.path.exists(path):
    try:
        existing = json.loads(open(path).read())
    except (json.JSONDecodeError, OSError):
        existing = {}
existing.update({
    "schema_version":             "1.3",
    "run_id":                     run_id,
    "created_at_utc":             created_at,
    "server_binary":              binary,
    "server_version":             version,
    "applied_server_options":     opts,
    "declared_reality_assertion": declared_reality,
    "home_start_command":         home_cmd,
    "away_start_command":         away_cmd,
    "timeout_secs":               int(timeout_secs),
    "match_status":               match_status,
})
with open(path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
PYEOF
}

cleanup_processes() {
  # SERVER_PID is the session leader (setsid), so PGID == PID. Kill the
  # whole process group so player/coach/trainer children die with it.
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM -"$SERVER_PID" 2>/dev/null || true
    sleep 0.5
    kill -KILL -"$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}

on_exit() {
  local rc=$?
  cleanup_processes
  if [[ -d "$RUN_DIR" ]]; then
    write_metadata 2>>"$RUN_DIR/server.out" || true
  fi
  trap - EXIT INT TERM
  exit "$rc"
}

trap on_exit EXIT
trap 'echo "[smoke] caught signal; cleaning up" >&2; exit 130' INT TERM

# Write metadata once up front so a very-early crash still leaves a record.
write_metadata

# dependency_missing: start scripts not usable.
if [[ -z "$HOME_TEAM_START" || ! -x "$HOME_TEAM_START" ]]; then
  MATCH_STATUS="dependency_missing"
  die "HOME_TEAM_START not executable: '$HOME_TEAM_START'. Set HELIOS_BASE_DIR or HOME_TEAM_START."
fi
if [[ ! -x "$AWAY_TEAM_START" ]]; then
  MATCH_STATUS="dependency_missing"
  die "AWAY_TEAM_START not executable: '$AWAY_TEAM_START'. Set AWAY_TEAM_START."
fi

echo "[smoke] run dir:         $RUN_DIR"
echo "[smoke] rcssserver:      $BIN ($SERVER_VERSION)"
echo "[smoke] timeout:         ${TIMEOUT_SECS}s"
echo "[smoke] home team start: $HOME_TEAM_START"
echo "[smoke] away team start: $AWAY_TEAM_START"
echo "[smoke] starting rcssserver on port $RCSS_PORT"

# NOTE: the auto_mode + team_l_start / team_r_start triple has been the
# canonical way to drive an unattended match for many rcssserver versions,
# but this exact invocation has not been verified against rcssserver-18.
# See setup/SERVER_CONTRACT.md for the running tally.
setsid timeout --kill-after=5 "$TIMEOUT_SECS" \
  "$BIN" "${SERVER_OPTIONS[@]}" \
  > "$RUN_DIR/server.out" 2>&1 &
SERVER_PID=$!

if wait "$SERVER_PID"; then
  SERVER_RC=0
else
  SERVER_RC=$?
fi

RCG="$(find "$RUN_DIR" -maxdepth 1 \( -name '*.rcg' -o -name '*.rcg.gz' \) | head -n1 || true)"
RCL="$(find "$RUN_DIR" -maxdepth 1 -name '*.rcl' | head -n1 || true)"

# Determine match_status from (server exit code, log presence).
# timeout(1) returns 124 on time-out, 137 on KILL after --kill-after.
if (( SERVER_RC == 124 || SERVER_RC == 137 )); then
  MATCH_STATUS="timeout"
elif (( SERVER_RC != 0 )); then
  MATCH_STATUS="server_failed_to_start"
elif [[ -z "$RCG" ]]; then
  MATCH_STATUS="teams_failed_to_start"
else
  MATCH_STATUS="match_completed"
fi

# Refresh metadata so it reflects the determined status before the parser
# runs (the parser does not consume match_status, but a forensic reader
# expecting an up-to-date file will see the right value).
write_metadata

# Attestation runs regardless of match outcome -- the evidence schema
# is also useful for explaining why a failed match was not real.
python3 "$ROOT/scripts/attest_runtime.py" --run-dir "$RUN_DIR" >/dev/null \
  || echo "[smoke] WARN: attest_runtime.py exited non-zero; metadata.json may lack observed_reality_status" >&2

if [[ "$MATCH_STATUS" != "match_completed" ]]; then
  echo "[smoke] match_status: $MATCH_STATUS" >&2
  echo "[smoke] tail of server.out:" >&2
  tail -n 40 "$RUN_DIR/server.out" >&2 || true
  exit 1
fi

python3 "$ROOT/evaluation/parse_match_result.py" \
  --run-dir "$RUN_DIR" \
  --rcg "$RCG" \
  ${RCL:+--rcl "$RCL"} \
  --output "$RUN_DIR/metrics.json" \
  --notes "smoke test"

# Best-effort tactical report. Failure here must not abort the smoke
# (the harness's other deliverables -- rcg, rcl, metrics.json -- are
# already written and committed).
if [[ -n "$RCL" && -f "$RCL" ]]; then
  python3 "$ROOT/scripts/match_report.py" "$RUN_DIR" 2>&1 \
    | sed 's/^/[smoke] match_report: /' \
    || echo "[smoke] match_report: generation failed (non-fatal)"
fi

echo "[smoke] match_status: $MATCH_STATUS"
echo "[smoke] done: $RUN_DIR/metrics.json"
echo "[smoke]       $RUN_DIR/metadata.json"
