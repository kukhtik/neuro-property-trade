#!/usr/bin/env bash
# HG-08 - the SDK seat plays against a mock Neuro websocket (docs/restoration/gates.md HG-08).
#
# The audit's finding: an SDK seat had NO ACTOR - seat_manager never spawned the adapter, so
# the match stalled on the seat's first decision. This gate proves the seat plays:
#   1. it starts `tools/ci/mock_neuro_ws.py` (stdlib-only websocket server that answers every
#      force with one offered action) and reads its port from the log;
#   2. it runs `game/tools/gates/hg08_sdk_seat_gate.tscn` with NEURO_SDK_WS_URL pointed at the
#      mock - the vendored addon reads that env var at process start;
#   3. the verdict comes from the GATE SCENE's line; the mock log is kept as evidence
#      ("mock: <- force [...] -> action roll_dice id=N").
#
# No python? The gate FAILS (not skips): the mock is stdlib-only, a machine without python
# cannot run half of this repo's tooling anyway.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> HG-08 FAILED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 1
fi

# `python` FIRST (the local Windows convention in run_gates.sh), then python3 (CI), then the
# py launcher - and every candidate must PROVE it runs: on Windows `python3` is often a
# Store stub that prints a banner and exits 9009, which is how the first version of this gate
# "failed to start" a mock that works perfectly by hand.
PY=""
for cand in "python" "python3" "py -3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> HG-08 FAILED: no working python interpreter for the mock websocket server"
	exit 1
fi

mkdir -p "$repo/build/gates"
mock_log="$repo/build/gates/HG-08-mock.log"
mock2_log="$repo/build/gates/HG-08-mock-soak.log"
gate_log="$repo/build/gates/HG-08.log"
soak_log="$repo/build/gates/HG-08-soak.log"

mock_dir="$(dirname "$repo/tools/ci/mock_neuro_ws.py")"
mock_win="$(native "$mock_dir")/$(basename "$repo/tools/ci/mock_neuro_ws.py")"
$PY "$mock_win" 0 300 >"$mock_log" 2>&1 &
MOCK_PID=$!
cleanup() { kill "$MOCK_PID" 2>/dev/null || true; if [ -n "${MOCK2_PID:-}" ]; then kill "$MOCK2_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT

port=""
for _i in $(seq 1 60); do
	port=$(grep -oE 'MOCK_PORT=[0-9]+' "$mock_log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$port" ] && break
	sleep 0.25
done
if [ -z "$port" ]; then
	echo "==> HG-08 FAILED: the mock websocket server did not start (see build/gates/HG-08-mock.log)"
	tail -4 "$mock_log" 2>/dev/null || true
	exit 1
fi
echo "==> HG-08 mock listening on 127.0.0.1:$port"

NEURO_SDK_WS_URL="ws://127.0.0.1:$port" \
	timeout 260 "$godot" --headless --path "$(native "$repo/game")" res://tools/gates/hg08_sdk_seat_gate.tscn \
	>"$gate_log" 2>&1
grep -aE "^HG-08|^FAIL|^==>" "$gate_log" | tail -8 || true

if ! grep -aq "==> HG-08 PASSED" "$gate_log"; then
	reason="$(grep -aE "==> HG-08 FAILED" "$gate_log" | head -1)"
	if [ -z "$reason" ]; then
		reason="no verdict line from the gate scene (see build/gates/HG-08.log)"
	fi
	echo "$reason"
	tail -6 "$gate_log" 2>/dev/null || true
	exit 1
fi
if ! grep -aq "mock: <- force" "$mock_log"; then
	echo "==> HG-08 FAILED: the game claims PASSED but the mock never answered a force (evidence missing)"
	exit 1
fi

# --- invite latency: the force must arrive WITH the registration, not one turn clock later ------
# The vendored ActionWindow used to send the force only after `_force_timeout` (= turn_timer), so a
# seat was invited to its own turn a whole clock late. The mock stamps the gap between the first
# command (actions/register) and the first force; anything beyond a few seconds means the invitation
# is waiting for the clock again.
latency="$(grep -aoE 'INVITE_LATENCY=[0-9.]+' "$mock_log" | head -1 | cut -d= -f2)"
if [ -z "$latency" ]; then
	echo "==> HG-08 FAILED: the mock never recorded an invite latency (no INVITE_LATENCY line)"
	tail -6 "$mock_log" 2>/dev/null || true
	exit 1
fi
if ! awk -v l="$latency" 'BEGIN { exit !(l < 5.0) }'; then
	echo "==> HG-08 FAILED: the seat was invited ${latency}s after its actions were registered (want < 5s: the force must go out with the window, not after the turn clock)"
	exit 1
fi
echo "==> HG-08 invite latency ${latency}s (< 5s: the force goes out with the window)"

# --- scenario 2: the archive's seats soak (SDK+AI+AI+LOCAL) ------------------------------------
# A fresh mock: the first one exits once it answered a client.
$PY "$mock_win" 0 300 >"$mock2_log" 2>&1 &
MOCK2_PID=$!
port2=""
for _i in $(seq 1 60); do
	port2=$(grep -oE 'MOCK_PORT=[0-9]+' "$mock2_log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$port2" ] && break
	sleep 0.25
done
if [ -z "$port2" ]; then
	echo "==> HG-08 FAILED: the soak mock did not start (see build/gates/HG-08-mock-soak.log)"
	exit 1
fi
NEURO_SDK_WS_URL="ws://127.0.0.1:$port2" 	timeout 200 "$godot" --headless --path "$(native "$repo/game")" res://tools/seats_soak.tscn 	>"$soak_log" 2>&1
grep -aE "seats soak" "$soak_log" | tail -3 || true
if ! grep -aq "seats soak: PASSED" "$soak_log"; then
	echo "==> HG-08 FAILED: the seats soak (SDK+AI+AI+LOCAL) did not reach its cap without stalling"
	tail -6 "$soak_log" 2>/dev/null || true
	exit 1
fi

echo "==> HG-08 PASSED (an SDK seat played: adapter spawned, mock answered a force, intents accepted, match advanced; the SDK+AI+AI+LOCAL soak survived too)"
exit 0

reason="$(grep -aE "==> HG-08 FAILED" "$gate_log" | head -1)"
if [ -z "$reason" ]; then
	reason="no verdict line from the gate scene (see build/gates/HG-08.log)"
fi
echo "$reason"
tail -6 "$gate_log" 2>/dev/null || true
exit 1
