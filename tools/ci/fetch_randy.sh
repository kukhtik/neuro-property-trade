#!/usr/bin/env bash
# Fetch the upstream "Randy" server - the official Neuro-API stand-in - so the RANDY-01
# gate can run against it.
#
# WHY NOT VENDORED. Randy lives in the upstream VedalAI/neuro-sdk repo, and this repository
# vendors only the Godot SDK (game/addons/neuro-sdk). Vendoring the server too would mean
# shipping upstream node dependencies and a second copy of upstream code that the SDK
# already updates. Instead the gate fetches it into the scratch area on demand.
#
# WHAT IT IS. Randy "is a simple websocket server designed to mimic Neuro" - the SDK's own
# documentation tells integrators to test against it. It picks a RANDOM action from the
# forced set and answers a failed result by re-sending the same action, so the seat has to
# cope with an action it did not expect. That is more than our own mock does.
#
# Usage:
#   bash tools/ci/fetch_randy.sh              # fetch + install into the scratch area
#   bash tools/ci/fetch_randy.sh --check      # only report what is there
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

# NATIVE paths for native programs (python, node): they cannot open MSYS "/c/..." paths -
# the same trap that makes `git -C /c/...` fail silently. `pwd -W` gives the Windows form.
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

randy_dir="${NPT_RANDY_DIR:-${TMPDIR:-/tmp}/npt-randy}"
mode="${1:-install}"

# node 24 is the version the SDK's own tooling expects; node 26 falls over on
# better-sqlite3, so prefer 24 when it is installed.
node_bin="node"
for cand in "/c/Program Files/nodejs/node.exe" node; do
	if [ -x "$cand" ] || command -v "$cand" >/dev/null 2>&1; then
		node_bin="$cand"
		break
	fi
done

if [ "$mode" = "--check" ]; then
	if [ -f "$randy_dir/index.ts" ] && [ -d "$randy_dir/node_modules" ]; then
		echo "Randy is present in $randy_dir"
		exit 0
	fi
	echo "Randy is NOT in $randy_dir"
	exit 1
fi

if [ ! -x "$node_bin" ] && ! command -v node >/dev/null 2>&1; then
	echo "fetch_randy: no node runtime found - Randy needs node (24 recommended)"
	exit 1
fi

mkdir -p "$randy_dir"
cd "$repo"

for f in index.ts package.json tsconfig.json; do
	if ! command -v gh >/dev/null 2>&1; then
		echo "fetch_randy: the gh CLI is not available; fetch these by hand into $randy_dir:"
		echo "  https://raw.githubusercontent.com/VedalAI/neuro-sdk/main/Randy/$f"
		exit 1
	fi
	gh api "repos/VedalAI/neuro-sdk/contents/Randy/$f" --jq '.content' 2>/dev/null | base64 -d > "$randy_dir/$f" || {
		echo "fetch_randy: could not fetch $f"
		exit 1
	}
done
echo "fetched the upstream Randy server into $randy_dir"

# Two adjustments to the upstream file, both minimal and both needed:
#   1. the ports become environment variables, so the gate can pick FREE ones instead of
#      colliding with a stale instance (a collision makes our server die with EADDRINUSE
#      while the log we then read belongs to the stranger);
#   2. the log loses its ANSI colour, so the gate can grep it (util.inspect colours the
#      strings, and "command: 'actions/register'" with a colour escape inside the quotes
#      does not match the pattern - the gate would count zero and pass on nothing).
# The two adjustments live in a python file, not in a heredoc: a nested heredoc inside a
# shell script is where backslashes and quotes go to die.
PY=""
for cand in python python3 "py -3"; do
	if command -v "$cand" >/dev/null 2>&1 && $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "fetch_randy: no python for the port/colour patch; run tools/ci/patch_randy.py by hand"
	exit 1
fi
# native() converts a DIRECTORY (it cd's into it). The file inside it must be appended
# afterwards - asking native() about the file itself would fail the cd and fall back to the
# MSYS path, which the native python cannot open ("can't open file 'C:\\c\\Users\\...'").
patch_py="$(native "$repo/tools/ci")/patch_randy.py"
$PY "$patch_py" "$(native "$randy_dir")/index.ts" || exit 1

randy_win="$(native "$randy_dir")"
cd "$randy_win" || exit 1
if [ ! -d node_modules ]; then
	echo "installing the upstream dependencies (ws, express, body-parser, json-schema-faker, tsx)..."
	npm install --no-audit --no-fund >/dev/null 2>&1 || {
		echo "fetch_randy: npm install failed - Randy needs its dependencies"
		exit 1
	}
	echo "dependencies installed"
fi

echo "Randy is ready in $randy_dir"
echo "run the gate with: NPT_RANDY_DIR=$randy_win bash tools/ci/gates/randy01_gate.sh"
exit 0
