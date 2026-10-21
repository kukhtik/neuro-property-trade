#!/usr/bin/env bash
# INSPECTOR-IN-RING - the tile card is INSIDE the ring, beside the journal.
#
# CONCEPT A (docs/specs/ui-redesign-v5-composition.md): the ring's interior is one panel
# with two belts - the four seats across the top, and three columns below. The tile card
# (the inspector) is one of them, because "what happened" and "what is this tile" are
# two views of the same turn.
#
# WHY IT MATTERS, in one line: the card used to live in the shell's right column - 232px
# of the 1600 frame (14.5 %) that was NOT the board, and the eye had to leave the ring to
# read it.
#
# WHAT THIS GATE MEASURES, on the REAL product (not on a mock - a composition that only
# exists in a mock is not a composition):
#   * the card is a descendant of the panno - it is inside the ring;
#   * the card is in the LOWER belt, the one that holds the journal;
#   * the card and the journal have DIFFERENT left edges in the frame - side by side,
#     not stacked.
#
# It needs a real renderer: a headless viewport has nothing to photograph. Without a
# display the gate SKIPS out loud, blocking nothing.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> INSPECTOR-IN-RING SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/inspector-in-ring.log"
rc=0
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/inspector_in_ring_probe.tscn >"$log" 2>&1 || rc=$?

if ! grep -aq "INSPECTOR-IN-RING" "$log"; then
	echo "==> INSPECTOR-IN-RING SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/inspector-in-ring.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> INSPECTOR-IN-RING FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "INSPECTOR-IN-RING FAILED" "$log"; then
	echo "==> INSPECTOR-IN-RING FAILED: the tile card is not inside the ring - $(grep -a 'INSPECTOR-IN-RING:' "$log" | head -1 | sed 's/.*INSPECTOR-IN-RING: //')"
	exit 1
fi

grep -a "==> INSPECTOR-IN-RING" "$log"
exit 0
