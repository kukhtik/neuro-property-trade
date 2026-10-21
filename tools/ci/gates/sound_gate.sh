#!/usr/bin/env bash
# SOUND — the "Звук" row is a SETTING, not decoration (track 2, docs/tracks/2026-10-20-three-tracks.md §2).
#
# WHY IT EXISTS: on 20.10.2026 the product had ZERO sound files, ZERO AudioStreamPlayer and no
# `game_settings.sound` field, while the settings sheet shipped a "Звук" checkbox. The checkbox
# wrote nothing — the same "the interface promises what the product does not have" class of lie
# the program calls critical. This gate:
#   1. builds the REAL settings sheet and toggles its REAL checkbox:
#        OFF -> collected settings carry sound=false, the manager refuses to play, counter stays 0
#        ON  -> collected settings carry sound=true,  one play is counted
#   2. demands the row is tagged LIVE (`settings.tag_live`), because the field it writes is read;
#   3. loads every registered sound from game/assets/audio/*.wav (12 synthesised files);
#   4. mutes on the master cosmetics switch (`SkinManager.animations_enabled` = the animations row);
#   5. runs tools/ci/unused_symbols.py and fails if `sound` is back in UNAPPLIED/ORPHAN — i.e. if
#      the field stops having a live consumer (a field nothing reads is the defect returning).
#
# The measuring part is game/tools/gates/sound_gate.gd (headless, no display needed).
# Verdict: ==> SOUND PASSED ... / ==> SOUND FAILED: <first reason> / ==> SOUND SKIPPED: <why>
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> SOUND SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/sound.log"
timeout 300 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/gates/sound_gate.tscn >"$log" 2>&1
tr -d '\r' <"$log" >"$log.norm" && mv "$log.norm" "$log"

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> SOUND FAILED: SCRIPT ERROR while measuring: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "==> SOUND FAILED" "$log"; then
	echo "==> SOUND FAILED: $(grep -a '==> SOUND FAILED' "$log" | head -1 | sed 's/.*==> SOUND FAILED:[[:space:]]*//')"
	exit 1
fi

if ! grep -aq "==> SOUND PASSED" "$log"; then
	echo "==> SOUND FAILED: the measurement printed no verdict line (did the scene run?) - see build/gates/sound.log"
	exit 1
fi

# ---- 5. `sound` must have a live product consumer (tools/ci/unused_symbols.py) -----------------
py=""
for cand in python python3; do
	if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" >/dev/null 2>&1; then
		py="$cand"
		break
	fi
done
if [ -z "$py" ]; then
	echo "==> SOUND SKIPPED: the measurement passed but no python for unused_symbols (the UNAPPLIED half is unproven)"
	exit 0
fi
unused="$("$py" "$repo/tools/ci/unused_symbols.py" 2>/dev/null | tr -d '\r')"
dead="$(printf '%s\n' "$unused" | grep -E "^(  ORPHAN|  UNAPPLIED).*game/core/game_settings\.gd[[:space:]]+sound[[:space:]]*$" || true)"
if [ -n "$dead" ]; then
	echo "==> SOUND FAILED: game_settings.sound has no live product consumer - unused_symbols reports: $(printf '%s' "$dead" | head -1 | sed 's/^ *//')"
	exit 1
fi

grep -a "==> SOUND PASSED" "$log"
echo "    unused_symbols: game_settings.sound is read by product code (not UNAPPLIED/ORPHAN)"
exit 0
