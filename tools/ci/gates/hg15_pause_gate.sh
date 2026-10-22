#!/usr/bin/env bash
# HG-15 — ОБЕЩАНИЕ ПАУЗЫ ИЗМЕРЕНО.
#
# ЧТО ОБЕЩАНО. Пауза в продукте — событие МАТЧА, а не одного экрана: `engine.paused`,
# `admin_override("pause"/"resume")`, отказ интентов на паузе, тишина `seat_manager._tick`
# (он зануляет `decision_waiting`), ключ `paused` в ОБЕИХ проекциях, чип «ПАУЗА» в шапке.
# Всё это есть — и всё это не измерял НИ ОДИН гейт: в реестре не было ни HG-15, ни VOICE-01,
# ни E-5, то есть три обещания приёмки висели TODO. Пауза без измерения — это пауза, о
# поломке которой узнают от игроков.
#
# ПОЧЕМУ ГЕЙТ, А НЕ ПРОСТО ТЕСТ. Тест меряет движок вне окна; здесь меряется ЖИВОЙ продукт:
# проба поднимает настоящий `MainScript` (профиль admin, как hg12/hg13), доводит матч до
# живого хода человека и работает с настоящим движком и настоящим `SeatManager`. Проба живёт
# рядом: `game/tools/hg15_pause_probe.tscn` (проба меряет, гейт выносит вердикт — как у
# PANELS-IN-RING и E-5).
#
# ЧЕГО ЭТОТ ГЕЙТ НЕ ДЕЛАЕТ: он не «скипает» при отсутствии измерения. Гейт, который ничего не
# измерил, не имеет права быть зелёным: нет бинарника, нет строки пробы, нет вердикта — это
# FAILED с причиной, а не тихий skip. Проба headless, дисплей ей не нужен, поэтому молчание —
# это отсутствие измерения, а не «нет экрана».
#
# Вердикт: ==> HG-15 PASSED (...) / ==> HG-15 FAILED: <причина>
# Run: bash tools/ci/gates/hg15_pause_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# NATIVE путь для нативного бинарника: godot не открывает MSYS-пути `/c/...`
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh" 2>/dev/null)"
if [ -z "$godot" ] || [ ! -e "$godot" ]; then
	echo "==> HG-15 FAILED: нет бинарника Godot (см. tools/ci/fetch_godot.sh) — измерение не сделано"
	exit 1
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/hg15-pause.log"
rc=0
timeout 300 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/hg15_pause_probe.tscn >"$log" 2>&1 || rc=$?

# НИ ОДНОЙ СТРОКИ ПРОБЫ — это не «нет дисплея», это отсутствие измерения: проба headless, ей
# дисплей не нужен, поэтому молчание = красный.
if ! grep -aq "HG-15 PROBE" "$log"; then
	echo "==> HG-15 FAILED: проба не сделала ни одной проверки (см. build/gates/hg15-pause.log)"
	exit 1
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> HG-15 FAILED: SCRIPT ERROR во время измерения: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "==> HG-15 FAILED" "$log"; then
	echo "==> HG-15 FAILED: $(grep -a '==> HG-15 FAILED' "$log" | head -1 | sed 's/.*==> HG-15 FAILED: //')"
	exit 1
fi

if ! grep -aq "==> HG-15 PASSED" "$log"; then
	echo "==> HG-15 FAILED: проба отработала (rc=$rc), но вердикта не напечатала"
	exit 1
fi

grep -a "==> HG-15 PASSED" "$log" | head -1
exit 0
