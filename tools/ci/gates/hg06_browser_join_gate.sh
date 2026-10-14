#!/usr/bin/env bash
# HG-06 - the browser join, end to end, on a build EXPORTED BY THIS RUN (docs/restoration/gates.md).
#
# Proves what the product broke and what no test noticed: a person opens the invitation link in a
# browser, joins a real host, and plays - accepted by the engine. The audit's three tools all
# measured `joined=False`; this gate is the promotion of `tools/ci/browser_seat_e2e.py` (kept as
# the driver) with the two things the audit demanded:
#   (a) THE EXPORT IS THIS RUN'S: `--export-release` into build/gates/web, then the pck mtime is
#       checked against the run's start - a stale build fails the gate (HG-11a: the audit's
#       browser runs measured an export from before the interface swap);
#   (b) a verdict line for the runner, not just a printed RESULT.
#
# Environment: this gate needs a python WITH playwright (`py -3.12` locally). Without one it
# prints == > HG-06 SKIPPED: reason - the runner counts a skip as "did not prove anything",
# which is honest and does not block CI on machines that cannot run a browser.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> HG-06 FAILED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 1
fi

# a python that has playwright AND PIL (py -3.12 first: that is the venv of this repo's tools)
PYW=""
if command -v py >/dev/null 2>&1 && py -3.12 -c "import playwright, PIL" >/dev/null 2>&1; then
	PYW="py -3.12"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import playwright, PIL" >/dev/null 2>&1; then
	PYW="python3"
elif command -v python >/dev/null 2>&1 && python -c "import playwright, PIL" >/dev/null 2>&1; then
	PYW="python"
fi
if [ -z "$PYW" ]; then
	echo "==> HG-06 SKIPPED: no python with playwright+PIL found (install playwright or run py -3.12)"
	exit 0
fi

# --- (a) the export of THIS run, into the gate's own directory -------------------------------
webdir="$repo/build/gates/web"
mkdir -p "$webdir"
t0="$(date +%s)"
echo "==> HG-06 export: $webdir (this run, absolute path)"
( cd "$repo" && "$godot" --headless --path game --export-release "Web" "$(native "$webdir")/index.html" ) >"$repo/build/gates/HG-06-export.log" 2>&1
# the log carries ANSI colour codes around the status tokens (`\e[92m[ DONE ]\e[39m .savepack`),
# so the match must tolerate them: `].*savepack`, not `] savepack`.
if ! grep -qE "\[ *DONE *\].*savepack" "$repo/build/gates/HG-06-export.log"; then
	echo "==> HG-06 FAILED: the web export did not finish ([ DONE ] savepack absent; see build/gates/HG-06-export.log)"
	exit 1
fi
pck="$webdir/index.pck"
pck_mtime=$(stat -c %Y "$pck" 2>/dev/null || echo 0)
if [ "$pck_mtime" -lt "$t0" ]; then
	echo "==> HG-06 FAILED: the exported pck is older than this run (stale build measured)"
	exit 1
fi
echo "==> HG-06 export fresh: index.pck $(stat -c %s "$pck") bytes"

# --- the browser plays ------------------------------------------------------------------------
export NPT_WEB="$(native "$webdir")"
export NPT_LOGS="$(native "$repo/build/gates/browser_logs")"
# native() converts a DIRECTORY (it cds into it); a file argument needs dirname/basename
e2e_dir="$(dirname "$repo/tools/ci/browser_seat_e2e.py")"
e2e_win="$(native "$e2e_dir")/$(basename "$repo/tools/ci/browser_seat_e2e.py")"
out="$($PYW "$e2e_win" 2>&1)"
rc=$?
printf '%s\n' "$out" | grep -aE "^(joined|projections|intents sent|accepted|RESULT)" || true
if printf '%s' "$out" | grep -aq "RESULT: BROWSER JOINED" && printf '%s' "$out" | grep -aqE "accepted    = [1-9]"; then
	echo "==> HG-06 PASSED (fresh export; a real browser joined and the engine accepted its intents)"
	exit 0
fi
echo "==> HG-06 FAILED: the browser did not join or nothing was accepted (rc=$rc)"
printf '%s\n' "$out" | tail -12
exit 1
