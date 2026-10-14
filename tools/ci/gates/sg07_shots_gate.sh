#!/usr/bin/env bash
# SG-07 — the app's OWN frame series and a FRESH side-by-side (docs/restoration/gates.md SG-07).
#
# WHY IT EXISTS: the mockup's renders are generated from the design package and are always
# current; the app had no series at all, and `side_by_side.py` compared today's mockup against a
# role frame captured a day earlier - the HG-11 defect wearing a picture instead of a number.
#
# This gate photographs the shipping application in 14 named states under TWO skins, then has the
# machine say the only things a machine can say about pictures (tools/ci/shots_report.py):
# every file exists at the size its profile promises, no frame is blank, frames of different
# states are actually different pictures, and every frame is from THIS run. It writes
# build/renders/report.html - the grid a human reviews - and a side-by-side of a real app frame
# against the mockup's own scene for the three states that carry the layout.
#
# A REPORT gate: like SG-03 it needs real pixels (headless textures are blank) and a browser for
# the mockup half, so without a display or without Pillow/playwright it SKIPS out loud and blocks
# nothing. What it will NOT do is pass on a missing, blank, duplicated or stale frame.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> SG-07 SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

# one interpreter that can BOTH read the frames (Pillow) and render the mockup (playwright):
# `py -3.12` locally, `python*` elsewhere. Without it nothing was read, so nothing is claimed.
PY=""
for cand in "py -3.12" python3 python; do
	if $cand -c "import PIL, playwright" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> SG-07 SKIPPED: no python with Pillow+playwright - frames could not be read or the mockup rendered"
	exit 0
fi

renders="$repo/build/renders"
renders_win="$(native "$renders")"
mkdir -p "$renders" "$repo/build/gates"
started="$(date +%s)"
# A frame from the previous run is not evidence of this one (HG-11).
rm -f "$renders"/*.png

STATES="cold,settings,join-none,invite,turn-human,trade,inspector,purchase,auction,ai,win,compact,observer,admin"
## sequence [extra flags]: the extra flags are the real product CLIs (seeds, roles, round limit),
# not test-only hooks - the capture boots the shipping `MainScript`.
SPECS=("pre" "invite" "match --smoke-seed=4242 --round-limit=3" "over --smoke-drive --round-limit=2" "compact" "observer --stream" "admin --admin")

shots=0
for skin in neuro evil; do
	for spec in "${SPECS[@]}"; do
		seq="${spec%% *}"
		extra=""
		if [ "$spec" != "$seq" ]; then extra="${spec#* }"; fi
		log="$repo/build/gates/SG-07-$seq-$skin.log"
		rc=0
		# shellcheck disable=SC2086
		timeout 300 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
			--position 40,40 res://tools/gates/sg07_capture.tscn -- \
			"--seq=$seq" "--skin=$skin" "--outdir=$(native "$renders")" $extra >"$log" 2>&1 || rc=$?
		if ! grep -aq "SG-07 DONE" "$log"; then
			# A capture that produced frames and then died is a HANG, not an environment skip: the
			# display demonstrably worked. It already happened once (`match/neuro` waited forever
			# on a render signal that an occluded window stops emitting) and the gate called it a
			# skip - the series would have quietly lost five states.
			if grep -aq "SG-07 CAPTURED" "$log"; then
				echo "==> SG-07 FAILED: the $seq/$skin capture died without a verdict after $(grep -ac "SG-07 CAPTURED" "$log") frame(s) (rc=$rc) - see build/gates/SG-07-$seq-$skin.log"
				exit 1
			fi
			echo "==> SG-07 SKIPPED: the $seq/$skin capture produced no frame at all (no display/GPU? see build/gates/SG-07-$seq-$skin.log)"
			exit 0
		fi
		if grep -aq "SCRIPT ERROR" "$log"; then
			echo "==> SG-07 FAILED: SCRIPT ERROR during the $seq/$skin capture: $(grep -a "SCRIPT ERROR" "$log" | head -1)"
			exit 1
		fi
		grep -a "SG-07 MISS" "$log" | head -2
		n="$(grep -ac "SG-07 CAPTURED" "$log")"
		shots=$((shots + n))
	done
done

report="$($PY "$(native "$repo/tools/ci")/shots_report.py" --dir "$(native "$renders")" \
	--states "$STATES" --skins "neuro,evil" --started "$started" \
	--out "$(native "$renders")/report.html" 2>&1)"
echo "$report" | grep -aE "SHOTS|report:" | head -8
case "$report" in
	*"SHOTS OK"*) : ;;
	*"SHOTS FAILED"*)
		echo "==> SG-07 FAILED: $(printf '%s' "$report" | grep -a "SHOTS FAILED" | head -1)"
		exit 1
		;;
	*)
		echo "==> SG-07 FAILED: the frame check produced no verdict: $(printf '%s' "$report" | tail -1)"
		exit 1
		;;
esac

## The side-by-side a human judges: the mockup's own scene on the left, THIS RUN's app frame on
## the right. The app half is named explicitly and its age is checked, so the old failure mode
## (current mockup vs yesterday's build) cannot come back.
PAIRS="turn-human:turn-human:1440x900 auction:auction:1440x900 compact:compact:880x600"
for pair in $PAIRS; do
	st="${pair%%:*}"
	rest="${pair#*:}"
	sc="${rest%%:*}"
	size="${rest##*:}"
	for skin in neuro evil; do
		# NATIVE paths for the native interpreter: a MSYS `/c/...` path handed to python becomes
		# `<cwd>/c/...` and the file lands in a directory nobody looks at (the gate then reports
		# "produced no file" about a side-by-side that DID succeed).
		sb="$renders_win/side_by_side-$st-$skin.png"
		so="$($PY "$(native "$repo/tools/ci")/side_by_side.py" --theme "$skin" --scene "$sc" \
			--size "$size" --app "$renders_win/${st}_${skin}.png" \
			--out "$sb" --started "$started" 2>&1)"
		if printf '%s' "$so" | grep -aq "FAIL:"; then
			echo "==> SG-07 FAILED: side-by-side $st/$skin: $(printf '%s' "$so" | grep -a "FAIL:" | head -1)"
			exit 1
		fi
		if [ ! -f "$sb" ]; then
			echo "==> SG-07 FAILED: side-by-side $st/$skin produced no file"
			exit 1
		fi
		echo "side-by-side $st/$skin: $(printf '%s' "$so" | grep -a 'wrote' | tail -1)"
	done
done

echo "==> SG-07 PASSED ($shots frames of the shipping app, $STATES under neuro and evil, all current and distinct; side-by-sides for turn-human/auction/compact against the mockup; grid in build/renders/report.html)"
exit 0
