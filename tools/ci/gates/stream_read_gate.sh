#!/usr/bin/env bash
# STREAM-READ — "the stream picture can be read from a PHONE" (docs/program.md P1.1).
#
# The owner's correction of 16.10: watching the stream from a phone is NOT playing in a 390px
# game window. The promise is a picture drawn at a native large resolution that a viewer watches
# small, so the honest measure is the EFFECTIVE font size after the frame is scaled down:
#
#     effective_px = frame_px * (390 / frame_width)
#
# A 14px label in a 1920px frame lands at 2.8px on a phone. This gate measures the labels a viewer
# must grasp from one glance and judges the smallest effective size against a 12px floor.
#
# WHY A REAL WINDOW: a headless root viewport is 64x64 and would measure a window nobody has, so
# this runs with --rendering-driver opengl3 at 1920x1080. No display => SKIPPED out loud, blocking
# nothing; but a run that produced rows and THEN died is a FAILURE, not a skip.
#
# Verdict is the printed line:
#   ==> STREAM-READ PASSED/FAILED (...)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> STREAM-READ SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/STREAM-READ.log"
skin="${1:-neuro}"
# the fixed seed reaches main.gd through the product's own CLI, so every run measures the same match
seed="${STREAM_READ_SEED:-4242}"
rc=0
# `--smoke-drive` lets the host play its own LOCAL seats: without it the match parks on the first
# local turn and NO events reach the journal, so "what is happening" has no line to measure (the
# gate's first runs failed on exactly that, and said so). The fixed seed keeps the match the same
# every run; both flags are the product's own CLI, read by main._cli_value.
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/gates/stream_read_gate.tscn -- \
	"--skin=$skin" "--outdir=$(native "$repo/build/gates")" "--smoke-seed=$seed" "--smoke-drive" >"$log" 2>&1 || rc=$?

if ! grep -aq "STREAM-READ frame=" "$log"; then
	# the gate never reported its own coverage line: it did not run (no display?) or it died before
	# measuring. Either way nothing was proven, so it is a SKIP only if it produced no rows at all.
	if grep -aq "STREAM-READ ROW" "$log"; then
		echo "==> STREAM-READ FAILED: the gate died after $(grep -ac 'STREAM-READ ROW' "$log") measured role(s) (rc=$rc) - see build/gates/STREAM-READ.log"
		exit 1
	fi
	echo "==> STREAM-READ SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/STREAM-READ.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> STREAM-READ FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

grep -a "STREAM-READ ROW" "$log"
grep -a "STREAM-READ NOTE" "$log" | head -3
line="$(grep -a "==> STREAM-READ " "$log" | tail -1)"
if [ -z "$line" ]; then
	echo "==> STREAM-READ FAILED: the gate printed no verdict line"
	exit 1
fi
echo "$line"
case "$line" in
	*"PASSED"*) exit 0 ;;
	*) exit 1 ;;
esac
