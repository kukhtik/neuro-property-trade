#!/usr/bin/env bash
# E-5 — ИНВЕНТАРЬ КАРТОЧКИ ИГРОКА (D2 / D13).
#
# ЧТО ОБЕЩАНО. Сегодня карточка игрока несёт только чип «В собственности: N» — количество без
# списка, и зритель не может узнать, ЧТО именно собрал человек. Обещание: (1) подсказка карточки
# отдаёт список ЕГО клеток по именам (из `proj.board[].name`) с токеном группы, суффиксами
# домов/залога, деньгами и картами тюрьмы; (2) отдельное действие карточки выделяет его клетки НА
# ДОСКЕ — свои получают кольцо, рамки владения остальных глушатся. Клик по самой карточке при этом
# остаётся дверью в `drawer-seats` (press уходит наверх, в зону панно).
#
# ПОЧЕМУ ГЕЙТ, А НЕ ПРОСТО ТЕСТ. Тест меряет правило и виджет вне окна; здесь мерится ЖИВОЙ
# продукт — настоящий `PlayersPanel` через настоящий `sync()` и настоящая `BoardScene` с 40
# настоящими `TileView`, у которых спрашивается их собственная рамка состояния. Проба живёт
# рядом: `game/tools/e5_inventory_probe.tscn` (проба меряет, гейт выносит вердикт — как у
# PANELS-IN-RING).
#
# ЧЕГО ЭТОТ ГЕЙТ НЕ ДЕЛАЕТ: он не «скипает» при отсутствии измерения. Гейт, который ничего не
# измерил, не имеет права быть зелёным: нет бинарника, нет строки пробы, нет вердикта — это FAILED
# с причиной, а не тихий skip.
#
# Вердикт: ==> E-5 PASSED (...) / ==> E-5 FAILED: <причина>
# Run: bash tools/ci/gates/e5_inventory_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# NATIVE путь для нативного бинарника: godot не открывает MSYS-пути `/c/...`
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

godot="$(bash "$repo/tools/ci/godot_bin.sh" 2>/dev/null)"
if [ -z "$godot" ] || [ ! -e "$godot" ]; then
	echo "==> E-5 FAILED: нет бинарника Godot (см. tools/ci/fetch_godot.sh) - измерение не сделано"
	exit 1
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/e5-inventory.log"
rc=0
timeout 300 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/e5_inventory_probe.tscn >"$log" 2>&1 || rc=$?

# НИ ОДНОЙ СТРОКИ ПРОБЫ - это не «нет дисплея», это отсутствие измерения: проба headless, ей
# дисплей не нужен, поэтому молчание = красный.
if ! grep -aq "E-5 PROBE" "$log"; then
	echo "==> E-5 FAILED: проба не сделала ни одной проверки (см. build/gates/e5-inventory.log)"
	exit 1
fi

if grep -aq "SCRIPT ERROR" "$log"; then
	echo "==> E-5 FAILED: SCRIPT ERROR во время измерения: $(grep -a 'SCRIPT ERROR' "$log" | head -1)"
	exit 1
fi

if grep -aq "==> E-5 FAILED" "$log"; then
	echo "==> E-5 FAILED: $(grep -a '==> E-5 FAILED' "$log" | head -1 | sed 's/.*==> E-5 FAILED: //')"
	exit 1
fi

if ! grep -aq "==> E-5 PASSED" "$log"; then
	echo "==> E-5 FAILED: проба отработала (rc=$rc), но вердикта не напечатала"
	exit 1
fi

grep -a "==> E-5 PASSED" "$log" | head -1
exit 0
