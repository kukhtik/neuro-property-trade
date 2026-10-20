#!/usr/bin/env bash
# CHAT-01 - the Twitch chat seat (promise S2, docs/program.md P1.2).
#
# The promise had every piece and NO acceptance test: the bridge
# (tools/ci/twitch_bridge.py), the seat driver (seats/drivers/chat_driver.gd), the server
# entry (game_server._on_chat -> seat_manager.push_chat) and the engine's own validation.
# `grep -c CHAT-01 tools/ci/run_gates.sh` was 0.
#
# WHAT THIS GATE PROVES (no network, no token):
#   1. the bridge's vote grammar and anti-flood rule (its own --selftest);
#   2. the seat driver: majority wins, illegal votes are ignored, a SILENT box does not
#      stall the match (the auto-roll), and the driver submits THROUGH the manager so the
#      events reach the journal;
#   3. the seat in a real match: a vote buys a property, and the engine rejects an illegal
#      bid (the engine is the authority; the chat seat only proposes);
#   4. the frame the bridge sends is the frame the server reads (protocol round trip).
#
# WHAT IT DOES NOT PROVE: the live IRC socket (needs a channel token) and the browser
# client that would carry the frame. Both are external by nature, and the plan says so
# instead of calling them done.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

PY=""
for cand in python python3 "py -3"; do
	if command -v "$cand" >/dev/null 2>&1 && $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> CHAT-01 FAILED: no python interpreter for the bridge selftest"
	exit 1
fi

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> CHAT-01 FAILED: no Godot binary"
	exit 1
fi

fails=0
note() { echo "  $1"; }

# --- 1. the bridge: grammar, anti-flood, the frame it sends ---
out="$(cd "$repo" && $PY tools/ci/twitch_bridge.py --selftest 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
	note "the bridge selftest failed (exit $rc):"
	printf '%s\n' "$out" | tail -5 | sed 's/^/    /'
	fails=$((fails + 1))
elif ! printf '%s' "$out" | grep -q "BRIDGE SELFTEST PASSED"; then
	note "the bridge selftest did not print its verdict line"
	fails=$((fails + 1))
else
	note "bridge selftest: $(printf '%s' "$out" | grep -o 'BRIDGE SELFTEST PASSED: .*')"
fi

# --- 2/3. the seat: the tests that pin the promise ---
out="$(cd "$repo" && "$godot" --headless --path game --script res://tests/run.gd 2>&1)"
rc=$?
if printf '%s' "$out" | grep -q "SCRIPT ERROR"; then
	note "the suite emitted a SCRIPT ERROR"
	fails=$((fails + 1))
fi
# The chat tests are named, so a failure says WHICH promise broke - not just a count.
chat_fail="$(printf '%s' "$out" | grep -cE 'ERROR: chat_test\.gd' || true)"
if [ "${chat_fail:-0}" -ne 0 ]; then
	note "the chat seat tests failed:"
	printf '%s\n' "$out" | grep -E 'ERROR: chat_test\.gd' | head -5 | sed 's/^/    /'
	fails=$((fails + 1))
fi
ran="$(printf '%s' "$out" | grep -oE 'ran [0-9]+ tests' | head -1)"
if [ -z "$ran" ]; then
	note "the suite did not report a test count"
	fails=$((fails + 1))
else
	note "suite: $ran, 0 chat failures"
fi

# --- 4. the registry: a gate that is not registered is not a gate ---
if ! grep -q '"CHAT-01|' "$repo/tools/ci/run_gates.sh"; then
	note "CHAT-01 is not in the gate registry - a gate that is not registered is not a gate"
	fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then
	echo "==> CHAT-01 FAILED: $fails check(s) failed (the chat seat is the promise S2)"
	exit 1
fi
echo "==> CHAT-01 PASSED (the chat seat votes: majority wins, illegal votes are rejected by the engine, a silent box rolls on instead of stalling the match; the bridge grammar and the protocol frame are checked too)"
exit 0
