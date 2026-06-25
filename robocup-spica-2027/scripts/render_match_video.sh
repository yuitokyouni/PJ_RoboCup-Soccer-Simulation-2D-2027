#!/usr/bin/env bash
# render_match_video.sh - replay a .rcg in rcssmonitor on a headless
# Xvfb display and screen-record it with ffmpeg into an mp4.
#
# Pipeline:
#   .rcg --[rcssmonitor playback]--> Xvfb --[ffmpeg x11grab]--> .mp4
#
# Defaults to a 3x-speed playback (timer-interval 33 ms instead of the
# 100 ms real-time default) and caps the recording at 120 wall-clock
# seconds, which covers a couple of minutes of game time.
set -euo pipefail

usage() {
  cat <<'EOF'
render_match_video.sh - render a .rcg game log into an mp4 video

Usage:
  render_match_video.sh --rcg PATH --output PATH
                        [--duration SECS] [--timer-ms MS]
                        [--width N] [--height N] [--fps N]
                        [--display NUM] [--help]

Options:
  --rcg PATH         The rcssserver .rcg game log to replay (required).
  --output PATH      Destination .mp4 file (required).
  --duration SECS    Maximum recording length in wall-clock seconds.
                     Default: 120. Set to 0 to record until rcssmonitor
                     exits (long matches at default speed are >10 min).
  --timer-ms MS      rcssmonitor --timer-interval in ms. Lower = faster
                     playback. Default: 33 (~3x real time).
  --width N          Capture width in pixels.  Default: 1280.
  --height N         Capture height in pixels. Default: 720.
  --fps N            Output video framerate.   Default: 30.
  --display NUM      Xvfb display number to use. Default: 99.

Exit status:
  0  mp4 written and at least one byte large.
  1  external missing, rcssmonitor failed, or ffmpeg produced no output.
EOF
}

RCG=""
OUTPUT=""
DURATION=120
TIMER_MS=33
WIDTH=1280
HEIGHT=720
FPS=30
DISPLAY_NUM=99

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --rcg) shift; RCG="$1"; shift ;;
    --rcg=*) RCG="${1#*=}"; shift ;;
    --output) shift; OUTPUT="$1"; shift ;;
    --output=*) OUTPUT="${1#*=}"; shift ;;
    --duration) shift; DURATION="$1"; shift ;;
    --duration=*) DURATION="${1#*=}"; shift ;;
    --timer-ms) shift; TIMER_MS="$1"; shift ;;
    --timer-ms=*) TIMER_MS="${1#*=}"; shift ;;
    --width) shift; WIDTH="$1"; shift ;;
    --width=*) WIDTH="${1#*=}"; shift ;;
    --height) shift; HEIGHT="$1"; shift ;;
    --height=*) HEIGHT="${1#*=}"; shift ;;
    --fps) shift; FPS="$1"; shift ;;
    --fps=*) FPS="${1#*=}"; shift ;;
    --display) shift; DISPLAY_NUM="$1"; shift ;;
    --display=*) DISPLAY_NUM="${1#*=}"; shift ;;
    *) echo "render_match_video.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "[render] ERROR: $*" >&2; exit 1; }

[[ -n "$RCG" ]] || die "--rcg is required"
[[ -f "$RCG" ]] || die "rcg not found: $RCG"
[[ -n "$OUTPUT" ]] || die "--output is required"
for n in DURATION TIMER_MS WIDTH HEIGHT FPS DISPLAY_NUM; do
  v="${!n}"
  [[ "$v" =~ ^[0-9]+$ ]] || die "$n must be a non-negative integer, got '$v'"
done

for bin in Xvfb ffmpeg rcssmonitor; do
  command -v "$bin" >/dev/null 2>&1 \
    || die "$bin not in PATH (need xvfb, ffmpeg, and the built rcssmonitor)"
done

mkdir -p "$(dirname "$OUTPUT")"

XVFB_PID=""
MON_PID=""
FFMPEG_PID=""

cleanup() {
  for pid in $FFMPEG_PID $MON_PID $XVFB_PID; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  # Give ffmpeg a beat to finalize MOOV atom on a clean shutdown.
  sleep 0.5
  for pid in $FFMPEG_PID $MON_PID $XVFB_PID; do
    [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "[render] rcg:       $RCG"
echo "[render] output:    $OUTPUT"
echo "[render] geometry:  ${WIDTH}x${HEIGHT} @ ${FPS} fps"
echo "[render] playback:  timer-interval ${TIMER_MS} ms"
echo "[render] duration:  ${DURATION} s (0 = wait for rcssmonitor exit)"
echo "[render] display:   :$DISPLAY_NUM"

# 1. Xvfb
Xvfb ":$DISPLAY_NUM" -screen 0 "${WIDTH}x${HEIGHT}x24" -nolisten tcp 2>/dev/null &
XVFB_PID=$!
sleep 1
kill -0 "$XVFB_PID" 2>/dev/null \
  || die "Xvfb did not come up on display :$DISPLAY_NUM (display already in use?)"

# 2. rcssmonitor in playback mode. --auto-quit-mode on makes it exit
# when the log ends; --geometry pins window size to the Xvfb frame.
DISPLAY=":$DISPLAY_NUM" rcssmonitor \
  --auto-quit-mode on --auto-quit-wait 2 \
  --timer-interval "$TIMER_MS" \
  --geometry "${WIDTH}x${HEIGHT}+0+0" \
  --maximize \
  --show-tool-bar off --show-menu-bar off --show-status-bar off \
  "$RCG" &
MON_PID=$!
# Wait a moment for rcssmonitor to render its first frame before
# starting capture, otherwise the first ~1 s of the video is the
# default-grey background.
sleep 2

# 3. ffmpeg x11grab capture. -t 0 is invalid; we treat 0 as "no limit"
# by omitting -t and capping via the monitor's auto-quit.
FFMPEG_T_ARG=()
if (( DURATION > 0 )); then FFMPEG_T_ARG=(-t "$DURATION"); fi

ffmpeg -hide_banner -loglevel warning -y \
  -f x11grab -framerate "$FPS" -video_size "${WIDTH}x${HEIGHT}" \
  -i ":$DISPLAY_NUM" \
  "${FFMPEG_T_ARG[@]}" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -crf 23 \
  "$OUTPUT" &
FFMPEG_PID=$!

# Whichever exits first wins; we tear down the other.
wait -n "$FFMPEG_PID" "$MON_PID" || true

cleanup
trap - EXIT INT TERM

if [[ ! -s "$OUTPUT" ]]; then
  die "ffmpeg produced an empty output file"
fi

size=$(stat -c '%s' "$OUTPUT")
echo "[render] done: $OUTPUT ($(numfmt --to=iec --suffix=B "$size"))"
