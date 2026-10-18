#!/usr/bin/env bash
# MULTI-SDK gate: two SDK seats, two connections, one process.
#
# Starts TWO mocks (tools/ci/mock_neuro_ws.py, one per seat), hands their ports to the game as
# NPT_SDK_A / NPT_SDK_B and runs game/tools/multi_sdk_probe.gd. The probe passes only when both
# seats are connected and both have intents accepted by the engine - i.e. when the connections are
# genuinely separate (before this, the second sdk: seat was silently downgraded to AI).
#
# Run: bash tools/ci/multi_sdk_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> MULTI-SDK FAILED: no Godot binary"
	exit 1
fi
PY=""
for cand in "python" "python3" "py -3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
	echo "==> MULTI-SDK FAILED: no working python for the mocks"
	exit 1
fi

mkdir -p "$repo/build/gates"
mock_dir="$(native "$here")"
"$PY" "$mock_dir/mock_neuro_ws.py" 0 240 >"$repo/build/gates/MULTI-SDK-mock-a.log" 2>&1 &
A_PID=$!
"$PY" "$mock_dir/mock_neuro_ws.py" 0 240 >"$repo/build/gates/MULTI-SDK-mock-b.log" 2>&1 &
B_PID=$!
cleanup() { kill "$A_PID" 2>/dev/null || true; kill "$B_PID" 2>/dev/null || true; }
trap cleanup EXIT

port_of() {
	local log="$1" p=""
	for _i in $(seq 1 80); do
		p=$(grep -oE 'MOCK_PORT=[0-9]+' "$log" 2>/dev/null | head -1 | cut -d= -f2)
		[ -n "$p" ] && break
		sleep 0.25
	done
	printf '%s' "$p"
}
A_PORT="$(port_of "$repo/build/gates/MULTI-SDK-mock-a.log")"
B_PORT="$(port_of "$repo/build/gates/MULTI-SDK-mock-b.log")"
if [ -z "$A_PORT" ] || [ -z "$B_PORT" ]; then
	echo "==> MULTI-SDK FAILED: a mock did not start (see build/gates/MULTI-SDK-mock-*.log)"
	exit 1
fi
echo "==> MULTI-SDK mocks on 127.0.0.1:$A_PORT and 127.0.0.1:$B_PORT"

NPT_SDK_A="ws://127.0.0.1:$A_PORT" NPT_SDK_B="ws://127.0.0.1:$B_PORT" \
	timeout 240 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/multi_sdk_probe.tscn >"$repo/build/gates/MULTI-SDK.log" 2>&1
grep -aE "^MULTI-SDK|^==>" "$repo/build/gates/MULTI-SDK.log" | tail -12 || true

if grep -aq "==> MULTI-SDK PASSED" "$repo/build/gates/MULTI-SDK.log"; then
	exit 0
fi
reason="$(grep -aE '==> MULTI-SDK FAILED' "$repo/build/gates/MULTI-SDK.log" | head -1)"
echo "${reason:-==> MULTI-SDK FAILED: no verdict line (see build/gates/MULTI-SDK.log)}"
exit 1
