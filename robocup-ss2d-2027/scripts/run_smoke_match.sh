#!/usr/bin/env bash
# run_smoke_match.sh - run a single baseline-vs-baseline match end-to-end.
#
# Phase 1 goal: produce a reproducible run directory under logs/runs/<TS>/
# containing the server output, the .rcg / .rcl logs, and a metrics.json.
# This script is *not* a tournament runner; for batch evaluation see Phase 2.
set -euo pipefail

usage() {
  cat <<'EOF'
run_smoke_match.sh - run a single baseline-vs-baseline smoke match

Usage:
  run_smoke_match.sh [--help]

Environment:
  HELIOS_BASE_DIR  Directory of a built helios-base checkout.
                   Required unless HOME_TEAM_START / AWAY_TEAM_START are set.
  HOME_TEAM_START  Executable that launches the home team.
                   Default: $HELIOS_BASE_DIR/src/start.sh
  AWAY_TEAM_START  Executable that launches the away team.
                   Default: same as HOME_TEAM_START
  RCSS_PORT        rcssserver port. Default: 6000

Output (under logs/runs/<UTC-timestamp>/):
  server.out    rcssserver stdout/stderr
  *.rcg         game log (binary)
  *.rcl         text log
  metrics.json  machine-readable match result

Exit status:
  0  match completed and metrics.json written
  1  required dependency missing or rcssserver produced no game log
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "run_smoke_match.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

die() { echo "[smoke] ERROR: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_DIR="$ROOT/logs/runs/$TS"
mkdir -p "$RUN_DIR"

command -v rcssserver >/dev/null 2>&1 \
  || die "rcssserver not in PATH. Run 'make doctor' and see setup/SETUP.md."
command -v python3 >/dev/null 2>&1 \
  || die "python3 not in PATH (needed for the result parser)."

HOME_TEAM_START="${HOME_TEAM_START:-${HELIOS_BASE_DIR:-}/src/start.sh}"
AWAY_TEAM_START="${AWAY_TEAM_START:-$HOME_TEAM_START}"

[[ -n "$HOME_TEAM_START" && -x "$HOME_TEAM_START" ]] \
  || die "HOME_TEAM_START not executable: '$HOME_TEAM_START'. Set HELIOS_BASE_DIR or HOME_TEAM_START."
[[ -n "$AWAY_TEAM_START" && -x "$AWAY_TEAM_START" ]] \
  || die "AWAY_TEAM_START not executable: '$AWAY_TEAM_START'. Set AWAY_TEAM_START."

RCSS_PORT="${RCSS_PORT:-6000}"

echo "[smoke] run dir:        $RUN_DIR"
echo "[smoke] home team start: $HOME_TEAM_START"
echo "[smoke] away team start: $AWAY_TEAM_START"
echo "[smoke] starting rcssserver on port $RCSS_PORT"

# NOTE: the auto_mode + team_l_start / team_r_start triple has been the
# canonical way to drive an unattended match for many rcssserver versions,
# but this exact invocation has not been verified against rcssserver-18 in
# this repo. If it breaks, fall back to launching teams manually with
# helios-base's start.sh and a stand-alone rcssserver in another shell.
rcssserver \
  server::game_log_dir="$RUN_DIR" \
  server::text_log_dir="$RUN_DIR" \
  server::game_log_compression=0 \
  server::auto_mode=true \
  server::port="$RCSS_PORT" \
  server::team_l_start="$HOME_TEAM_START" \
  server::team_r_start="$AWAY_TEAM_START" \
  > "$RUN_DIR/server.out" 2>&1 &
SERVER_PID=$!

cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

wait "$SERVER_PID" || true
trap - EXIT INT TERM

RCG="$(find "$RUN_DIR" -maxdepth 1 -name '*.rcg' -o -name '*.rcg.gz' | head -n1 || true)"
RCL="$(find "$RUN_DIR" -maxdepth 1 -name '*.rcl' | head -n1 || true)"

if [[ -z "$RCG" ]]; then
  echo "[smoke] tail of server.out:"
  tail -n 40 "$RUN_DIR/server.out" >&2 || true
  die "rcssserver did not produce a .rcg log. See $RUN_DIR/server.out."
fi

python3 "$ROOT/evaluation/parse_match_result.py" \
  --run-dir "$RUN_DIR" \
  --rcg "$RCG" \
  ${RCL:+--rcl "$RCL"} \
  --output "$RUN_DIR/metrics.json" \
  --notes "smoke test"

echo "[smoke] done: $RUN_DIR/metrics.json"
