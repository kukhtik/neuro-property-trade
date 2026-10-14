#!/usr/bin/env bash
# SG-10 - the perf report (docs/restoration/gates.md SG-10).
#
# "Только tools/fps_clean.py, только на чистой машине": a host (the fresh desktop build, which
# now writes PERF fps lines again - the swap had archived the sampler with the old overlay) plus
# one real browser as the friend, nothing else on the box. The script's own preflight refuses to
# start next to another host/serve.py, so a number is never taken while the machine competes
# with itself.
#
# Thresholds: browser median >= 30 is the script's regression signal (exit 1); the local budget
# I-7 wants >= 40 and BOTH role builds at or above it. No playwright / no display => SKIPPED
# (reported, not blocking - CI machines have no GPU). A hidden page (exit 2) is an environment
# artifact, not a result: SKIPPED with the reason.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

mkdir -p "$repo/build/gates"
out="$repo/build/gates/SG-10-fps.txt"

# an interpreter that actually has playwright (py -3.12 locally, python* elsewhere), and it must
# be able to launch a browser at all
PY=""
for cand in "py -3.12" "python" "python3"; do
	if $cand -c "import playwright" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> SG-10 SKIPPED: no python with playwright - run the perf report locally (tools/fps_clean.py)"
	exit 0
fi

if ! bash -c "cd '$repo' && $PY tools/fps_clean.py" >"$out" 2>&1; then
	rc=$?
	if grep -aq "НЕДЕЙСТВИТЕЛЕН" "$out"; then
		echo "==> SG-10 SKIPPED: the measurement was invalid (page throttled/hidden - see build/gates/SG-10-fps.txt)"
		exit 0
	fi
	if grep -aq "СТОП" "$out"; then
		echo "==> SG-10 SKIPPED: another host/serve.py was alive - the machine was competing with itself"
		exit 0
	fi
	echo "==> SG-10 FAILED: fps regression (see build/gates/SG-10-fps.txt)"
	grep -aE "ХОСТ|БРАУЗЕР|==> " "$out" | tail -4
	exit 1
fi

grep -aE "ХОСТ|БРАУЗЕР" "$out" | tail -2
if grep -aq "FPS OK" "$out"; then
	echo "==> SG-10 PASSED (clean-machine run: both role builds measured, browser median >= 30; see build/gates/SG-10-fps.txt)"
	exit 0
fi
echo "==> SG-10 FAILED: fps_clean exited 0 without an FPS OK verdict line"
exit 1
