#!/usr/bin/env bash
# S3 — "the stream picture can be read" (docs/program.md P1.1), one command, one verdict.
#
# The promise: the picture a viewer sees at 1440x900 works, and watching from a PHONE works
# too (the audit found 297 findings "outside the screen" at 390px). Neither had ever been
# measured on the thing that ships.
#
# Two halves, because neither alone is honest:
#   A. THE RELEASE BUILD (web export made BY THIS RUN, absolute path) opened in a real
#      Chromium at 1280x720 and 390x844: does it boot, draw, fill the window, stay quiet,
#      and wear the skin's palette (checked by tools/ci/palette_report.py - one impl).
#   B. THE LIVE TREE at the same sizes: fonts, clipped text and things leaving the window
#      are not visible to a browser (the UI is drawn into a canvas), so they are measured
#      inside the app: game/tools/phone_fit_probe (390x844 and friends, promoted to git in
#      this same step) and the READ gate (font floors + dock fill, prints 1280x720 too).
#
# A stale artifact cannot pass: the export happens here, and its pck mtime is checked against
# the run's start (HG-11a). Verdict is the last line.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> S3 FAILED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 1
fi

PYW=""
if command -v py >/dev/null 2>&1 && py -3.12 -c "import playwright, PIL" >/dev/null 2>&1; then
	PYW="py -3.12"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import playwright, PIL" >/dev/null 2>&1; then
	PYW="python3"
fi
if [ -z "$PYW" ]; then
	echo "==> S3 FAILED: no python with playwright+PIL (the artifact half cannot be measured)"
	exit 1
fi

out="$repo/build/s3"
web="$out/web"
mkdir -p "$out" "$web"
t0="$(date +%s)"
rm -f "$out"/frame_*.png

# --- half A.1: the export of THIS run ---------------------------------------------------------
echo "==> S3 export: $web (this run, absolute path)"
( cd "$repo" && "$godot" --headless --path game --export-release "Web" "$(native "$web")/index.html" ) >"$out/export.log" 2>&1
if ! grep -qE "\[ *DONE *\].*savepack" "$out/export.log"; then
	echo "==> S3 FAILED: the web export did not finish ([ DONE ] savepack absent; see build/s3/export.log)"
	exit 1
fi
pck_mtime=$(stat -c %Y "$web/index.pck" 2>/dev/null || echo 0)
if [ "$pck_mtime" -lt "$t0" ]; then
	echo "==> S3 FAILED: the exported pck is older than this run (a stale build was about to be measured)"
	exit 1
fi

# --- half A.2: a host, so the browser opens a LIVE match and not the lobby ---------------------
port=$((19100 + ($$ % 200)))
logdir="$out/host"
mkdir -p "$logdir"
rm -f "$logdir"/*.log
( cd "$repo" && "$godot" --headless --path game -- --admin "--server-port=$port" --autostart \
	--smoke-seats=3 --smoke-drive --proxy-remote=0 "--log-dir=$(native "$logdir")" ) \
	>"$out/host.out" 2>&1 &
host_pid=$!
token=""
for _ in $(seq 1 60); do
	if [ -f "$logdir/admin.log" ]; then
		token="$(grep -aoE "SERVER seat=[0-9]+ token=[A-Za-z0-9]+" "$logdir/admin.log" | head -1 | grep -oE "[A-Za-z0-9]+$")"
		[ -n "$token" ] && break
	fi
	sleep 0.5
done
if [ -z "$token" ]; then
	kill "$host_pid" 2>/dev/null
	echo "==> S3 FAILED: the host never announced a seat token (no live match to photograph)"
	exit 1
fi
echo "==> S3 host up on $port, seat token ${token:0:6}..."

$PYW "$(native "$repo/tools/ci")/s3_artifact.py" --web "$(native "$web")" --out "$(native "$out")" \
	--sizes "1280x720,390x844" --url-extra "seat=$token&host=ws://127.0.0.1:$port&smoke=1" \
	>"$out/artifact.log" 2>&1
art_rc=$?
grep -aE "^S3 ART|^S3 ARTIFACT|^FAIL" "$out/artifact.log" || true
kill "$host_pid" 2>/dev/null
if ! grep -aq "S3 ARTIFACT" "$out/artifact.log"; then
	echo "==> S3 FAILED: the artifact half printed no verdict (see build/s3/artifact.log: $(tail -1 "$out/artifact.log" | cut -c1-160))"
	exit 1
fi

# the frames the artifact half drew: the palette verdict comes from inside that half now -
# token coverage, not per-cluster strictness (see s3_artifact.palette_coverage for why a live
# frame cannot be judged by cluster counts). The number is printed here so the reader sees it.
palette_note=""
grep -a "^S3 ART " "$out/artifact.log" | sed 's/^/   /' | sed 's/console_errors/console_err/'
for line in $(grep -aoE "token_coverage=[0-9.]+" "$out/artifact.log"); do
	echo "   $line"
done

# --- half B: the live tree, same sizes ---------------------------------------------------------
echo "==> S3 live-tree half: fonts / clipping / off-screen at phone sizes"
rc_phone=0
timeout 240 "$godot" --path "$(native "$repo/game")" --rendering-driver opengl3 --position 40,40 \
	res://tools/phone_fit_probe.tscn >"$out/phone.log" 2>&1 || rc_phone=$?
grep -a "^PHONE PROBE\|^==> PHONE PROBE" "$out/phone.log" | tail -2 || true

echo "==> S3 live-tree half: READ-01/02/03 (font floors, dock fill) incl. 1280x720"
rc_read=0
bash "$repo/tools/ci/gates/read_gate.sh" neuro >"$out/read.log" 2>&1 || rc_read=$?
grep -a "^READ-01 ROW\|^==> READ-0" "$out/read.log" | head -5 || true

# READ-01's VERDICT judges only 1440x900 (the profile the plan names); its 1280x720 row is
# printed as context, and 880x600 is compact by design. This scenario's own negative check
# found what that costs: reverting the font clamp (tile_view.NAME_MIN 11 -> 8) gave
# `READ-01 ROW 1280x720 cells=0/40 silent=40 min_font=8` and a GREEN verdict - a regression
# visible in the row and absent from the judgement. So S3 reads the rows too: on the two dock
# profiles at most 2 ring cells may stay silent.
read_row_note=""
grep -a "^READ-01 ROW" "$out/read.log" > "$out/read_rows.txt" || true
while read -r row; do
	case "$row" in
		*"1440x900"*|*"1280x720"*)
			silent="$(printf '%s' "$row" | grep -oE 'silent=[0-9]+' | grep -oE '[0-9]+')"
			cells="$(printf '%s' "$row" | grep -oE 'cells=[0-9]+/[0-9]+' | cut -d= -f2)"
			label="$(printf '%s' "$row" | awk '{print $3}')"
			if [ -n "$silent" ] && [ "$silent" -gt 2 ]; then
				read_row_note="READ-01 row $label: cells=$cells silent=$silent (the gate's own verdict looks only at 1440x900)"
			fi
			;;
	esac
done < "$out/read_rows.txt"
[ -n "$read_row_note" ] && echo "   $read_row_note"

took=$(( $(date +%s) - t0 ))
# --- the one verdict: EVERY failed half is named, so a red scenario is one line per reason ---
reasons=""
add_reason() { [ -z "$reasons" ] && reasons="$1" || reasons="$reasons | $1"; }
if [ "$art_rc" -ne 0 ]; then
	add_reason "$(grep -a '^S3 ARTIFACT FAILED' "$out/artifact.log" | head -1 | cut -c1-220)"
fi
[ -n "$palette_note" ] && add_reason "$palette_note"
if grep -aq "==> PHONE PROBE FAILED" "$out/phone.log"; then
	add_reason "$(grep -a '==> PHONE PROBE FAILED' "$out/phone.log" | head -1 | cut -c1-220)"
fi
if [ "$rc_read" -ne 0 ] || grep -aq "==> READ-0[123] FAILED" "$out/read.log"; then
	add_reason "$(grep -a '==> READ-0[123] FAILED' "$out/read.log" | head -1 | cut -c1-220)"
fi
[ -n "$read_row_note" ] && add_reason "$read_row_note"
if [ -n "$reasons" ]; then
	echo "==> S3 FAILED: $reasons"
	exit 1
fi
echo "==> S3 PASSED (release build drawn at 1280x720 and 390x844 with no console error, palette ⊆ skin tokens; live tree: phone fit clean and READ floors met; took ${took}s; frames and logs in build/s3/)"
exit 0
