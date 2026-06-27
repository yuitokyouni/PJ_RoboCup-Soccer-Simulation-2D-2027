#!/usr/bin/env bash
# probe_rcssserver.sh - inspect the installed rcssserver and the harness's
# assumptions about how to launch it. Read-only: does not start a match,
# does not modify any file.
set -euo pipefail

usage() {
  cat <<'EOF'
probe_rcssserver.sh - inspect rcssserver install + harness assumptions

Usage:
  probe_rcssserver.sh [--help]

Prints:
  - path to the rcssserver binary
  - version (if --version or -V is supported)
  - whether 'rcssserver --help' responds
  - which documented config files exist under $HOME
  - the command-line server::* options the harness plans to pass, with
    explicit UNVERIFIED markers for anything not yet exercised against
    the installed binary

Exit status:
  0  rcssserver found (probe ran)
  1  rcssserver not in PATH
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "probe_rcssserver.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

BIN="$(command -v rcssserver || true)"
if [[ -z "$BIN" ]]; then
  echo "[probe] rcssserver: NOT INSTALLED"
  echo "[probe] install:    https://github.com/rcsoccersim/rcssserver"
  echo "[probe] see also:   setup/SETUP.md, setup/DEPENDENCIES.md"
  exit 1
fi

echo "[probe] rcssserver path:     $BIN"

# Version probe: try --version, then -V. Tolerant of binaries that exit
# non-zero on either, or print nothing.
VERSION="$(
  { "$BIN" --version 2>&1 || true; } | head -n1
)"
if [[ -z "$VERSION" || "$VERSION" =~ [Uu]nrecognized|[Ii]nvalid ]]; then
  VERSION="$(
    { "$BIN" -V 2>&1 || true; } | head -n1
  )"
fi
if [[ -z "$VERSION" || "$VERSION" =~ [Uu]nrecognized|[Ii]nvalid ]]; then
  echo "[probe] rcssserver version:  unknown (binary did not respond to --version or -V)"
else
  echo "[probe] rcssserver version:  $VERSION"
fi

# --help probe: only needs to exit cleanly; don't print the body.
if "$BIN" --help </dev/null >/dev/null 2>&1; then
  echo "[probe] rcssserver --help:   responds"
else
  echo "[probe] rcssserver --help:   does NOT respond cleanly (older versions may not support --help)"
fi

# Config-file resolution. UNVERIFIED across rcssserver versions.
echo "[probe] HOME config files (documented lookup order; UNVERIFIED):"
for f in \
  "$HOME/.rcssserver-server.conf" \
  "$HOME/.rcssserver-player.conf" \
  "$HOME/.rcssserver-CSVSaver.conf"
do
  if [[ -f "$f" ]]; then
    echo "  exists:  $f"
  else
    echo "  absent:  $f"
  fi
done
echo "[probe] Explicit overrides: 'server::key=value' on the command line."
echo "[probe] The harness assumes command-line overrides win over config files (UNVERIFIED)."

# Launch options the harness will pass. Keep this in sync with run_smoke_match.sh.
cat <<'EOF'
[probe] Launch options that scripts/run_smoke_match.sh passes:
  server::game_log_dir=<run_dir>        [UNVERIFIED against rcssserver-18]
  server::text_log_dir=<run_dir>        [UNVERIFIED against rcssserver-18]
  server::game_log_compression=0        [UNVERIFIED against rcssserver-18]
  server::auto_mode=true                [canonical pattern; UNVERIFIED against rcssserver-18]
  server::port=<RCSS_PORT>              [stable across known versions]
  server::team_l_start=<home_start>     [canonical pattern; UNVERIFIED against rcssserver-18]
  server::team_r_start=<away_start>     [canonical pattern; UNVERIFIED against rcssserver-18]
[probe] See setup/SERVER_CONTRACT.md for rationale and verification status.
EOF
