#!/usr/bin/env bash
# MOCK-02 — «ВИЗУАЛЬНЫЙ ВКУС» (замена отменённой телефонной проверки, вторым крылом).
#
# ЧТО ОБЕЩАНО. Владелец 23.10: «так же проверка на визуальный вкус (чтобы не было огромных
# выбивающихся надписей к примеру)». Вкус измерим: кегль каждой надписи должен быть ШАГОМ
# ШКАЛЫ (она живёт в скине: `tokens.size = {11, 13, 14, 18, 28}` — те же значения читает
# макет) и не должен превышать потолок `xl`.
#
# ЧТО МЕРЯЕТ (подробности — в `tools/ci/mockup_taste.py`):
#   1. ЖИВО: ни одна надпись не крупнее потолка xl × ui_scale. Это «огромные выбивающиеся
#      надписи» буквально.
#   2. ЖИВО: надпись вне доски обязана иметь кегль из шкалы. (Надпись в клетке доски считает
#      кегль от размера клетки — это законно, но ей ограничен потолок.)
#   3. СТАТИЧЕСКИ: в исходниках `game/` не должно быть «сырых» чисел вне шкалы
#      (`add_theme_font_size_override(..., 10)`, `maxi(12, ...)`, `s.size("s", 12)`).
#      Именно так в коде появились 10 и 12 — по ошибочно записанной в журнале шкале.
#
# ГЕЙТ, КОТОРЫЙ НИЧЕГО НЕ ИЗМЕРИЛ, НЕ ИМЕЕТ ПРАВА БЫТЬ ЗЕЛЁНЫМ: нет пробы, нет дампа, нет
# вердикта — это FAILED с причиной, а не тихий skip.
#
# НЕГАТИВНАЯ ПРОВЕРКА (возврат дефекта, без правки чужого кода):
#   bash tools/ci/gates/mockup_taste_gate.sh --negative
# Подставляет дамп, в котором одна надпись имеет кегль 64 px. Гейт обязан покраснеть
# (`==> MOCK-02 FAILED`), иначе он ничего не измеряет.
#
# Вердикт: ==> MOCK-02 PASSED (...) / ==> MOCK-02 FAILED: <причина>
# Запуск:  bash tools/ci/gates/mockup_taste_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# NATIVE путь для нативных бинарников: godot и python не открывают MSYS-пути `/c/...`
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }
repo_native="$(native "$repo")"

godot="$(bash "$repo/tools/ci/godot_bin.sh" 2>/dev/null)"
if [ -z "$godot" ] || [ ! -e "$godot" ]; then
	echo "==> MOCK-02 FAILED: нет бинарника Godot (см. tools/ci/fetch_godot.sh) - измерение не сделано"
	exit 1
fi

PY=""
for cand in "py -3.12" "python3" "python"; do
	if command -v ${cand%% *} >/dev/null 2>&1; then
		PY="$cand"; break
	fi
done
if [ -z "$PY" ]; then
	echo "==> MOCK-02 FAILED: нет Python - измерение не сделано"
	exit 1
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/mockup_taste.log"
dump="$repo/build/gates/mockup_taste.dump"
rc=0
timeout 120 "$godot" --headless --path "$(native "$repo/game")" \
	res://tools/mockup_taste_probe.tscn >"$log" 2>&1 || rc=$?

if ! grep -aq "MOCK-02 PROBE" "$log"; then
	echo "==> MOCK-02 FAILED: проба не сделала ни одной проверки (rc=$rc, см. build/gates/mockup_taste.log)"
	exit 1
fi
if grep -aq "SCRIPT ERROR:" "$log"; then
	echo "==> MOCK-02 FAILED: SCRIPT ERROR во время измерения: $(grep -a 'SCRIPT ERROR:' "$log" | head -1)"
	exit 1
fi

grep -a "^TASTE|" "$log" >"$dump"
if [ ! -s "$dump" ]; then
	echo "==> MOCK-02 FAILED: дамп пробы пуст - измерение не сделано"
	exit 1
fi

# --- негативный режим: одна надпись с кеглем 64 px ---
dump_arg="$repo_native/build/gates/mockup_taste.dump"
if [ "${1:-}" = "--negative" ]; then
	bad="$repo_native/build/gates/mockup_taste_negative.dump"
	{ cat "$dump"; echo "TASTE|label|/fake/huge/64|-1|0|огромная надпись"; } > "$bad"
	dump_arg="$bad"
fi

# Анализатор — нативный Python, поэтому путь к дампу должен быть NATIVE (`C:/...`),
# а не MSYS (`/c/...`): нативный бинарь MSYS-путь не открывает.
$PY "$repo_native/tools/ci/mockup_taste.py" --dump "$dump_arg" >"$repo/build/gates/mockup_taste_verdict.log" 2>&1
vrc=$?
cat "$repo/build/gates/mockup_taste_verdict.log"

if grep -aq "==> MOCK-02 FAILED" "$repo/build/gates/mockup_taste_verdict.log"; then
	exit 1
fi
if ! grep -aq "==> MOCK-02 PASSED" "$repo/build/gates/mockup_taste_verdict.log"; then
	echo "==> MOCK-02 FAILED: анализатор отработал (rc=$vrc), но вердикта не напечатал"
	exit 1
fi
exit 0
