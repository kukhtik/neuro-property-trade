#!/usr/bin/env bash
# SG-03 - "палитра кадра ⊆ токены скина" (docs/restoration/gates.md SG-03).
#
# Stage 1 is a REPORT (the design is not frozen): every significant colour of a REAL rendered
# frame of a mid-match app is checked against the skin's token palette; unexplained colours are
# reported and - after the owner reviews - calibrated into tools/ci/palette_allowlist.txt, at
# which point `--strict` turns new unexplained colours red. Hard red NOW: a blank/unreadable
# frame (an empty screenshot once masqueraded as "the app looks wrong" - never again).
#
# Capture needs real pixels: Godot runs with --rendering-driver opengl3 (headless textures are
# blank). No display / capture failed => SKIPPED (reported, not blocking) - CI has no GPU.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> SG-03 FAILED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 1
fi

PY=""
for cand in "python" "python3" "py -3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> SG-03 FAILED: no working python interpreter"
	exit 1
fi

mkdir -p "$repo/build/gates"
rc_all=0
for skin in neuro evil classic; do
	frame="$repo/build/gates/SG-03-frame-$skin.png"
	log="$repo/build/gates/SG-03-$skin.log"
	timeout 240 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 \
		--position 40,40 res://tools/gates/sg03_capture.tscn -- \
		"--out=$(native "$(dirname "$frame")")/$(basename "$frame")" "--skin=$skin" \
		>"$log" 2>&1
	if ! grep -aq "SG-03 CAPTURED" "$log"; then
		echo "==> SG-03 SKIPPED: could not capture the $skin frame (no display/GPU? see build/gates/SG-03-$skin.log)"
		exit 0
	fi
	grep -a "SG-03 CAPTURED" "$log" | tail -1
	strict=""
	if [ -f "$repo/tools/ci/palette_allowlist.txt" ]; then
		strict="--strict"
	fi
	out="$($PY "$(native "$repo/tools/ci")/palette_report.py" \
		--frame "$(native "$(dirname "$frame")")/$(basename "$frame")" \
		--skin "$(native "$(dirname "$repo/game/assets/skins/$skin")")/$(basename "$skin")/skin.json" \
		--allowlist "$(native "$repo/tools/ci")/palette_allowlist.txt" \
		--report "$(native "$repo/build/gates")/SG-03-$skin" $strict 2>&1)"
	echo "$out"
	if echo "$out" | grep -aq "==> SG-03 FAILED"; then
		rc_all=1
	fi
done
if [ "$rc_all" -ne 0 ]; then
	echo "==> SG-03 FAILED: at least one skin's palette has unexplained colours (see build/gates/SG-03-*.json)"
	exit 1
fi
if [ -f "$repo/tools/ci/palette_allowlist.txt" ]; then
	echo "==> SG-03 PASSED (strict: frames captured for neuro/evil/classic, every >=120px colour is a skin token or a reviewed allowlist entry; see build/gates/SG-03-*.json)"
else
	echo "==> SG-03 PASSED (report-stage: no allowlist yet - review build/gates/SG-03-*.json and calibrate)"
fi
exit 0
