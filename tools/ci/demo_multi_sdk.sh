#!/usr/bin/env bash
# Record a demo of the whole app with THREE SDK players, one connection each.
#
# Starts three seats (tools/ci/llm_seat.py, scripted answers with `--pace` so every move is visible
# for at least a second), runs game/tools/demo_multi_sdk.gd WINDOWED (a headless viewport has
# nothing to photograph) and assembles the frames into an MP4 with the ffmpeg that ships with the
# agent tools. The scene itself drives the admin panel (pause, then resume) mid-recording.
#
# Run: bash tools/ci/demo_multi_sdk.sh [seconds]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

secs="${1:-52}"
pace="1.2"
out="$repo/build/demo"
frames="$out/frames"
log="$out/demo.log"
mkdir -p "$frames"
rm -f "$frames"/f*.png

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> DEMO FAILED: no Godot binary"
	exit 1
fi
PY=""
for cand in "python" "python3" "py -3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
	echo "==> DEMO FAILED: no working python for the seats"
	exit 1
fi
ffmpeg="$(command -v ffmpeg || true)"
if [ -z "$ffmpeg" ]; then
	echo "==> DEMO FAILED: ffmpeg is not on PATH (the video cannot be assembled)"
	exit 1
fi

seat_dir="$(native "$here")"
pids=""
start_seat() {   # $1 = logfile -> prints the port
	local logf="$1"
	$PY "$seat_dir/llm_seat.py" --pace "$pace" --timeout 300 --model "" >"$logf" 2>&1 &
	pids="$pids $!"
	local p=""
	for _i in $(seq 1 80); do
		p=$(grep -oE 'LLM_PORT=[0-9]+' "$logf" 2>/dev/null | head -1 | cut -d= -f2)
		[ -n "$p" ] && break
		sleep 0.25
	done
	printf '%s' "$p"
}
cleanup() { for p in $pids; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

A="$(start_seat "$out/seat-a.log")"
B="$(start_seat "$out/seat-b.log")"
C="$(start_seat "$out/seat-c.log")"
if [ -z "$A" ] || [ -z "$B" ] || [ -z "$C" ]; then
	echo "==> DEMO FAILED: a seat did not start (see build/demo/seat-*.log)"
	exit 1
fi
echo "==> DEMO seats on 127.0.0.1:$A 127.0.0.1:$B 127.0.0.1:$C (pace ${pace}s per move)"

NPT_SDK_A="ws://127.0.0.1:$A" NPT_SDK_B="ws://127.0.0.1:$B" NPT_SDK_C="ws://127.0.0.1:$C" \
	NPT_DEMO_DIR="$(native "$frames")" \
	timeout $((secs + 90)) "$godot" --path "$(native "$repo/game")" \
	--demo-outdir="$(native "$frames")" res://tools/demo_multi_sdk.tscn >"$log" 2>&1
grep -aE "^DEMO|^==>" "$log" | tail -20 || true

shots="$(ls "$frames"/f*.jpg 2>/dev/null | wc -l)"
if [ "$shots" -lt 40 ]; then
	echo "==> DEMO FAILED: only $shots frame(s) were written (see $log)"
	exit 1
fi
# Assemble at the rate the frames were ACTUALLY captured, so the video runs at real time instead of
# fast-forwarding: the recorder cannot promise a fixed fps (each frame costs a viewport readback).
rate="$(awk -v s="$shots" -v d="$secs" 'BEGIN { r = s / d; if (r < 1) r = 1; printf "%.3f", r }')"
echo "==> DEMO frames: $shots -> ${rate} fps"
"$ffmpeg" -y -framerate "$rate" -i "$(native "$frames")/f%05d.jpg" -c:v libx264 -pix_fmt yuv420p \
	-movflags +faststart "$(native "$out")/demo.mp4" >"$out/ffmpeg.log" 2>&1
if [ ! -s "$out/demo.mp4" ]; then
	echo "==> DEMO FAILED: ffmpeg produced no file (see $out/ffmpeg.log)"
	tail -5 "$out/ffmpeg.log" || true
	exit 1
fi
echo "==> DEMO video: $out/demo.mp4 ($(du -h "$out/demo.mp4" | cut -f1))"
grep -aq "==> DEMO PASSED" "$log"
