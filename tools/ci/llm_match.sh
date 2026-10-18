#!/usr/bin/env bash
# One match with a REAL language model on the SDK seat (pipeline stall hunt).
#
# Starts tools/ci/llm_seat.py (a websocket seat that asks an opencode free model what to do),
# reads its port, then runs game/tools/llm_match.gd with NEURO_SDK_WS_URL pointed at it.
# The seat's log is kept next to the match log, so a stall can be attributed:
#   build/llm/seat.log   LLM / FALLBACK lines with per-decision latency
#   build/llm/match.log  rounds, intents per seat, event histogram, stalls
#
# Run: bash tools/ci/llm_match.sh [--model opencode/deepseek-v4.1-flash-free] [--think 60]
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

model="opencode/deepseek-v4.1-flash-free"
think=60
seat_flags=""
while [ $# -gt 0 ]; do
	case "$1" in
		--model) model="$2"; shift 2 ;;
		--think) think="$2"; shift 2 ;;
		# a dead bridge: the seat connects and never answers (proves the SDK-side timeout)
		--silent) seat_flags="--silent"; shift ;;
		*) echo "usage: llm_match.sh [--model provider/model] [--think seconds] [--silent]" >&2; exit 2 ;;
	esac
done

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> LLM-MATCH FAILED: no Godot binary"
	exit 1
fi
PY=""
for cand in "python" "python3" "py -3"; do
	if $cand -c "import sys" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
	echo "==> LLM-MATCH FAILED: no working python for the seat"
	exit 1
fi

mkdir -p "$repo/build/llm"
seat_log="$repo/build/llm/seat.log"
match_log="$repo/build/llm/match.log"
: > "$seat_log"

seat_dir="$(native "$here")"
$PY "$seat_dir/llm_seat.py" --model "$model" --think "$think" --timeout 300 $seat_flags >"$seat_log" 2>&1 &
SEAT_PID=$!
cleanup() { kill "$SEAT_PID" 2>/dev/null || true; }
trap cleanup EXIT

port=""
for _i in $(seq 1 80); do
	port=$(grep -oE 'LLM_PORT=[0-9]+' "$seat_log" 2>/dev/null | head -1 | cut -d= -f2)
	[ -n "$port" ] && break
	sleep 0.25
done
if [ -z "$port" ]; then
	echo "==> LLM-MATCH FAILED: the seat did not start (see build/llm/seat.log)"
	tail -5 "$seat_log" 2>/dev/null || true
	exit 1
fi
echo "==> LLM-MATCH seat on 127.0.0.1:$port model=$model"

NEURO_SDK_WS_URL="ws://127.0.0.1:$port" \
	timeout 420 "$godot" --headless --path "$(native "$repo/game")" res://tools/llm_match.tscn \
	>"$match_log" 2>&1
grep -aE "^MATCH|^==>" "$match_log" | tail -20 || true

echo "==> LLM-MATCH seat summary:"
grep -aE "^SEAT_SUMMARY|^seat: (LLM|FALLBACK|SILENT)" "$seat_log" | tail -8 || true

if grep -aq "==> LLM-MATCH DONE" "$match_log" || grep -aq "==> LLM-MATCH ADVANCING" "$match_log"; then
	exit 0
fi
reason="$(grep -aE '==> LLM-MATCH STALLED' "$match_log" | head -1)"
echo "${reason:-==> LLM-MATCH FAILED: no verdict line from the match scene (see build/llm/match.log)}"
exit 1
