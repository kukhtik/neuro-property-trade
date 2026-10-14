#!/usr/bin/env bash
# HG-11 - freshness of artifacts AND frames (docs/restoration/gates.md, HG-11).
#
# The audit's two lies, now both checkable:
#   (a) `compare_mockup.py` measured a HARD-CODED frame (`build/smoke/admin.png`) from an old
#       run while the smoke's own frame went unread. Contract: the frame is an input
#       (`--frame` / NPT_FRAME); asked-for-and-missing is a hard failure; no frame = a printed
#       skip, never a silent pass.
#   (b) `tools/ci/smoke_all_roles.py > run the comparison` must point the comparison at THIS
#       run's frame.
#   (c) `tools/ci/check_freshness.sh` - canonical artifacts must be newer than the last
#       shipping-code commit or explicitly allowlisted with a reason.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

PY=""
for cand in python python3; do
	if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> HG-11 FAILED: no python interpreter to run the checker with"
	exit 1
fi

fails=0
note() { echo "  $1"; }

# --- (a1) no frame: a printed skip with the reason, exit 0 ---
out="$(cd "$repo" && "$PY" tools/ci/compare_mockup.py neuro 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
	note "no-frame run exited $rc (expected 0: palette/structure still checkable)"
	fails=$((fails + 1))
elif ! printf '%s' "$out" | grep -q "COMPARISON PASSED"; then
	note "no-frame run did not print COMPARISON PASSED"
	fails=$((fails + 1))
elif ! printf '%s' "$out" | grep -q "layout skipped"; then
	note "no-frame run did not say the layout step was SKIPPED - a silent skip is the bug"
	fails=$((fails + 1))
elif ! printf '%s' "$out" | grep -q -- "--frame"; then
	note "no-frame skip message does not name --frame / NPT_FRAME"
	fails=$((fails + 1))
else
	note "no frame given -> explicit skip: $(printf '%s' "$out" | grep -m1 'layout skipped' | sed 's/^ *//')"
fi

# --- (a2) an explicitly requested frame that does not exist: hard failure ---
missing_frame="build/gates/definitely-not-a-frame-$$.png"
out="$(cd "$repo" && "$PY" tools/ci/compare_mockup.py neuro --frame "$missing_frame" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
	note "a missing --frame did NOT fail the comparison (asked for and gone must be red)"
	fails=$((fails + 1))
elif ! printf '%s' "$out" | grep -qi "does not exist"; then
	note "missing --frame failed with the wrong message: $(printf '%s' "$out" | head -1)"
	fails=$((fails + 1))
else
	note "missing --frame -> hard failure with a human reason"
fi

# --- (a3) the checker does not remember a frame path (comments may tell the history; the CODE
# must not carry it) ---
if grep -qa '"build" / "smoke" / "admin' "$repo/tools/ci/compare_mockup.py"; then
	note "compare_mockup.py still derives the frame from build/smoke/admin.png"
	fails=$((fails + 1))
else
	note "compare_mockup.py carries no hard-coded frame path"
fi

# --- (b) the smoke points the comparison at its OWN frame ---
if grep -qa -- "\-\-frame" "$repo/tools/ci/smoke_all_roles.py"; then
	note "smoke_all_roles.py passes its own admin frame to the comparison"
else
	note "smoke_all_roles.py does not pass its own frame (still compares someone else's)"
	fails=$((fails + 1))
fi

# --- (c) artifact freshness ---
out="$(bash "$repo/tools/ci/check_freshness.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | grep -aE "^(==>|ARCHIVED|STALE|FRESH)" | head -8
if [ "$rc" -ne 0 ]; then
	note "check_freshness.sh is red"
	fails=$((fails + 1))
fi

if [ "$fails" -eq 0 ]; then
	echo "==> HG-11 PASSED (frames are per-run and requested explicitly; artifacts fresh or archived with a reason)"
	exit 0
fi
echo "==> HG-11 FAILED: $fails check(s) red (see the lines above)"
exit 1
