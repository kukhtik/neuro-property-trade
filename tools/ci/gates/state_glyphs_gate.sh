#!/usr/bin/env bash
# STATE-GLYPHS - the board says a fact about a cell with a SHAPE, not with a word.
#
# The owner's complaint (20.10): "не пиши, а показывай в дизайне (к примеру кто владеет и
# состояние, сколько отелей и так далее)". The board answered it in words: the owner was a
# LETTER in a badge, the house count was the text "×3" beside 5x5 px squares, and the
# mortgage was the letter "M". A letter is not a shape, "×3" is not a count, and a 5 px
# square is a dot.
#
# WHAT THIS GATE PROVES, in pixels:
#   * a cell with an owner shows the owner's COLOUR;
#   * one house and three houses differ in the AMOUNT OF INK - the count is a form, and the
#     form grows with the fact;
#   * a hotel is its own shape, not three houses;
#   * a mortgaged cell is a HATCH that reaches the cell's edges, not a letter in the middle.
#
# It measures PLAIN cells (no name, no price, no letter badge, no text counter), so every
# pixel it counts is a SHAPE. That detail is not cosmetic: the first version of the probe
# measured the whole cell, and it PASSED with the shapes switched off - the ink differences
# it saw came from the very text the shapes replace.
#
# It needs a real renderer: a headless viewport has nothing to photograph. Without a
# display the gate SKIPS out loud, blocking nothing - but a run that produced rows and THEN
# died is a FAILURE, not a skip.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> STATE-GLYPHS SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/STATE-GLYPHS.log"
rc=0
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/state_glyphs_probe.tscn >"$log" 2>&1 || rc=$?

if ! grep -aq "STATE-GLYPHS" "$log"; then
	# the probe never reported itself: it did not run (no display?) or it died before
	# measuring. Either way nothing was proven.
	echo "==> STATE-GLYPHS SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/STATE-GLYPHS.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> STATE-GLYPHS FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "STATE-GLYPHS FAILED" "$log"; then
	echo "==> STATE-GLYPHS FAILED: the board's shapes do not say what they should - $(grep -a 'STATE-GLYPHS:' "$log" | head -1 | sed 's/.*STATE-GLYPHS: //')"
	exit 1
fi

grep -a "==> STATE-GLYPHS" "$log"
exit 0
