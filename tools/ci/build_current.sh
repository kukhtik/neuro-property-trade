#!/usr/bin/env bash
# Rebuild the FRESH artifacts — build/current/{windows,web} — from the working tree.
#
# WHY THIS EXISTS: HG-11 says no report may lean on a build older than the code sitting next to
# it, and the rule was "rebuild after every commit that touches game/". Nothing did it: the two
# fresh artifacts had been exported BY HAND once, so the first commit that touched `game/`
# afterwards (the SG-07 capture + the UI-core test module) made them stale and HG-11 went red -
# correctly. This is that rebuild, as a command instead of a memory.
#
# The VERDICT IS READ FROM THE FILES, never from the export's exit code: a failed export leaves
# the previous artifact in place and Godot still exits 0, which is exactly how a stale .exe
# survives a "successful" build.
#
#   tools/ci/build_current.sh              # both halves
#   tools/ci/build_current.sh --windows    # desktop only (faster)
#   tools/ci/build_current.sh --web        # web only
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
cd "$repo" || exit 1
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash tools/ci/godot_bin.sh)"
if [ -z "$godot" ]; then
	echo "==> BUILD FAILED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 1
fi

want="${1:---all}"
mkdir -p build/current/windows build/current/web
rm -f build/current/windows/*.exe build/current/web/index.html

# the import pass writes the class cache the exports resolve `class_name` globals from
"$godot" --headless --path game --import >/dev/null 2>&1

if [ "$want" != "--web" ]; then
	echo "[windows] export"
	"$godot" --headless --path game --export-release "Windows Desktop" \
		"$(native build/current/windows)/NeuroPropertyTrade.exe" 2>&1 | tail -2
	if [ ! -f build/current/windows/NeuroPropertyTrade.exe ]; then
		echo "==> BUILD FAILED: build/current/windows/NeuroPropertyTrade.exe was not produced"
		exit 1
	fi
	echo "windows ok: $(stat -c '%s bytes, %y' build/current/windows/NeuroPropertyTrade.exe | cut -c1-40)"
fi

if [ "$want" != "--windows" ]; then
	echo "[web] export"
	"$godot" --headless --path game --export-release "Web" \
		"$(native build/current/web)/index.html" 2>&1 | tail -2
	if [ ! -f build/current/web/index.html ]; then
		echo "==> BUILD FAILED: build/current/web/index.html was not produced"
		exit 1
	fi
	# a web bundle that does not boot is worse than none: the same check build_all.sh uses
	if ! bash tools/ci/verify_web_build.sh build/current/web; then
		echo "==> BUILD FAILED: the web bundle is not bootable"
		exit 1
	fi
	echo "web ok: $(ls build/current/web | tr '\n' ' ')"
fi

echo "==> BUILD CURRENT ok ($want)"
