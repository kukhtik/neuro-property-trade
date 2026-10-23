#!/usr/bin/env bash
# ECO-02 - the hot path must not allocate, search the tree, or churn the scene.
#
# WHY THIS EXISTS. The owner asked (23.10) for the frugality of 2000-era games, where
# nothing was created in a frame: the assets were fixed, the memory was bounded, and the
# engine could not even do what Godot 4 does. The cheap honest first measurement of that
# is STATIC: inside `_process`, `_draw` and `_physics_process` there must be no object
# creation, no tree lookup, no string building and no scene churn.
#
# WHAT IT CHECKS. Every `.gd` file of the PRODUCT is parsed by INDENTATION (a block ends
# when the indentation decreases) and the bodies of the three hot functions are scanned
# for allocations (`new`, `str(`, `%`, a collection literal), tree lookups (`get_node`,
# `find_child`, `get_children`), scene churn (`add_child`, `queue_free`) and per-frame
# signal reconnection. A block parser is used on purpose: the taste gate's regex missed 59
# calls, and a check that misses is worse than no check.
#
# THE RATCHET. The allowed number of violations lives in
# tools/ci/eco_hotpath_baseline.txt and is currently ZERO. The gate fails when the count
# grows, and passes when it shrinks - so the number can only go down. It is not a "zero
# tolerance" gate that would be red from day one and get switched off; it is a number
# that ratchets.
#
# SCOPE. The product only. CI tooling (game/tools, game/tests) runs in headless probes,
# never in a frame of the game, and is not even shipped in the release pack; measuring it
# would bury the product's number in noise (83 of 89 hits were there).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

PY=""
for cand in "py -3.12" python python3 "py -3"; do
	if command -v "$cand" >/dev/null 2>&1 && $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> ECO-02 SKIPPED: no python interpreter for tools/ci/eco_hotpath.py"
	exit 0
fi

out="$(cd "$repo" && $PY tools/ci/eco_hotpath.py 2>&1)"
rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
if [ "$rc" -ne 0 ]; then
	echo "==> ECO-02 FAILED: the product's hot path allocates again (see the lines above)"
	exit 1
fi

# The negative must be RED: the gate has to fail when the defect is really there.
neg="$(cd "$repo" && $PY tools/ci/eco_hotpath.py --negative 2>&1)"
nrc=$?
if [ "$nrc" -eq 0 ]; then
	printf '%s\n' "$neg" | sed 's/^/  /'
	echo "==> ECO-02 FAILED: the negative check did not fail - the gate cannot prove it measures"
	exit 1
fi
echo "==> ECO-02 PASSED (the hot path creates nothing; the negative check fails as it must)"
exit 0
