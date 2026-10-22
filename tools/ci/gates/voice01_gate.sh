#!/usr/bin/env bash
# VOICE-01 — «КТО ГОВОРИТ» (D1, docs/program.md §3а).
#
# ЧТО ОБЕЩАНО. У игрока должно быть видно, КТО говорит. Вендорённый SDK-модуль
# (`game/addons/neuro-sdk/voice/voice_chat.gd`) отдаёт `speaking_changed(speaking)`,
# `speech_cancelled()`, `voice_unavailable(reason)`, `voice_ready()` — и до этой работы у них в
# продукте (`game/`) не было НИ ОДНОГО потребителя: `git grep speaking_changed -- game/` находил
# только сам аддон. Обещание висело TODO: ни кода, ни гейта.
#
# ПОЧЕМУ ГЕЙТ, А НЕ ЗАМЕТКА. Обещание про СВОЮ логику продукта: по сигналу «этот говорит» карточка
# места показывает, кто говорит, а при `voice_unavailable` продукт ТИХО деградирует — индикатор
# гаснет, ошибок нет, ничего не «красное». Живой сервер голоса — внешний блокер, и он здесь не
# нужен: источник сигналов подставляется снаружи (как `FakeRemote` у HG-12), поэтому логика
# измеряется headless на НАСТОЯЩЕМ продукте.
#
# МЕРИТ (подробности — в `game/tools/voice01_probe.gd`):
#   1. сигнал доходит до экрана: `speaking_changed(true)` зажигает индикатор в карточке ЭТОГО
#      места и несёт правильную идентичность (`driver_label`);
#   2. идентичность не путается: горит ровно одно место;
#   3. тихая деградация: `voice_unavailable` гасит индикатор, дерево узлов живо, деградация
#      переживает перерисовку карточек (иначе она «воскресала» бы на каждой проекции);
#   4. окно появления/исчезновения: `speaking_changed(false)` и `speech_cancelled` гасят.
#
# ГЕЙТ, КОТОРЫЙ НИЧЕГО НЕ ИЗМЕРИЛ, НЕ ИМЕЕТ ПРАВА БЫТЬ ЗЕЛЁНЫМ: нет бинарника, нет строки пробы,
# нет вердикта — это FAILED с причиной, а не тихий skip (проба headless, дисплей ей не нужен).
# `SCRIPT ERROR:` (с двоеточием — так эту строку пишет сам Godot) — провал.
#
# НЕГАТИВНАЯ ПРОВЕРКА (возврат дефекта, без правки чужого кода):
#   bash -c 'G="$(bash tools/ci/godot_bin.sh)"; "$G" --headless --path "$(cd game && pwd -W)" \
#            res://tools/voice01_probe.tscn -- --voice01-negative'
#   Проба эмулирует снаружи ровно тот дефект, ради которого проверка написана: внешний обработчик
#   того же сигнала снова зажигает индикатор после `speaking_changed(false)`. Проверка «индикатор
#   гаснет» обязана покраснеть (`==> VOICE-01 NEGATIVE OK`), иначе она ничего не измеряет.
#
# Вердикт: ==> VOICE-01 PASSED (...) / ==> VOICE-01 FAILED: <причина>
# Запуск:  bash tools/ci/gates/voice01_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# NATIVE путь для нативного бинарника: godot не открывает MSYS-пути `/c/...`
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh" 2>/dev/null)"
if [ -z "$godot" ] || [ ! -e "$godot" ]; then
	echo "==> VOICE-01 FAILED: нет бинарника Godot (см. tools/ci/fetch_godot.sh) - измерение не сделано"
	exit 1
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/voice01.log"
rc=0
timeout 300 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/voice01_probe.tscn >"$log" 2>&1 || rc=$?

# НИ ОДНОЙ СТРОКИ ПРОБЫ — это не «нет дисплея» (проба headless), это отсутствие измерения.
if ! grep -aq "VOICE-01 PROBE" "$log"; then
	echo "==> VOICE-01 FAILED: проба не сделала ни одной проверки (rc=$rc, см. build/gates/voice01.log)"
	exit 1
fi

# `SCRIPT ERROR:` с двоеточием — настоящая строка ошибки Godot (см. дисциплину run_gates.sh).
if grep -aq "SCRIPT ERROR:" "$log"; then
	echo "==> VOICE-01 FAILED: SCRIPT ERROR во время измерения: $(grep -a 'SCRIPT ERROR:' "$log" | head -1)"
	exit 1
fi

if grep -aq "==> VOICE-01 FAILED" "$log"; then
	echo "==> VOICE-01 FAILED: $(grep -a '==> VOICE-01 FAILED' "$log" | head -1 | sed 's/.*==> VOICE-01 FAILED: //')"
	exit 1
fi

if ! grep -aq "==> VOICE-01 PASSED" "$log"; then
	echo "==> VOICE-01 FAILED: проба отработала (rc=$rc), но вердикта не напечатала"
	exit 1
fi

grep -a "VOICE-01 PROBE:" "$log" | tail -1
grep -a "==> VOICE-01 PASSED" "$log" | head -1
exit 0
