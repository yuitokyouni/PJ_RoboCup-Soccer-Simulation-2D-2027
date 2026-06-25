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
  # cmake (needed for the cyrus-* / cppdnn builds). Warn rather than fail.
  if ! command -v cmake >/dev/null 2>&1; then
    echo "[build] WARN: cmake not found; cyrus-lib / cppdnn / cyrus-team builds will fail."
    echo "[build]       on Debian/Ubuntu: sudo apt install -y cmake"
  fi
  # Eigen3 (needed for CppDNN -- header-only, ships with libeigen3-dev).
  if [[ ! -d /usr/include/eigen3 && ! -d /usr/local/include/eigen3 ]]; then
    echo "[build] WARN: Eigen3 not found; cppdnn build will fail."
    echo "[build]       on Debian/Ubuntu: sudo apt install -y libeigen3-dev"
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

build_rcssmonitor() {
  # rcssmonitor is Qt5 GUI -- needs qmake (qtbase5-dev qt5-qmake).
  if ! command -v qmake >/dev/null 2>&1 && ! command -v qmake-qt5 >/dev/null 2>&1; then
    die "rcssmonitor: qmake (Qt5) not found. Install with: sudo apt install -y qtbase5-dev qt5-qmake"
  fi
  build_autotools rcssmonitor
}

build_helios_base() {
  # helios-base needs librcsc installed first. Pass --with-librcsc.
  [[ -d "$INSTALL/lib" ]] \
    || die "helios-base: librcsc not installed under $INSTALL. Build librcsc first."

  # Apply Phase 4 defensive-duty patch (PRESS / COVER / DefenseDuty
  # assigner) before bootstrap so the regenerated Makefile.in picks up
  # the new .cpp files. The patch script is idempotent.
  local patch="$ROOT/externals/patches/helios-base/apply.sh"
  if [[ -x "$patch" ]]; then
    echo "[build] applying helios-base defensive-duty patch"
    bash "$patch" "$SRC/helios-base/src"
    # Force re-bootstrap by removing the generated Makefile.in so
    # build_autotools' ./bootstrap step regenerates it from the patched
    # Makefile.am. Otherwise a previous build's Makefile.in would be
    # reused and the new sources would never compile.
    rm -f "$SRC/helios-base/src/player/Makefile.in"
  else
    echo "[build] WARN: $patch not found or not executable; building unpatched helios-base"
  fi

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

# --- Cyrus team (real 2021 RoboCup champion code) ------------------
#
# cyrus-soccer-simulation-team uses CMake, depends on the cyrus-soccer-
# simulation-lib branch `cyrus` (their fork of librcsc with extra
# cyrus-flavored intercept tables, etc) and on Cyrus2D/CppDNN
# (header-only, requires Eigen3) and on rapidjson (vendored at build
# time via ExternalProject in upstream, but we pre-fetch since outbound
# git from the build sandbox is not guaranteed; the apply.sh script
# patches vendor/rapidjson.cmake to use the pre-fetched copy).
#
# Install lives under a SEPARATE prefix ($CYRUS_PREFIX) so the librcsc
# fork (libversion 18) does not collide with the helios librcsc in
# $INSTALL.
CYRUS_PREFIX="$ROOT/externals/install-cyrus"

build_cmake_in_prefix() {
  # Args: name install_prefix [extra cmake flags]
  local name="$1"; shift
  local prefix="$1"; shift
  local dir="$SRC/$name"
  [[ -d "$dir" ]] || die "$name not fetched: $dir missing. Run: make fetch-externals"
  echo "[build] === $name (cmake) ==="
  rm -rf "$dir/build"
  mkdir -p "$dir/build"
  pushd "$dir/build" >/dev/null
  cmake -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release "$@" ..
  make -j"$JOBS"
  make install
  popd >/dev/null
  echo "[build] === $name DONE ==="
}

build_cyrus_lib() {
  build_cmake_in_prefix cyrus-lib "$CYRUS_PREFIX"
}

build_cppdnn() {
  # CppDNN's CMakeLists.txt hard-codes /usr/local/include/CppDNN as the
  # install destination, ignoring CMAKE_INSTALL_PREFIX. We tolerate
  # this: it's a header-only library and cyrus-team finds the headers
  # via the standard include path.
  echo "[build] cppdnn install path is upstream-hardcoded /usr/local/include/CppDNN"
  echo "[build] (header-only; sudo may be required for the first install)"
  build_cmake_in_prefix cppdnn /usr/local
}

build_cyrus_team() {
  [[ -d "$CYRUS_PREFIX/lib" ]] \
    || die "cyrus-team: cyrus-lib not installed under $CYRUS_PREFIX. Build cyrus-lib first."
  [[ -d "$SRC/rapidjson/include/rapidjson" ]] \
    || die "cyrus-team: rapidjson not fetched. Run: make fetch-externals"
  # Apply the vendor/rapidjson.cmake patch so we use the pre-fetched
  # rapidjson tree at $SRC/rapidjson/ instead of ExternalProject_Add'ing
  # a fresh git clone (which fails in sandboxed builds).
  local patch="$ROOT/externals/patches/cyrus-team/apply.sh"
  if [[ -x "$patch" ]]; then
    echo "[build] applying cyrus-team vendor/rapidjson.cmake patch"
    bash "$patch" "$SRC/cyrus-team"
  else
    echo "[build] WARN: $patch missing; cyrus-team build may try ExternalProject git clone"
  fi
  build_cmake_in_prefix cyrus-team "$CYRUS_PREFIX" \
    -DCMAKE_PREFIX_PATH="$CYRUS_PREFIX"
}

# Cyrus2DBase master fails to build against librcsc master as of
# 2026-06-24 -- librcsc changed PenaltyKickState's return type from
# pointer to value, and Cyrus2DBase's bhv_penalty_kick.cpp still
# expects the pointer form. Until that is reconciled (either pin
# librcsc to a pre-change commit on the Cyrus side, or wait for
# Cyrus2DBase to update), it is excluded from the default ORDER.
# Pass `--only cyrus2dbase` to attempt the build anyway; the same
# compile error will reappear.
ORDER=(librcsc rcssserver helios-base cyrus-lib cppdnn cyrus-team)

run_one() {
  case "$1" in
    librcsc)     build_librcsc ;;
    rcssserver)  build_rcssserver ;;
    rcssmonitor) build_rcssmonitor ;;
    helios-base) build_helios_base ;;
    cyrus2dbase) build_cyrus2dbase ;;
    cyrus-lib)   build_cyrus_lib ;;
    cppdnn)      build_cppdnn ;;
    cyrus-team)  build_cyrus_team ;;
    *) die "unknown external: $1 (one of: librcsc, rcssserver, rcssmonitor, helios-base, cyrus2dbase, cyrus-lib, cppdnn, cyrus-team)" ;;
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
