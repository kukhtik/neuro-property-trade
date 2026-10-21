#!/usr/bin/env bash
# SOUND-EVENTS — the sounds are BOUND TO EVENTS (track 2, docs/tracks/2026-10-20-three-tracks.md §2).
#
# WHY IT EXISTS: `SOUND` proves the switch and the manager work when something calls them. It
# cannot tell "a beep on a button" from "a dice click when the dice roll". This gate runs a REAL
# match — real engine, real seat manager, four AI seats, the real `game_view` — and compares the
# sound log against the events the UI received:
#
#     roll xN -> dice xN · purchase xM -> buy xM · auction_bid/jail/card_*/winner...
#
# Both directions are measured in the same run (the negative is not a manual step):
#     replay the recorded events with sound OFF -> 0 played, refusals recorded
#     replay the same events with sound ON      -> the same count as the live match
#
# The measuring part is game/tools/gates/sound_events_gate.gd. The expectation table lives in
# THAT file, duplicated from the product on purpose: reading the product's own map would make the
# gate agree with whatever the product does.
#
# Verdict: ==> SOUND-EVENTS PASSED ... / ==> SOUND-EVENTS FAILED: <first reason> / SKIPPED
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> SOUND-EVENTS SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

# the assets must be importable: a fresh clone has no .godot/ cache, and `load()` of a .wav then
# returns null - the gate would report "the WAV did not load" instead of measuring the binding.
if [ ! -d "$repo/game/.godot/imported" ]; then
	echo "==> SOUND-EVENTS: importing assets first (no game/.godot/imported yet)"
	"$godot" --headless --path "$(native "$repo/game")" --import >/dev/null 2>&1 || true
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/sound-events.log"
# the match is driven by AI seats on wall-clock: it stops after a few turns, not at a frame count
timeout 300 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/gates/sound_events_gate.tscn >"$log" 2>&1
tr -d '\r' <"$log" >"$log.norm" && mv "$log.norm" "$log"

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> SOUND-EVENTS FAILED: SCRIPT ERROR while running the match: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "==> SOUND-EVENTS FAILED" "$log"; then
	echo "==> SOUND-EVENTS FAILED: $(grep -a '==> SOUND-EVENTS FAILED' "$log" | head -1 | sed 's/.*==> SOUND-EVENTS FAILED:[[:space:]]*//')"
	exit 1
fi

if ! grep -aq "==> SOUND-EVENTS PASSED" "$log"; then
	echo "==> SOUND-EVENTS FAILED: the match printed no verdict line (did the scene run?) - see build/gates/sound-events.log"
	exit 1
fi

# the per-sound table is the evidence: print it above the verdict, like every other gate here
grep -aE "^    (dice|buy|bid|jail|card|mortgage|game_over|error|toast|turn|tick|replay)" "$log" || true
grep -a "==> SOUND-EVENTS PASSED" "$log"
exit 0
