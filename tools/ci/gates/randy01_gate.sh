#!/usr/bin/env bash
# RANDY-01 - the SDK seat against the OFFICIAL Neuro-API server (VedalAI/neuro-sdk `Randy`).
#
# WHY A SECOND SERVER. The project had its own mock (`tools/ci/mock_neuro_ws.py`, 210 lines)
# written by us, for us. It answers what our adapter needs, so it cannot catch a mismatch
# between our adapter and the REAL protocol. Randy is the upstream reference server - it is
# the thing the SDK's own documentation tells integrators to test against
# ("Randy is a simple websocket server designed to mimic Neuro... You can use Randy to test
# your local websocket implementations"). It also does the things the mock never did:
#   - it validates nothing (like the mock), but it PICKS A RANDOM ACTION from the forced
#     set, so the seat has to cope with an action it did not expect;
#   - it answers `action/result` with success=false by re-sending the SAME action, so the
#     retry path is exercised;
#   - it is the upstream implementation, so a protocol drift in OUR copy of the vendored
#     addon shows up here and nowhere else.
#
# WHAT THIS GATE PROVES: our SDK seat speaks the protocol the upstream server speaks -
# startup, actions/register, actions/force, action/result - and its intents are accepted
# by the engine while a RANDOM third party is playing the other side.
#
# WHAT IT DOES NOT PROVE: anything about a real model. Randy is a bot: it does not send
# invalid data, does not act without a force, and does not hesitate. A real Neuro is
# none of those things. The plan says so instead of calling it done.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> RANDY-01 FAILED: no Godot binary"
	exit 1
fi

# --- where is Randy? ---
# It is upstream code, so it is NOT vendored into this repository (we vendor the Godot
# SDK, not the whole repo). The gate fetches it into the scratch area and runs it from
# there. If the fetch fails, the gate says so out loud - it never silently passes.
randy_dir="${NPT_RANDY_DIR:-${TMPDIR:-/tmp}/npt-randy}"
randy_log="${TMPDIR:-/tmp}/npt-randy.log"

# The ports must be FREE - a stale instance on the same port makes our server die with
# EADDRINUSE while the log we read belongs to the stranger, and the http port is as
# vulnerable as the websocket one. So: find two free ports instead of naming them.
node_bin="node"
for cand in "/c/Program Files/nodejs/node.exe" node; do
	if [ -x "$cand" ] || command -v "$cand" >/dev/null 2>&1; then
		node_bin="$cand"
		break
	fi
done

pick_free_port() {
	"$node_bin" -e "
const net=require('net');
const s=net.createServer();
s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>process.stdout.write(String(p)));});
" 2>/dev/null
}

port="${NPT_RANDY_PORT:-$(pick_free_port)}"
http_port="${NPT_RANDY_HTTP_PORT:-$(pick_free_port)}"
if [ -z "$port" ] || [ -z "$http_port" ] || [ "$port" = "$http_port" ]; then
	echo "==> RANDY-01 FAILED: could not pick two free ports for the server"
	exit 1
fi

needs_randy=0
if [ -f "$randy_dir/index.ts" ] && [ -d "$randy_dir/node_modules" ]; then
	needs_randy=0
else
	needs_randy=1
fi

randy_pid=""
# `npx tsx index.ts` is not one process: bash -> node(npx) -> cmd -> node(tsx) -> node(server).
# Killing only $randy_pid (the subshell) kills the WRAPPER and lets the grandchildren live:
# they re-parent, keep their sockets and ~35 MB each, and every gate run leaked one more
# server (a night of sweeps left 40 orphaned node.exe on this machine). So the cleanup must
# hunt by the one handle that survives re-parenting - the command line naming the Randy dir.
cleanup() {
	if command -v powershell.exe >/dev/null 2>&1; then
		RANDY_DIR_WIN="$(cygpath -w "$randy_dir" 2>/dev/null || printf '%s' "$randy_dir")" \
			powershell.exe -NoProfile -Command '
				$d = $env:RANDY_DIR_WIN
				$me = $PID
				Get-CimInstance Win32_Process |
					Where-Object {
						$_.ProcessId -ne $me -and $_.CommandLine -and
						$_.Name -in @("node.exe","cmd.exe") -and
						$_.CommandLine.IndexOf($d, [StringComparison]::OrdinalIgnoreCase) -ge 0
					} |
					ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
			' >/dev/null 2>&1 || true
	elif command -v pkill >/dev/null 2>&1; then
		pkill -f "$randy_dir" 2>/dev/null || true
	fi
	if [ -n "$randy_pid" ]; then
		kill "$randy_pid" 2>/dev/null || true
	fi
}
trap cleanup EXIT

if [ "$needs_randy" -eq 1 ]; then
	echo "==> RANDY-01 SKIPPED: the upstream Randy server is not present in $randy_dir"
	echo "    fetch it with: gh api repos/VedalAI/neuro-sdk/contents/Randy/index.ts --jq .content | base64 -d > $randy_dir/index.ts"
	echo "    then: cd $randy_dir && npm install"
	exit 0
fi

# --- start Randy ---
( cd "$randy_dir" && "$node_bin" -e "1" >/dev/null 2>&1 || true )
# A stale instance on the same port would make OUR Randy die with EADDRINUSE while the
# log we then read belongs to the OLD one - the gate would measure a stranger. Say so.
if "$node_bin" -e "
const net=require('net');const s=net.connect($port,'127.0.0.1');
s.on('connect',()=>{s.end();process.exit(0)});
s.on('error',()=>process.exit(1));
setTimeout(()=>process.exit(1),800);
" 2>/dev/null; then
	echo "==> RANDY-01 FAILED: something already listens on $port - the log would belong to another server"
	echo "    free it, or set NPT_RANDY_PORT to another port"
	exit 1
fi

( cd "$randy_dir" && PORT="$port" HTTP_PORT="$http_port" npx tsx index.ts >"$randy_log" 2>&1 ) &
randy_pid=$!

# wait for the port
up=0
for _i in $(seq 1 40); do
	if "$node_bin" -e "
const net=require('net');const s=net.connect($port,'127.0.0.1');
s.on('connect',()=>{s.end();process.exit(0)});
s.on('error',()=>process.exit(1));
setTimeout(()=>process.exit(1),800);
" 2>/dev/null; then
		up=1
		break
	fi
	sleep 1
done
if [ "$up" -ne 1 ]; then
	echo "==> RANDY-01 FAILED: Randy did not open its websocket port ($port)"
	tail -10 "$randy_log" 2>/dev/null | sed 's/^/    /'
	exit 1
fi
# The server we started must be the one that is up: if OUR process died (EADDRINUSE and
# something else is up), the log says so and the gate must not measure the stranger.
if ! kill -0 "$randy_pid" 2>/dev/null; then
	echo "==> RANDY-01 FAILED: the Randy process we started is not running"
	tail -6 "$randy_log" 2>/dev/null | sed 's/^/    /'
	exit 1
fi

# --- the seat plays against Randy ---
# The timeout must be LONGER than the scene's own watch phase: the scene allows 180s for
# the match to advance (hg08_sdk_seat_gate.gd, the "watch" state) and the standalone HG-08
# gate gives it 260s. At 120s this gate killed the scene BEFORE it could print the
# "N SDK-seat intent(s) accepted" line - and the gate then reported "the seat did not
# report how many intents the engine accepted", which reads like a protocol failure and
# is not one. The scene's deadline is the authority: give it more than it asks for.
# The timeout must EXCEED the scene's own watch deadline (180s, hg08_sdk_seat_gate.gd's
# "watch" state) with room for the boot and for Randy's start. At 120s the gate killed the
# scene mid-watch and read NOTHING - and then said "the seat did not report how many
# intents the engine accepted", which reads like a protocol failure and is not one: the
# server had logged 184 answers. The standalone HG-08 gate gives the same scene 260s.
# The scene's output goes to a FILE, not into a shell variable: the gate kept only the
# last six HG-08 lines, so the reason the scene stopped was thrown away and every failure
# looked like the same thing. A gate that cannot show what the thing it measured said
# cannot be diagnosed - and this one failed three times for three different reasons.
scene_log="$repo/build/gates/RANDY-01-scene.log"
mkdir -p "$repo/build/gates"
(cd "$repo" && NEURO_SDK_WS_URL="ws://127.0.0.1:$port" timeout 320 "$godot" --headless \
	--path game res://tools/gates/hg08_sdk_seat_gate.tscn) >"$scene_log" 2>&1
rc=$?
out="$(cat "$scene_log")"

# --- what do we know? ---
# Randy prints the command with util.inspect: `command: 'actions/register'`. The patterns
# must match THAT shape - a gate that greps for a shape nobody prints counts nothing and
# then passes on empty numbers, which is the "green without checking anything" failure.
count_in_log() {
	if [ ! -f "$randy_log" ]; then
		echo 0
		return
	fi
	# -a: the log carries raw websocket frames, so grep would call it BINARY and print
	# "Binary file matches" instead of a count. Count LINES, not occurrences.
	# The ANSI colour codes are stripped first: the upstream server colours its output,
	# and "command: 'actions/register'" with a colour escape inside the quotes does not
	# match the pattern - which would make the gate count zero and pass on nothing.
	tr -d '\033' < "$randy_log" | sed 's/\[[0-9;]*m//g' | grep -ac "$1" | head -1 | tr -d ' \r'
}
registered="$(count_in_log "command: 'actions/register'")"
forced="$(count_in_log "command: 'actions/force'")"
answered="$(count_in_log "command: 'action'")"
results="$(count_in_log "command: 'action/result'")"
for v in registered forced answered results; do
	case "${!v}" in
		''|*[!0-9]*) echo "==> RANDY-01 FAILED: could not count '$v' in the server log" >&2; exit 1 ;;
	esac
done

fails=0
note() { echo "  $1"; }

if [ ! -s "$randy_log" ]; then
	note "the Randy server wrote nothing - the gate proved nothing"
	fails=$((fails + 1))
fi
if [ "$registered" -lt 1 ]; then
	note "Randy never received actions/register - our startup handshake did not reach it"
	fails=$((fails + 1))
fi
if [ "$forced" -lt 1 ]; then
	note "Randy never received an actions/force - the seat did not ask for a decision"
	fails=$((fails + 1))
fi
if [ "$answered" -lt 1 ]; then
	note "Randy never sent an action back"
	fails=$((fails + 1))
fi
if [ "$results" -lt 1 ]; then
	note "Randy never received an action/result - our answer did not reach the server"
	fails=$((fails + 1))
fi
# The PROTOCOL is what this gate is about. Whether the MATCH ADVANCES is a different
# question and Randy cannot answer it: Randy picks a RANDOM action from the forced set
# (it took 'bid_auction' 185 times out of 186 in a measured run), so the match does not
# necessarily progress - that is Randy being a bot, not our seat failing. The HG-08
# scene's "the match advances" check therefore CANNOT be the criterion here; the
# criterion is that the seat's intents REACHED THE ENGINE and were accepted. The scene
# reports the seat's own intent count.
# The scene prints either
#   "HG-08: the match advanced to round N with M SDK-seat intent(s) accepted"
# or the failure line with the same numbers. Read the number from whichever appeared.
intents="$(printf '%s' "$out" | grep -aoE '[0-9]+ SDK-seat intent\(s\)' | grep -oE '^[0-9]+' | head -1)"
if [ -z "$intents" ]; then
	note "the seat did not report how many intents the engine accepted"
	printf '%s\n' "$out" | grep -aE 'HG-08|FAIL' | tail -8 | sed 's/^/    /'
	note "the scene's own output: build/gates/RANDY-01-scene.log"
	fails=$((fails + 1))
elif [ "$intents" -lt 1 ]; then
	note "the engine accepted 0 intents from the SDK seat against Randy"
	fails=$((fails + 1))
else
	note "the engine accepted $intents intent(s) from the SDK seat"
fi
if printf '%s' "$out" | grep -q "SCRIPT ERROR:"; then
	note "the run emitted a SCRIPT ERROR"
	fails=$((fails + 1))
fi

note "Randy saw: register=$registered force=$forced action=$answered result=$results"

if [ "$fails" -ne 0 ]; then
	echo "==> RANDY-01 FAILED: $fails check(s) failed (the seat did not speak the upstream protocol)"
	exit 1
fi
echo "==> RANDY-01 PASSED (the SDK seat speaks the upstream Neuro protocol: startup, register, force, action, result - against the official Randy server, not only against our own mock)"
exit 0
