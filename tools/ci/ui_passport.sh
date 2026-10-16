#!/usr/bin/env bash
# UI PASSPORT runner - the agent's eyes and text description of the real interface.
#
# WHY: gates answer "did it pass"; they do not let an agent SEE the screen or understand what is
# on it. This runner drives the real app (headless, the layout is exact once the root size is
# pinned), dumps every state to a machine tree + a text map, and folds the dumps into ONE dossier
# (build/ui-passport/for-agent.md). Frames for the same states come from the SG-07 series and are
# annotated from the same rects when Pillow is available. Not a gate: it never judges.
#
#   tools/ci/ui_passport.sh [--skin=neuro] [--with-stream]
#
# Verdicts (read the LINES, not the exit code):
#   every sequence must print  `UI PASSPORT DONE seq=<seq> states=<n>`
#   any `SCRIPT ERROR` (with colon) fails this runner
#   final line: `==> UI PASSPORT OK (N states)` or `==> UI PASSPORT FAILED`
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
godot="$(bash "$here/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "ui_passport: no Godot binary (see tools/ci/fetch_godot.sh)" >&2
	exit 1
fi

# NATIVE paths for native binaries: godot.exe cannot open MSYS `/c/...` paths.
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }
out="$(native "$repo/build/ui-passport")"
mkdir -p "$repo/build/ui-passport"
rm -f "$repo/build/ui-passport"/*.tree.json "$repo/build/ui-passport"/*.text.md 2>/dev/null

skin=""
with_stream=0
with_film=0
save_baseline=0
diff_mode=0
for a in "$@"; do
	case "$a" in
		--skin=*) skin="${a#--skin=}" ;;
		--with-stream) with_stream=1 ;;
		--film) with_film=1 ;;
		--save-baseline) save_baseline=1 ;;
		--diff) diff_mode=1 ;;
		*) echo "usage: ui_passport.sh [--skin=<id>] [--with-stream] [--film] [--save-baseline] [--diff]" >&2; exit 2 ;;
	esac
done

fail=0
states=0

run_seq() { # <seq> [extra godot args...]
	local seq="$1"; shift
	local log="$repo/build/ui-passport/run_${seq}_${1:-default}.log"
	echo "--- seq=$seq $*"
	# `--path` must be RELATIVE (MSYS absolute paths look like /c/... to the native binary).
	( cd "$repo" && timeout 420 "$godot" --headless --path game res://tools/ui_passport.tscn -- \
		"--seq=$seq" "--outdir=$out" "$@" ) > "$log" 2>&1
	if ! grep -aq "UI PASSPORT DONE seq=$seq" "$log"; then
		echo "FAIL: seq=$seq printed no DONE line (see $log)"
		fail=1
	fi
	if grep -aq "SCRIPT ERROR" "$log"; then
		echo "FAIL: seq=$seq emitted a SCRIPT ERROR (see $log)"
		fail=1
	fi
	local n
	n="$(grep -ac 'UI-PASSPORT STATE' "$log" || true)"
	states=$((states + n))
	grep -a 'UI-PASSPORT STATE\|UI-PASSPORT MISS' "$log" || true
}

if [ -n "$skin" ]; then
	run_seq pre "--skin=$skin"
	run_seq match "--skin=$skin"
	[ "$with_stream" = 1 ] && run_seq match "--skin=$skin" "--role=stream" "--size=1280x720" "--label=stream"
else
	run_seq pre
	run_seq match
	[ "$with_stream" = 1 ] && run_seq match "--role=stream" "--size=1280x720" "--label=stream"
fi
# film = motion + behaviour; it drives the real app and never judges
[ "$with_film" = 1 ] && run_seq film ${skin:+--skin=$skin}

# The dossier. Pillow is only needed for the annotated frames; the text map needs none.
py=""
for cand in "py -3.12" "python" "python3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then py="$cand"; break; fi
done
if [ -n "$py" ]; then
	# NATIVE path for the report script too: python is a native binary and cannot open `/c/...`.
	# `native` takes a DIRECTORY (it cds into it) - convert the repo, then append the script path.
	natrepo="$(native "$repo")"
	$py "$natrepo/tools/ci/ui_passport_report.py" "$natrepo" || fail=1
	if [ "$save_baseline" = 1 ] && [ "$fail" = 0 ]; then
		mkdir -p "$repo/build/ui-passport/baseline"
		cp "$repo/build/ui-passport"/*.tree.json "$repo/build/ui-passport"/baseline/ 2>/dev/null
		cp "$repo/build/ui-passport"/*.text.md "$repo/build/ui-passport"/baseline/ 2>/dev/null
		echo "baseline saved: $(ls "$repo/build/ui-passport"/baseline/*.tree.json 2>/dev/null | wc -l) dumps"
	fi
	if [ "$diff_mode" = 1 ]; then
		$py "$natrepo/tools/ci/ui_passport_diff.py" "$natrepo" || fail=1
	fi
else
	echo "FAIL: no python found for the report stage"
	fail=1
fi

if [ "$fail" = 0 ]; then
	echo "==> UI PASSPORT OK ($states states; dossier: build/ui-passport/for-agent.md)"
else
	echo "==> UI PASSPORT FAILED (see the FAIL lines above)"
	exit 1
fi
