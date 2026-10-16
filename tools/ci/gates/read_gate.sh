#!/usr/bin/env bash
# READ-01/02/03 — "the board and the panels can be READ" (master-fix-plan §1, D1-D7).
#
# WHY: two redesigns fixed structure and palette and neither gate measured TEXT SIZE or panel
# FILL. "Green" meant "it was drawn", not "it can be read": the board rendered 8 of 40 cells with
# any text at all (9px names in a 65px cell) and the left dock left 60% of its height empty.
# This gate measures both, from the live tree, on three profiles.
#
# Real pixels are needed for the WINDOW to lay out (headless root viewports are 64x64), so the
# wrapper runs Godot with --rendering-driver opengl3. No display => SKIPPED out loud, blocking
# nothing; but a run that produced rows and THEN died is a FAILURE, not a skip.
#
# Verdicts are the three printed lines:
#   ==> READ-01 PASSED/FAILED (cells identifiable)
#   ==> READ-02 PASSED/FAILED (dock dead zone)
#   ==> READ-03 PASSED/FAILED (minimum live font)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> READ-01 SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/READ.log"
skin="${1:-neuro}"
rc=0
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/gates/read_gate.tscn -- \
	"--skin=$skin" "--outdir=$(native "$repo/build/gates")" >"$log" 2>&1 || rc=$?

if ! grep -aq "READ DONE" "$log"; then
	# frames/rows produced and then a death is a hang; the display demonstrably worked.
	if grep -aq "READ-01 ROW" "$log"; then
		echo "==> READ-01 FAILED: the gate died without a verdict after $(grep -ac 'READ-01 ROW' "$log") measured profile(s) (rc=$rc) - see build/gates/READ.log"
		exit 1
	fi
	echo "==> READ-01 SKIPPED: the measurement produced nothing (no display/GPU? see build/gates/READ.log)"
	exit 0
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> READ-01 FAILED: SCRIPT ERROR during the measurement: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

grep -a "READ-01 ROW" "$log"
grep -a "READ NOTE" "$log" | head -3

verdicts=0
failed=0
for id in READ-01 READ-02 READ-03; do
	line="$(grep -a "==> $id " "$log" | head -1)"
	if [ -z "$line" ]; then
		echo "==> $id FAILED: the gate printed no verdict for it"
		failed=1
		continue
	fi
	echo "$line"
	verdicts=$((verdicts + 1))
	case "$line" in
		*"PASSED"*) : ;;
		*) failed=1 ;;
	esac
done
if [ "$failed" -ne 0 ]; then
	echo "==> READ GATE FAILED (see build/gates/READ.log)"
	exit 1
fi
echo "==> READ GATE PASSED ($verdicts verdicts, skin=$skin, profiles measured from the live tree)"
exit 0
