#!/usr/bin/env bash
# setup_cyrus_snapshots.sh -- materialize the two cyrus-team snapshots
# the team_launchers/cyrus_{vanilla,improved}_*.sh scripts expect.
#
# Run AFTER `make build-externals` has produced a clean cyrus-team
# build under externals/src/cyrus-team/build/src/sample_player. This
# script will:
#
#   1. Take the freshly-built (rapidjson-patched, no phase5) cyrus-team
#      tree and copy it to externals/src/cyrus-team-vanilla-snapshot/
#      -- this is the "true vanilla" snapshot.
#
#   2. Run apply_phase5.sh against externals/src/cyrus-team/ to add
#      the Phase 5/6/7/8 patches in place. Rebuild.
#
#   3. Copy the now-improved cyrus-team tree to
#      externals/src/cyrus-team-v3-snapshot/ -- this is the "improved"
#      snapshot used by the cyrus_improved_*.sh launchers.
#
# Idempotent: if vanilla snapshot already exists, step 1 is skipped.
# If apply_phase5.sh sentinels are present (PHASE5_F325 etc.), step 2's
# patches no-op but the rebuild still runs. The v3 snapshot is always
# refreshed from the latest cyrus-team build.
#
# Usage:
#   scripts/setup_cyrus_snapshots.sh [--force-vanilla] [--jobs N]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/externals/src"
PATCHES="$ROOT/externals/patches/cyrus-team"
CYRUS="$SRC/cyrus-team"
VAN_SNAP="$SRC/cyrus-team-vanilla-snapshot"
V3_SNAP="$SRC/cyrus-team-v3-snapshot"
CYRUS_PREFIX="$ROOT/externals/install-cyrus"

FORCE_VANILLA=false
JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-vanilla) FORCE_VANILLA=true; shift ;;
    --jobs) shift; JOBS="${1:-}"; shift ;;
    --jobs=*) JOBS="${1#*=}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

die() { echo "[snapshots] ERROR: $*" >&2; exit 1; }

[[ -f "$CYRUS/build/src/sample_player" ]] \
  || die "$CYRUS/build/src/sample_player missing. Run: make build-externals --only cyrus-team"

if grep -q 'PHASE5_F325' "$CYRUS/src/strategy.h" 2>/dev/null; then
  die "$CYRUS/src/strategy.h already contains Phase 5 patches; cannot use as vanilla source. Reset cyrus-team (rm -rf, refetch, rebuild)."
fi

if [[ ! -d "$VAN_SNAP" || "$FORCE_VANILLA" == true ]]; then
  echo "[snapshots] (re)creating vanilla snapshot"
  rm -rf "$VAN_SNAP"
  cp -a "$CYRUS" "$VAN_SNAP"
else
  echo "[snapshots] vanilla snapshot already exists at $VAN_SNAP; skipping"
fi

echo "[snapshots] applying phase5 patches to $CYRUS"
bash "$PATCHES/apply_phase5.sh" "$CYRUS"

echo "[snapshots] rebuilding cyrus-team with phase5"
pushd "$CYRUS/build" >/dev/null
cmake -DCMAKE_INSTALL_PREFIX="$CYRUS_PREFIX" \
      -DCMAKE_PREFIX_PATH="$CYRUS_PREFIX" \
      -DCMAKE_BUILD_TYPE=Release ..
make -j"$JOBS"
popd >/dev/null

echo "[snapshots] (re)creating v3 (improved) snapshot"
rm -rf "$V3_SNAP"
cp -a "$CYRUS" "$V3_SNAP"

echo "[snapshots] DONE"
echo "[snapshots]   vanilla : $VAN_SNAP/build/src/sample_player"
echo "[snapshots]   improved: $V3_SNAP/build/src/sample_player"
