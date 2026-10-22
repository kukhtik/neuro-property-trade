#!/usr/bin/env bash
# MOCK-01 — «ВИЗУАЛ НЕ РАЗВАЛИЛСЯ И ВЫГЛЯДИТ КАК МАКЕТ» (замена отменённой телефонной проверки).
#
# ЧТО ОБЕЩАНО. Владелец 23.10: «вместо [телефонной проверки] нужно сделать проверку на
# консистентность (чтобы визуал не разваливался и все было там и выглядело так как должно
# быть, по пиксельное сравнение с макетом)». Этот гейт — это обещание, измеренное.
#
# ЭТАЛОН — КАКОЙ МАКЕТ И ПОЧЕМУ. В репозитории три кандидата, и это важно, потому что выбор
# меняет всё:
#   * `design/ui-prototype.html` — «макет» из 31 состояния, СГЕНЕРИРОВАН из игры
#     (`design/tools/build_prototype.py`; пересборка даёт побайтово ИДЕНТИЧНЫЙ файл).
#     Но его ШАБЛОН ВЁРСТКИ (`design/src/proto.js`) отстал: он объявляет боковые доки
#     `--L=268 --R=344`, которых в продукте нет с 21.10 (панели уехали в кольцо).
#     Замер против него даёт 44 зоны вне допуска, худшая — центр +100 п.п. — и это НЕ дефект
#     продукта, а сравнение с устаревшей композицией;
#   * `design/variants/v5/concept-a-composition.html` — концепт A, тот самый, который продукту
#     ПЕРЕносили (спека `docs/specs/ui-redesign-v5-composition.md`: «Что уже есть в продукте
#     (совпадает с A)»). Живой эталон композиции;
#   * `design/variants/sweep/*` — 16 кандидатов от 19.10, выбора владельца в репозитории нет.
# Замер против концепта A: общий ink 92.6 % против 93.2 % (Δ −0.6 п.п.), каждая зона в
# пределах 7.0 п.п. То есть ПРОДУКТ УЖЕ СООТВЕТСТВУЕТ эталону, и этот гейт защищает именно
# это соответствие.
#
# КАК МЕРЯЕМ. Построчный пиксельный diff не годится: в `tools/ci/compare_mockup.py` сказано
# прямо — «different fonts, different scales - a pixel diff would flag everything and say
# nothing». Макет рисует HTML в Chromium, игра — Godot. Поэтому сравниваем ПО ЗОНАМ: доля
# «не-фоновых» пикселей в каждой ячейке сетки 8x6 (тот же замер, что в §7 журнала), плюс
# общий ink и заполненность центра кольца. Фон берётся из полосы по краю кадра — та же
# логика, что в гейте `FILL`.
#
# ДВЕ ПРОВЕРКИ СВЕЖЕСТИ — иначе гейт измеряет не тот продукт (урок HG-11):
#   1. эталон (рендер концепта A) не старше последнего коммита, трогавшего сам концепт;
#   2. кадр игры не старше последнего коммита, трогавшего `game/` — иначе кадр показывает
#      ПРОШЛУЮ версию продукта, и «зелёный» гейт будет враньём.
#
# ГЕЙТ, КОТОРЫЙ НИЧЕГО НЕ ИЗМЕРИЛ, НЕ ИМЕЕТ ПРАВА БЫТЬ ЗЕЛЁНЫМ: нет кадра, нет эталона, нет
# вердикта — это FAILED с причиной, а не тихий skip.
#
# НЕГАТИВНАЯ ПРОВЕРКА (возврат дефекта, без правки чужого кода):
#   bash tools/ci/gates/mockup_consistency_gate.sh --negative
# Подставляет вместо кадра игры залитый белым PNG того же размера: гейт обязан покраснеть
# (`==> MOCK-01 FAILED`), иначе он ничего не измеряет.
#
# Вердикт: ==> MOCK-01 PASSED (...) / ==> MOCK-01 FAILED: <причина>
# Запуск:  bash tools/ci/gates/mockup_consistency_gate.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
repo_win="$(cd "$repo" && pwd -W 2>/dev/null || printf '%s' "$repo")"

REF_HTML="design/variants/v5/concept-a-composition.html"
REF_PNG="design/variants/v5/renders/concept-a-composition.png"
FRAME="build/renders/turn-human_neuro.png"
TOLERANCE=10      # п.п. — фактический максимум расхождения сейчас 7.0 п.п.

# --- Python: на Windows `py -3.12`, на CI — `python3` ---
PY=""
for cand in "py -3.12" "python3" "python"; do
	if command -v ${cand%% *} >/dev/null 2>&1; then
		if ${cand} -c "import PIL" >/dev/null 2>&1; then PY="$cand"; break; fi
	fi
done
if [ -z "$PY" ]; then
	echo "==> MOCK-01 FAILED: нет Python с Pillow (нужен py -3.12) - измерение не сделано"
	exit 1
fi

# --- эталон на месте? ---
if [ ! -f "$repo/$REF_PNG" ]; then
	echo "==> MOCK-01 FAILED: нет эталона $REF_PNG (отрисовка концепта A)"
	exit 1
fi
if [ ! -f "$repo/$REF_HTML" ]; then
	echo "==> MOCK-01 FAILED: нет макета $REF_HTML"
	exit 1
fi

# --- свежесть эталона: рендер не старше последнего коммита про сам концепт ---
# Оба файла ЗАКОММИЧЕНЫ, поэтому сравниваем времена КОММИТОВ, а не mtime: mtime после
# чекаута у всех файлов одинаковый, и сравнение с секундной точностью коммита давало
# ложное «устарело». (Рендер концепта A и сам концепт закоммичены вместе: c3a9ef6.)
# В режиме --negative проверки свежести НЕ мешают: там проверяется путь измерения,
# а не актуальность артефактов.
ref_ts="$(git -C "$repo_win" log -1 --format=%ct -- "$REF_HTML" 2>/dev/null || true)"
ref_png_ts="$(git -C "$repo_win" log -1 --format=%ct -- "$REF_PNG" 2>/dev/null || true)"
if [ "${1:-}" != "--negative" ] && [ -n "$ref_ts" ] && [ -n "$ref_png_ts" ] && [ "$ref_png_ts" -lt "$ref_ts" ]; then
	echo "==> MOCK-01 FAILED: эталон $REF_PNG старше последнего коммита про $REF_HTML (рендер устарел, перерисуй)"
	exit 1
fi

# --- кадр игры на месте? ---
if [ ! -f "$repo/$FRAME" ]; then
	echo "==> MOCK-01 FAILED: нет кадра $FRAME (сначала прогони SG-07 — он рисует кадры)"
	exit 1
fi

# --- свежесть кадра: кадр не старше последнего коммита, трогавшего game/ ---
code_ts="$(git -C "$repo_win" log -1 --format=%ct -- game 2>/dev/null || true)"
frame_mtime="$(stat -c %Y "$repo/$FRAME" 2>/dev/null || echo 0)"
if [ "${1:-}" != "--negative" ] && [ -n "$code_ts" ] && [ "$frame_mtime" -lt "$code_ts" ]; then
	echo "==> MOCK-01 FAILED: кадр $FRAME старше последнего коммита, трогавшего game/ - он показывает ПРОШЛЫЙ продукт (прогони SG-07)"
	exit 1
fi

mkdir -p "$repo/build/gates"
log="$repo/build/gates/mockup_consistency.log"

# --- негативный режим: подставляем испорченный кадр ---
# NATIVE пути для нативного Python: `/c/...` он не понимает (та же ловушка, что с godot).
repo_native="$(cd "$repo" && pwd -W 2>/dev/null || printf '%s' "$repo")"
frame_arg="$repo_native/$FRAME"
if [ "${1:-}" = "--negative" ]; then
	bad="$repo_native/build/gates/mockup_consistency_negative.png"
	${PY} - "$bad" "$repo_native/$FRAME" <<'PYEOF'
import sys
from PIL import Image
out, src = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
Image.new("RGB", im.size, (255, 255, 255)).save(out)
print("negative frame: %s (%dx%d, all white)" % (out, im.size[0], im.size[1]))
PYEOF
	[ -f "$bad" ] || { echo "==> MOCK-01 FAILED: не собрал негативный кадр ($bad)"; exit 1; }
	frame_arg="$bad"
fi

$PY "$repo_native/tools/ci/mockup_measure.py" --mockup "$repo_native/$REF_PNG" --frame "$frame_arg" \
	--tolerance "$TOLERANCE" >"$log" 2>&1
rc=$?

if grep -aq "SCRIPT ERROR:" "$log"; then
	echo "==> MOCK-01 FAILED: SCRIPT ERROR во время измерения: $(grep -a 'SCRIPT ERROR:' "$log" | head -1)"
	exit 1
fi
if ! grep -aq "MOCKUP-MEASURE" "$log"; then
	echo "==> MOCK-01 FAILED: измеритель не отработал (rc=$rc, см. build/gates/mockup_consistency.log)"
	exit 1
fi
if grep -aq "==> MOCKUP-MEASURE FAILED" "$log"; then
	reason="$(grep -a '==> MOCKUP-MEASURE FAILED' "$log" | head -1 | sed 's/.*==> MOCKUP-MEASURE FAILED: //')"
	echo "==> MOCK-01 FAILED: $reason"
	exit 1
fi
if ! grep -aq "==> MOCKUP-MEASURE PASSED" "$log"; then
	echo "==> MOCK-01 FAILED: измеритель отработал (rc=$rc), но вердикта не напечатал"
	exit 1
fi

summary="$(grep -a 'overall ink' "$log" | head -1 | sed 's/^ *//')"
echo "==> MOCK-01 PASSED (the live frame matches the reference mockup zone by zone; ${summary})"
exit 0
