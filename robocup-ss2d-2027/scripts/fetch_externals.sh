#!/usr/bin/env bash
# fetch_externals.sh - acquire the RCSS2D external dependencies as
# GitHub source tarballs. Resolves the requested_ref (tag, branch, or
# commit) to a SHA via GitHub's REST API, downloads
# `archive/<SHA>.tar.gz`, extracts into externals/src/<name>/, and
# records the resolved commit in externals/EXTERNALS.lock.
#
# Why tarballs instead of git clone:
#   - works in environments where outbound git protocol is restricted
#     but GitHub's archive + REST API are reachable
#   - one fewer dependency (no git on the host needed for the fetch)
#   - the SHA in the URL pins the content; the lock pins the SHA
set -euo pipefail

usage() {
  cat <<'EOF'
fetch_externals.sh - fetch external RCSS2D dependencies as tarballs

Usage:
  fetch_externals.sh [--help] [--force] [--only NAME]

Options:
  --force      Re-resolve the requested_ref and re-extract, even if
               externals/src/<name>/ already exists.
  --only NAME  Fetch only the named external (rcssserver, librcsc,
               helios-base, or cyrus2dbase). Lock lines for the other
               externals are preserved.

Requested set (see externals/EXTERNALS.md for license + role):
  rcssserver    https://github.com/rcsoccersim/rcssserver       rcssserver-19.0.0
  librcsc       https://github.com/helios-base/librcsc          master
  helios-base   https://github.com/helios-base/helios-base      master
  cyrus2dbase   https://github.com/Cyrus2D/Cyrus2DBase          master

Output:
  externals/src/<name>/         extracted source tree
  externals/EXTERNALS.lock      <name> <repo> <requested_ref> <resolved_commit>

Exit status:
  0  every target was already present or successfully (re-)fetched
  1  at least one fetch failed; partial state is preserved
EOF
}

FORCE=false
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=true; shift ;;
    --only) shift; ONLY="${1:-}"; shift ;;
    --only=*) ONLY="${1#*=}"; shift ;;
    *) echo "fetch_externals.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for bin in curl tar python3; do
  command -v "$bin" >/dev/null 2>&1 \
    || { echo "fetch_externals.sh: $bin not in PATH" >&2; exit 1; }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/externals/src"
LOCK="$ROOT/externals/EXTERNALS.lock"
mkdir -p "$SRC"

# (name repo requested_ref) tuples. Keep in sync with externals/EXTERNALS.md.
EXTERNALS=(
  "rcssserver    https://github.com/rcsoccersim/rcssserver         rcssserver-19.0.0"
  "rcssmonitor   https://github.com/rcsoccersim/rcssmonitor        master"
  "librcsc       https://github.com/helios-base/librcsc            master"
  "helios-base   https://github.com/helios-base/helios-base        master"
  "cyrus2dbase   https://github.com/Cyrus2D/Cyrus2DBase            master"
)

owner_repo_of() {
  local repo="$1"
  local s="${repo#https://github.com/}"
  echo "${s%.git}"
}

resolve_commit() {
  # Resolve any ref (tag, branch, or SHA prefix) -> 40-char SHA.
  local repo="$1" ref="$2"
  local or
  or="$(owner_repo_of "$repo")"
  local json
  json=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$or/commits/$ref") || return 1
  python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' <<<"$json"
}

download_and_extract() {
  local repo="$1" commit="$2" dest="$3"
  local or tarball rc=0
  or="$(owner_repo_of "$repo")"
  tarball=$(mktemp --suffix=.tar.gz)
  if ! curl -fsSL --max-time 180 -o "$tarball" \
        "https://github.com/$or/archive/$commit.tar.gz"; then
    rm -f "$tarball"
    return 1
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  tar xzf "$tarball" -C "$dest" --strip-components=1 || rc=1
  rm -f "$tarball"
  return "$rc"
}

read_lock_commit() {
  local name="$1"
  [[ -f "$LOCK" ]] || return 1
  awk -v n="$name" '$1==n {print $4; exit}' "$LOCK"
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
  # Preserve lock entries for externals we didn't touch this run.
  if [[ -n "$ONLY" && -f "$LOCK" ]]; then
    while read -r line; do
      [[ -z "$line" ]] && continue
      local n="${line%% *}"
      grep -q "^$n " "$LOCK_TMP" || printf '%s\n' "$line" >> "$LOCK_TMP"
    done < "$LOCK"
  fi
  sort -u "$LOCK_TMP" > "$LOCK"
  rm -f "$LOCK_TMP"
}

fetch_one() {
  local name="$1" repo="$2" ref="$3"
  local dir="$SRC/$name"

  local sha
  if [[ -d "$dir" ]] && [[ "$FORCE" != true ]]; then
    sha=$(read_lock_commit "$name" || true)
    if [[ -n "$sha" ]]; then
      echo "[fetch] keep   $name @ $sha (use --force to refresh)"
      record_lock "$name" "$repo" "$ref" "$sha"
      return 0
    fi
  fi

  echo "[fetch] resolve $name @ $ref"
  sha=$(resolve_commit "$repo" "$ref") || {
    echo "[fetch] ERROR  $name: could not resolve $ref via GitHub API" >&2
    return 1
  }

  echo "[fetch] tarball $name $sha"
  download_and_extract "$repo" "$sha" "$dir" || {
    echo "[fetch] ERROR  $name: tarball download or extraction failed" >&2
    return 1
  }

  record_lock "$name" "$repo" "$ref" "$sha"
}

init_lock
trap 'finalize_lock 2>/dev/null || true' EXIT

rc=0
for entry in "${EXTERNALS[@]}"; do
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
