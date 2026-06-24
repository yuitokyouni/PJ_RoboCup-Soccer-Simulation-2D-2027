#!/usr/bin/env bash
# fetch_externals.sh - clone the RCSS2D external dependencies into
# externals/src/. Idempotent: skips trees that already exist unless
# --force is passed. After each clone / checkout, writes the resolved
# commit hash into externals/EXTERNALS.lock so downstream scripts know
# exactly what they built against.
set -euo pipefail

usage() {
  cat <<'EOF'
fetch_externals.sh - clone external RCSS2D dependencies

Usage:
  fetch_externals.sh [--help] [--force] [--full] [--only NAME]

Options:
  --force      If a target tree exists, fetch and `git checkout` the
               pinned ref (preserves the tree, never deletes uncommitted
               work). Without --force, existing trees are left alone.
  --full       Use a full clone instead of `--depth=1`. Required if you
               plan to bisect or build from a non-tip commit.
  --only NAME  Fetch only the named external (one of: rcssserver,
               librcsc, helios-base, cyrus2dbase).

Pinned set (see externals/EXTERNALS.md for license + role):
  rcssserver    https://github.com/rcsoccersim/rcssserver       rcssserver-19.0.0
  librcsc       https://github.com/helios-base/librcsc          master
  helios-base   https://github.com/helios-base/helios-base      master
  cyrus2dbase   https://github.com/Cyrus2D/Cyrus2DBase          master

Output:
  externals/src/<name>/         cloned source tree
  externals/EXTERNALS.lock      <name> <repo> <ref> <commit> per line

Exit status:
  0  every target was already present or successfully (re-)fetched
  1  at least one fetch failed; partial state is preserved
EOF
}

FORCE=false
FULL=false
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=true; shift ;;
    --full) FULL=true; shift ;;
    --only) shift; ONLY="${1:-}"; shift ;;
    --only=*) ONLY="${1#*=}"; shift ;;
    *) echo "fetch_externals.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v git >/dev/null 2>&1 \
  || { echo "fetch_externals.sh: git not in PATH" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/externals/src"
LOCK="$ROOT/externals/EXTERNALS.lock"
mkdir -p "$SRC"

# (name repo ref) tuples. Edit this set alongside externals/EXTERNALS.md.
EXTERNALS=(
  "rcssserver    https://github.com/rcsoccersim/rcssserver         rcssserver-19.0.0"
  "librcsc       https://github.com/helios-base/librcsc            master"
  "helios-base   https://github.com/helios-base/helios-base        master"
  "cyrus2dbase   https://github.com/Cyrus2D/Cyrus2DBase            master"
)

fetch_one() {
  local name="$1" repo="$2" ref="$3"
  local dir="$SRC/$name"

  if [[ -d "$dir/.git" ]]; then
    if [[ "$FORCE" != true ]]; then
      local sha
      sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo unknown)
      echo "[fetch] keep   $name @ $sha (use --force to update)"
      record_lock "$name" "$repo" "$ref" "$sha"
      return 0
    fi
    echo "[fetch] update $name -> $ref"
    git -C "$dir" fetch --tags origin || return 1
    git -C "$dir" checkout "$ref" || return 1
    # Fast-forward only when on a branch.
    if git -C "$dir" symbolic-ref -q HEAD >/dev/null 2>&1; then
      git -C "$dir" pull --ff-only origin "$ref" || return 1
    fi
  else
    echo "[fetch] clone  $name @ $ref"
    local depth=""
    if [[ "$FULL" != true ]]; then
      depth="--depth=1 --no-tags --single-branch --branch=$ref"
    fi
    # shellcheck disable=SC2086
    git clone $depth "$repo" "$dir" || return 1
    if [[ "$FULL" == true ]]; then
      git -C "$dir" checkout "$ref" || return 1
    fi
  fi

  local sha
  sha=$(git -C "$dir" rev-parse HEAD)
  record_lock "$name" "$repo" "$ref" "$sha"
  return 0
}

LOCK_TMP=""
init_lock() {
  LOCK_TMP=$(mktemp)
  : > "$LOCK_TMP"
}

record_lock() {
  printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> "$LOCK_TMP"
}

finalize_lock() {
  if [[ -n "$ONLY" && -f "$LOCK" ]]; then
    # Preserve entries for externals we didn't touch this run.
    while read -r line; do
      local n="${line%% *}"
      grep -q "^$n " "$LOCK_TMP" || printf '%s\n' "$line" >> "$LOCK_TMP"
    done < "$LOCK"
  fi
  sort -u "$LOCK_TMP" > "$LOCK"
  rm -f "$LOCK_TMP"
}

init_lock
trap 'finalize_lock 2>/dev/null || true' EXIT

rc=0
for entry in "${EXTERNALS[@]}"; do
  # split on whitespace
  read -r name repo ref <<< "$entry"
  if [[ -n "$ONLY" && "$ONLY" != "$name" ]]; then
    continue
  fi
  if ! fetch_one "$name" "$repo" "$ref"; then
    echo "[fetch] FAIL   $name" >&2
    rc=1
  fi
done

if (( rc == 0 )); then
  echo "[fetch] lock written: $LOCK"
fi
exit "$rc"
