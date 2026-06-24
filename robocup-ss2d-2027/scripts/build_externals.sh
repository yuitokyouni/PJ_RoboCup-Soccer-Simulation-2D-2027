#!/usr/bin/env bash
# build_externals.sh - build the previously-fetched RCSS2D externals into
# externals/install/. Pre-flights every required system package and
# fails clearly (no silent installation) if any are missing.
#
# Build order (set by dependencies):
#   1. librcsc      (client-side base; helios-base + cyrus2dbase need it)
#   2. rcssserver   (server; independent of the team baselines)
#   3. helios-base  (optional historical baseline)
#   4. cyrus2dbase  (first practical baseline)
set -euo pipefail

usage() {
  cat <<'EOF'
build_externals.sh - build the fetched RCSS2D externals

Usage:
  build_externals.sh [--help] [--only NAME] [--jobs N]

Options:
  --only NAME  Build only the named external. One of:
               librcsc, rcssserver, helios-base, cyrus2dbase.
  --jobs N     Parallel jobs for `make -j` (default: $(nproc) or 4).

Pre-flight (required system packages):
  autoconf automake libtool pkg-config
  flex bison
  build-essential (g++)
  libboost-all-dev   (Debian/Ubuntu; equivalent elsewhere)
  qt5-default OR qtbase5-dev + qt5-qmake  (needed by helios-base/cyrus2dbase)

Install layout:
  externals/install/   shared prefix for all externals
  externals/install/lib/, include/, bin/ populated by `make install`

Every step is marked UNVERIFIED in setup/SERVER_CONTRACT.md until the
first real fetch+build+real-smoke cycle completes on a developer's
machine. This script does not silently install system packages; it
prints an exact `sudo apt install ...` line when any are missing.

Exit status:
  0  every requested external built and installed
  1  a pre-flight check or a build step failed; partial state preserved
EOF
}

ONLY=""
JOBS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --only) shift; ONLY="${1:-}"; shift ;;
    --only=*) ONLY="${1#*=}"; shift ;;
    --jobs) shift; JOBS="${1:-}"; shift ;;
    --jobs=*) JOBS="${1#*=}"; shift ;;
    *) echo "build_externals.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
JOBS="${JOBS:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] \
  || { echo "build_externals.sh: --jobs must be a positive integer, got '$JOBS'" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/externals/src"
INSTALL="$ROOT/externals/install"
mkdir -p "$INSTALL"

die() { echo "[build] ERROR: $*" >&2; exit 1; }

# Pre-flight: required system packages. Print one `apt install` line per
# missing batch, never invoke a package manager ourselves.
preflight() {
  local missing=()
  # libtoolize (libtool's autotools front-end) is the binary present on
  # modern Debian/Ubuntu; the `libtool` shell driver is no longer
  # installed on PATH but autotools rebuilds use libtoolize directly.
  for bin in autoconf automake libtoolize pkg-config flex bison g++ make; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "[build] missing system tool(s): ${missing[*]}"
    echo "[build] on Debian/Ubuntu: sudo apt install -y \\"
    echo "         autoconf automake libtool pkg-config flex bison build-essential libfl-dev"
    die "install the system tools above and re-run"
  fi
  # libfl-dev ships FlexLexer.h, which rcssserver's clang/parser tree
  # includes. The flex binary alone is not enough; libfl-dev is a
  # separate Debian package.
  if [[ ! -f /usr/include/FlexLexer.h && ! -f /usr/local/include/FlexLexer.h ]]; then
    echo "[build] FlexLexer.h not found in standard locations."
    echo "[build] on Debian/Ubuntu: sudo apt install -y libfl-dev"
    die "install libfl-dev and re-run"
  fi
  # Boost: probe with pkg-config + a header existence check.
  if ! pkg-config --exists boost 2>/dev/null \
     && [[ ! -f /usr/include/boost/version.hpp && ! -f /usr/local/include/boost/version.hpp ]]; then
    echo "[build] Boost not found in standard locations."
    echo "[build] on Debian/Ubuntu: sudo apt install -y libboost-all-dev"
    die "install Boost and re-run"
  fi
  # Qt (only needed for helios-base / cyrus2dbase; warn rather than fail).
  if ! command -v qmake >/dev/null 2>&1 && ! command -v qmake-qt5 >/dev/null 2>&1; then
    echo "[build] WARN: qmake (Qt5) not found; helios-base / cyrus2dbase builds may fail."
    echo "[build]       on Debian/Ubuntu: sudo apt install -y qtbase5-dev qt5-qmake"
  fi
}

# Common build steps for autotools-based externals.
# Args: name configure_extra...
build_autotools() {
  local name="$1"; shift
  local dir="$SRC/$name"
  [[ -d "$dir" ]] || die "$name not fetched: $dir missing. Run: make fetch-externals"
  echo "[build] === $name ==="
  pushd "$dir" >/dev/null
  if [[ -x ./bootstrap ]]; then
    ./bootstrap
  elif [[ -x autogen.sh ]]; then
    ./autogen.sh
  else
    die "$name: no ./bootstrap or autogen.sh; build steps are UNVERIFIED for this tree"
  fi
  ./configure --prefix="$INSTALL" "$@"
  make -j"$JOBS"
  make install
  popd >/dev/null
  echo "[build] === $name DONE ==="
}

build_librcsc() {
  build_autotools librcsc
}

build_rcssserver() {
  build_autotools rcssserver
}

build_helios_base() {
  # helios-base needs librcsc installed first. Pass --with-librcsc.
  [[ -d "$INSTALL/lib" ]] \
    || die "helios-base: librcsc not installed under $INSTALL. Build librcsc first."
  build_autotools helios-base --with-librcsc="$INSTALL"
}

build_cyrus2dbase() {
  [[ -d "$INSTALL/lib" ]] \
    || die "cyrus2dbase: librcsc not installed under $INSTALL. Build librcsc first."
  # Cyrus2DBase build flags are UNVERIFIED. The autotools path below is
  # the documented approach; if the tree uses CMake instead, the
  # bootstrap step will fail loudly and the operator should fall back to
  # the README in externals/src/cyrus2dbase/.
  build_autotools cyrus2dbase --with-librcsc="$INSTALL"
}

# Cyrus2DBase master fails to build against librcsc master as of
# 2026-06-24 -- librcsc changed PenaltyKickState's return type from
# pointer to value, and Cyrus2DBase's bhv_penalty_kick.cpp still
# expects the pointer form. Until that is reconciled (either pin
# librcsc to a pre-change commit on the Cyrus side, or wait for
# Cyrus2DBase to update), it is excluded from the default ORDER.
# Pass `--only cyrus2dbase` to attempt the build anyway; the same
# compile error will reappear.
ORDER=(librcsc rcssserver helios-base)

run_one() {
  case "$1" in
    librcsc)     build_librcsc ;;
    rcssserver)  build_rcssserver ;;
    helios-base) build_helios_base ;;
    cyrus2dbase) build_cyrus2dbase ;;
    *) die "unknown external: $1 (one of: ${ORDER[*]})" ;;
  esac
}

preflight

if [[ -n "$ONLY" ]]; then
  run_one "$ONLY"
else
  for name in "${ORDER[@]}"; do
    if [[ ! -d "$SRC/$name" ]]; then
      echo "[build] skip   $name (not fetched)"
      continue
    fi
    run_one "$name"
  done
fi

echo "[build] all done. binaries under: $INSTALL/bin"
echo "[build] add to PATH:  export PATH=\"$INSTALL/bin:\$PATH\""
