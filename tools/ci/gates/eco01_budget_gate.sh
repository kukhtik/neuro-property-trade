#!/usr/bin/env bash
# ECO-01 - the frame budget: the product must stay inside a recorded budget.
#
# WHY THIS EXISTS. The owner asked (23.10) for the frugality of 2000-era games, where the
# frame cost was small and MEASURED. A budget is the only honest form of that: numbers that
# fail the build when they get worse. The budget file tools/ci/eco_budget.json was written
# from a real measurement, not guessed.
#
# WHAT IT MEASURES. The live product in a WINDOW (headless has no rendering server, so
# draw calls would be zero and the frame time meaningless - the same reason the frame
# capture runs with a window): the frame processing time (p50/p95/max), the draw calls per
# frame, the ObjectDB growth, the orphan nodes, and the static memory growth. A leak shows
# up as growth, not as "many objects".
#
# THE NEGATIVE. The budget is tightened by 1% and the gate must fail: a budget that cannot
# fail proves nothing.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> ECO-01 SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

PY=""
for cand in "py -3.12" python python3 "py -3"; do
	if command -v "$cand" >/dev/null 2>&1 && $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> ECO-01 SKIPPED: no python interpreter for tools/ci/eco_budget.py"
	exit 0
fi

outdir="$repo/build/gates"
mkdir -p "$outdir"
dump="$outdir/eco_budget.dump"
log="$outdir/eco_budget.log"

rc=0
# The window is what makes the numbers real; a headless run would report zero draw calls.
timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
	--position 40,40 res://tools/eco_budget_probe.tscn >"$log" 2>&1 || rc=$?
if ! grep -aq "ECO-01 PROBE:" "$log"; then
	echo "==> ECO-01 FAILED: the probe produced no measurement (rc=$rc) - see $log"
	exit 1
fi
grep -a "^ECO|" "$log" >"$dump"

out="$(cd "$repo" && $PY tools/ci/eco_budget.py "$dump" 2>&1)"
vrc=$?
printf '%s\n' "$out" | sed 's/^/  /'
if [ "$vrc" -ne 0 ]; then
	echo "==> ECO-01 FAILED: the frame is over its budget (see $dump)"
	exit 1
fi

neg="$(cd "$repo" && $PY tools/ci/eco_budget.py "$dump" --negative 2>&1)"
nrc=$?
if [ "$nrc" -eq 0 ]; then
	printf '%s\n' "$neg" | sed 's/^/  /'
	echo "==> ECO-01 FAILED: the negative check did not fail - the budget cannot prove it bites"
	exit 1
fi
echo "==> ECO-01 PASSED (the frame is inside the recorded budget; the negative check fails as it must)"
exit 0
