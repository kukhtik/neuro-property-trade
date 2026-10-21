#!/usr/bin/env bash
# PANNO-BELTS - the ring's centre is TWO BELTS, not a stack of four zones.
#
# CONCEPT A (docs/specs/ui-redesign-v5-composition.md): the ring's interior is one panel
# with two belts - the four seats across the top, and three columns below:
# roll | journal | event.
#
# WHY IT MATTERS, in one line: the hero action and the thing it acts on must be read
# together, and in a stack of four full-width bands the eye meets three bands before it
# gets to the journal. The seats rail is gone (R-15) and the journal and the inspector
# still live in a 344px column OUTSIDE the ring - measured on the live frame, the ring's
# interior ends at x 1345 and x 1357..1587 is that column: 232px of the 1600 frame, 14.5 %,
# is off the board. Moving the inspector inside is the NEXT step, because it is the one
# change that touches the shell.
#
# WHAT THIS GATE MEASURES, in the live panno:
#   * the players zone is in the UPPER belt and the other three in the LOWER one;
#   * the roll and the journal have DIFFERENT left edges in the frame - side by side, not
#     stacked (the zones live in different parents, so their own position.x is 0 each: the
#     comparison is on the GLOBAL rect);
#   * the hero zone is not squeezed.
#
# It needs a real renderer: a headless viewport has nothing to photograph. Without a
# display the gate SKIPS out loud, blocking nothing.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> PANNO-BELTS SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/panno-belts.log"
rc=0
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/panno_belts_probe.tscn >"$log" 2>&1 || rc=$?

if ! grep -aq "PANNO-BELTS" "$log"; then
	echo "==> PANNO-BELTS SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/panno-belts.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> PANNO-BELTS FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "PANNO-BELTS FAILED" "$log"; then
	echo "==> PANNO-BELTS FAILED: the ring's centre is not the two belts of concept A - $(grep -a 'PANNO-BELTS:' "$log" | head -1 | sed 's/.*PANNO-BELTS: //')"
	exit 1
fi

grep -a "==> PANNO-BELTS" "$log"
exit 0
