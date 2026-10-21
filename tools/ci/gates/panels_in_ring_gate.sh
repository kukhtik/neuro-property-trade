#!/usr/bin/env bash
# PANELS-IN-RING - the seat cards, the tile card and the journal are INSIDE the ring.
#
# CONCEPT A (docs/specs/ui-redesign-v5-composition.md): the ring's interior holds the facts of
# the turn. The seat cards came from a 268px LEFT DOCK that the profile hides below 2000px
# wide - so on every window the product actually opens, the richer view of the four seats was
# behind a drawer while the ring painted a POORER COPY of the same four facts. The tile card
# came from a 344px right column: 14.5 % of the 1600px frame that was not the board.
#
# WHY IT MATTERS, in one line: two copies of the same four facts, one of them in the ring and
# one of it hidden - and the player has to guess which one is the truth.
#
# WHAT THIS GATE MEASURES, on the REAL product (not on a mock - a composition that exists
# only in a mock is not a composition):
#   * the seat cards, the tile card and the journal are each a DESCENDANT of the panno;
#   * none of them is a sliver (a panel inside the ring and 60px wide is still unreadable);
#   * the old left dock is GONE - there is no dock left to hide the cards behind.
#
# It needs a real renderer: a headless viewport has nothing to photograph. Without a
# display the gate SKIPS out loud, blocking nothing.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> PANELS-IN-RING SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/panels-in-ring.log"
rc=0
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/panels_in_ring_probe.tscn >"$log" 2>&1 || rc=$?

if ! grep -aq "PANELS-IN-RING" "$log"; then
	echo "==> PANELS-IN-RING SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/panels-in-ring.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> PANELS-IN-RING FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "PANELS-IN-RING FAILED" "$log"; then
	echo "==> PANELS-IN-RING FAILED: a panel is not inside the ring - $(grep -a 'PANELS-IN-RING:' "$log" | head -1 | sed 's/.*PANELS-IN-RING: //')"
	exit 1
fi

grep -a "==> PANELS-IN-RING" "$log"
exit 0
