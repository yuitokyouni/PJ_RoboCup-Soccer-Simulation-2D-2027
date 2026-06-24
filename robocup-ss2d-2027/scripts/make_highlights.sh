#!/usr/bin/env bash
# make_highlights.sh - extract a goals-only highlights reel from one
# match. Reads the .rcl, finds every goal_l_N / goal_r_N referee event,
# renders the full match via scripts/render_match_video.sh, cuts a clip
# around each goal cycle, and concatenates the clips into one mp4.
set -euo pipefail

usage() {
  cat <<'EOF'
make_highlights.sh - render a goals-only highlights mp4 from a match

Usage:
  make_highlights.sh --run-dir PATH --output PATH
                     [--pre SECS] [--post SECS] [--timer-ms MS]
                     [--width N] [--height N] [--fps N] [--help]

Options:
  --run-dir PATH   Match run directory (must contain *.rcg + *.rcl).
                   Typically logs/experiments/<id>/matches/match_NNNNNN/.
  --output PATH    Destination .mp4 file.
  --pre  SECS      Game-seconds of context before each goal. Default: 6.
  --post SECS      Game-seconds of celebration after each goal. Default: 4.
  --timer-ms MS    rcssmonitor timer interval. Default: 33 (~3x speed).
  --width / --height / --fps  Forwarded to render_match_video.sh.

Exit:
  0 if at least one clip rendered and the output mp4 has non-zero size.
EOF
}

RUN_DIR=""
OUTPUT=""
PRE=6
POST=4
TIMER_MS=33
WIDTH=1280
HEIGHT=720
FPS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --run-dir) shift; RUN_DIR="$1"; shift ;;
    --run-dir=*) RUN_DIR="${1#*=}"; shift ;;
    --output) shift; OUTPUT="$1"; shift ;;
    --output=*) OUTPUT="${1#*=}"; shift ;;
    --pre) shift; PRE="$1"; shift ;;
    --pre=*) PRE="${1#*=}"; shift ;;
    --post) shift; POST="$1"; shift ;;
    --post=*) POST="${1#*=}"; shift ;;
    --timer-ms) shift; TIMER_MS="$1"; shift ;;
    --timer-ms=*) TIMER_MS="${1#*=}"; shift ;;
    --width) shift; WIDTH="$1"; shift ;;
    --width=*) WIDTH="${1#*=}"; shift ;;
    --height) shift; HEIGHT="$1"; shift ;;
    --height=*) HEIGHT="${1#*=}"; shift ;;
    --fps) shift; FPS="$1"; shift ;;
    --fps=*) FPS="${1#*=}"; shift ;;
    *) echo "make_highlights.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "[highlights] ERROR: $*" >&2; exit 1; }

[[ -n "$RUN_DIR" ]] || die "--run-dir is required"
[[ -d "$RUN_DIR" ]] || die "run-dir not found: $RUN_DIR"
[[ -n "$OUTPUT" ]] || die "--output is required"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$ROOT/scripts/render_match_video.sh"

RCG=$(find "$RUN_DIR" -maxdepth 1 -name '*.rcg' | head -1)
RCL=$(find "$RUN_DIR" -maxdepth 1 -name '*.rcl' | head -1)
[[ -n "$RCG" ]] || die "no *.rcg under $RUN_DIR"
[[ -n "$RCL" ]] || die "no *.rcl under $RUN_DIR"

mapfile -t GOAL_LINES < <(
  grep -oE '^[0-9]+,[0-9]+	\(referee goal_[lr]_[0-9]+\)' "$RCL" || true
)
N=${#GOAL_LINES[@]}
(( N > 0 )) || die "no goal_[lr]_N referee events in $RCL"

echo "[highlights] match:        $(basename "$RUN_DIR")"
echo "[highlights] goals found:  $N"
for line in "${GOAL_LINES[@]}"; do
  cycle=${line%%,*}
  side=$(echo "$line" | grep -oE 'goal_[lr]' | head -1)
  echo "[highlights]   $side at cycle $cycle"
done

mkdir -p "$(dirname "$OUTPUT")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Render the full match. Cap duration to (last_goal_cycle * timer_ms +
# POST + 2) seconds so we don't waste time recording the trailing
# play-on that has no more goals.
LAST_CYCLE=$(echo "${GOAL_LINES[-1]}" | grep -oE '^[0-9]+' | head -1)
RENDER_DURATION=$(python3 -c "import math; print(math.ceil($LAST_CYCLE * $TIMER_MS / 1000) + $POST + 3)")
FULL="$TMP/full.mp4"
echo "[highlights] rendering full match (~${RENDER_DURATION}s wall) -> $FULL"
bash "$RENDER" \
  --rcg "$RCG" --output "$FULL" \
  --duration "$RENDER_DURATION" \
  --timer-ms "$TIMER_MS" \
  --width "$WIDTH" --height "$HEIGHT" --fps "$FPS"

LIST="$TMP/list.txt"
: > "$LIST"
i=0
for line in "${GOAL_LINES[@]}"; do
  cycle=${line%%,*}
  vstart=$(python3 -c "print(max(0, $cycle * $TIMER_MS / 1000 - $PRE))")
  vlen=$((PRE + POST))
  clip=$(printf "%s/clip_%03d.mp4" "$TMP" "$i")
  ffmpeg -hide_banner -loglevel error -y \
    -ss "$vstart" -i "$FULL" -t "$vlen" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 23 \
    "$clip"
  echo "file '$clip'" >> "$LIST"
  i=$((i+1))
done

echo "[highlights] concatenating $i clips -> $OUTPUT"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$LIST" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 23 \
  "$OUTPUT"

[[ -s "$OUTPUT" ]] || die "concat produced empty output"
size=$(stat -c '%s' "$OUTPUT")
echo "[highlights] done: $OUTPUT ($(numfmt --to=iec --suffix=B "$size"))"
