#!/usr/bin/env bash
# doctor.sh - check that the required external tools for the harness are
# installed and on PATH. Does not install anything.
set -euo pipefail

usage() {
  cat <<'EOF'
doctor.sh - check required external dependencies for the harness

Usage:
  doctor.sh [--help]

Checks (required unless noted):
  - rcssserver
  - rcssmonitor          (optional, GUI)
  - librcsc              (via rcsc-config or pkg-config librcsc)
  - helios-base players  (helios_player, helios_coach, helios_trainer)
  - python3
  - timeout              (GNU coreutils; bounds smoke match wall clock)
  - setsid               (util-linux; lets the harness kill the process tree)
  - jq                   (optional, used for metrics inspection)

Exit status:
  0  all required dependencies present
  1  one or more required dependencies missing

On a missing dependency, doctor prints the canonical source URL so the user
can follow setup/SETUP.md.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "doctor.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

missing=0
optional_missing=0

note() { echo "[doctor] ok: $*"; }
miss_req() { echo "[doctor] MISSING (required): $*" >&2; missing=$((missing+1)); }
miss_opt() { echo "[doctor] missing (optional): $*"; optional_missing=$((optional_missing+1)); }

check_required() {
  local bin="$1" hint="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    note "$bin -> $(command -v "$bin")"
  else
    miss_req "$bin (install: $hint)"
  fi
}

check_optional() {
  local bin="$1" hint="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    note "$bin -> $(command -v "$bin")"
  else
    miss_opt "$bin (install: $hint)"
  fi
}

check_required rcssserver    "https://github.com/rcsoccersim/rcssserver"
check_optional rcssmonitor   "https://github.com/rcsoccersim/rcssmonitor"
check_required python3       "system package manager"
check_required timeout       "system package manager (GNU coreutils)"
check_required setsid        "system package manager (util-linux)"
check_optional jq            "system package manager"

for b in helios_player helios_coach helios_trainer; do
  check_required "$b" "build helios-base: https://github.com/helios-base/helios-base"
done

if command -v rcsc-config >/dev/null 2>&1; then
  note "librcsc detected via rcsc-config ($(command -v rcsc-config))"
elif pkg-config --exists librcsc 2>/dev/null; then
  note "librcsc detected via pkg-config"
else
  miss_req "librcsc (build: https://github.com/helios-base/librcsc)"
fi

if (( missing > 0 )); then
  echo
  echo "[doctor] $missing required dependency check(s) failed."
  echo "[doctor] See setup/SETUP.md and setup/DEPENDENCIES.md."
  exit 1
fi

if (( optional_missing > 0 )); then
  echo "[doctor] all required deps present; $optional_missing optional missing."
else
  echo "[doctor] all dependencies present."
fi
