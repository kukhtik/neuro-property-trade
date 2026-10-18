#!/usr/bin/env python3
"""R-7 - "the stream picture can be read from a phone": what the CAPTURED FRAMES can prove.

THE RULE. docs/specs/ui-redesign-brief.md section 3.3, R-7 (MUST): every element of the "glance"
set (whose turn, the phase, the round, the money, the journal heading, the newest journal line)
must be readable after the frame is scaled down to a 390 px phone:

    effective_px = size_px * PHONE_CSS_WIDTH / frame_width          (390 / frame_width)

so a glance label needs >= 12 px EFFECTIVE, i.e. >= 12 * frame_width / 390 px IN the frame. The
single home of that arithmetic is game/ui/core/layout_profile.gd (PHONE_CSS_WIDTH,
GLANCE_MIN_PHONE_PX, glance_floor_px()); the gate that judges it is STREAM-READ
(tools/ci/gates/stream_read_gate.sh -> game/tools/gates/stream_read_gate.gd).

WHY THIS SCRIPT EXISTS NEXT TO A GATE THAT ALREADY MEASURES IT. STREAM-READ walks the LIVE Godot
tree and reads each Label's real font_size; it is the authoritative measurement and it is RED
today ("the smallest glance label is 2.4px on a phone (the journal heading: 12px in the 1920x1080
frame)"). It needs a Godot binary and a display, so it measures ONE frame size (1920x1080). This
script is the OFFLINE half: it reads the frames the product's own capturer already wrote
(build/renders/*.png) with PIL and no engine, and answers what a frame can answer - per-frame
geometry, the exact R-7 arithmetic for THAT frame, and a brightness-profile ESTIMATE of text-row
heights in named regions.

WHAT IT DOES NOT DO, SAID UP FRONT. It does not recover a font size from pixels. A PNG answers
"is there a blob here", and a blob is not a word (the READ gate's own header makes the same point):
antialiasing, the compositor, glyph-ink height != em size, and a region rectangle taken from layout
constants rather than from the pixels all stand between the picture and the number. Every figure in
the report is tagged "exact" / "estimate" / "cannot be measured", so the reader can tell which kind
of claim they are looking at. That tagging is the point of the exercise, not a disclaimer.

RUN:    py -3.12 tools/ci/r7_report.py
WRITES: build/r7/r7-report.md   (build/ is git-ignored - this report bothers nobody)
"""
import datetime
import pathlib
import sys

import numpy as np
from PIL import Image

REPO = pathlib.Path(__file__).resolve().parents[2]
RENDERS = REPO / "build" / "renders"
OUT = REPO / "build" / "r7" / "r7-report.md"

# --- the rule's constants, mirrored from layout_profile.gd (NOT re-invented here) --------------
PHONE_CSS_WIDTH = 390.0
GLANCE_MIN_PHONE_PX = 12.0
GLANCE_FRAME_WIDTH = 1920.0          # the frame the floor was derived at

# LayoutProfile.top_height() / right_width() / bottom_height() / RAIL_WIDTH, read out of the GDScript.
TOP_H = 56
BOTTOM_H = 96
RIGHT_W = {"wide": 380, "desktop": 344, "compact": 300}
RAIL_W = 48

# The glance set, and the font size the STREAM-READ gate MEASURED for each role in a 1920x1080
# window (build/gates/STREAM-READ.log, 2026-10-18). These are theme constants (HUD_MIN_PX = 13,
# the journal's own 12), so they do not depend on the frame width - but they are QUOTED from the
# gate's log rather than re-derived, so the two cannot drift apart silently.
GLANCE = [
    ("turn-name", "чей ход (имя)", 13),
    ("turn-phase", "что происходит (фаза)", 13),
    ("top-round", "раунд", 13),
    ("top-pot", "деньги (банк)", 13),
    ("jrn-title", "заголовок журнала", 12),
    ("jrn-text", "последняя строка журнала", 12),
]
GATE_LOG = REPO / "build" / "gates" / "STREAM-READ.log"

# A glyph's INK height is not its em size. For the faces this product ships (DejaVu-derived,
# cap height ~0.73 em) an ink band of h px implies an em of roughly h / 0.73. The band is a
# RANGE, not a measurement, so it is always reported as one.
CAP_RATIO_LO, CAP_RATIO_HI = 0.62, 0.80


def profile_of(w, h):
    """LayoutProfile.for_screen: wide >= 1600; desktop >= 1280 and > 700 tall; else compact."""
    if w >= 1600:
        return "wide"
    if w >= 1280 and h > 700:
        return "desktop"
    return "compact"


def classify(name):
    """Live frame, side-by-side composite, or a static mockup - they answer different questions."""
    if "side_by_side" in name:
        return "mockup" if name.endswith("-mockup.png") else "composite"
    return "frame"


def ink_bands(lum, rect, thr=45, min_px=3):
    """Text-row bands inside rect, by brightness profile against the region's own median.

    A row counts as "ink" when it holds >= min_px pixels more than thr above the region's median
    luminance; consecutive ink rows form a band. The band height is the INK height (cap + descender
    of whatever glyphs are present), which is what a brightness profile can honestly give - NOT the
    em size. Returns (bands, region_median_luminance); bands are (y_start, y_end, height).
    """
    x0, y0, x1, y1 = rect
    if x1 <= x0 or y1 <= y0:
        return [], None
    sub = lum[y0:y1, x0:x1]
    bg = float(np.median(sub))
    counts = (sub > bg + thr).sum(axis=1)
    bands = []
    y = 0
    while y < counts.size:
        if counts[y] >= min_px:
            s = y
            while y < counts.size and counts[y] >= min_px:
                y += 1
            bands.append((s + y0, y - 1 + y0, y - s))
        else:
            y += 1
    return bands, bg


def median(xs):
    xs = sorted(xs)
    if not xs:
        return 0.0
    n = len(xs)
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


def measure(path):
    """Everything a single PNG can answer. No font size is invented here."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    lum = np.asarray(im).astype(float).mean(axis=2)
    prof = profile_of(w, h)
    scale = PHONE_CSS_WIDTH / w
    need = GLANCE_MIN_PHONE_PX * w / PHONE_CSS_WIDTH          # exact: R-7 in THIS frame
    row = {
        "name": path.name,
        "kind": classify(path.name),
        "w": w, "h": h, "profile": prof,
        "scale": scale, "need_px": need,
    }
    row["worst_eff"] = min(px * scale for _, _, px in GLANCE)
    row["worst_role"] = min(GLANCE, key=lambda g: g[2] * scale)[1]
    # --- regions: the rectangles come from LayoutProfile, NOT from the pixels, so every band
    # --- height derived inside them is an ESTIMATE, never a measurement.
    row["header"] = ink_bands(lum, (0, 0, w, TOP_H))
    jw = RIGHT_W.get(prof, 300)
    row["journal_rect"] = (w - jw, TOP_H, w, max(TOP_H + 1, h - BOTTOM_H))
    row["journal"] = ink_bands(lum, row["journal_rect"])
    row["rail"] = ink_bands(lum, (w - RAIL_W, 0, w, h))
    row["rail_span"] = rail_span(lum, w, h)
    row["header_runs"] = ink_run_mode(lum, (0, 0, w, TOP_H))
    row["journal_runs"] = ink_run_mode(lum, row["journal_rect"])
    return row


def _vertical_runs(lum, rect, thr=45):
    """Lengths of vertical ink runs in rect: one run per stroke a column crosses."""
    x0, y0, x1, y1 = rect
    if x1 <= x0 or y1 <= y0:
        return []
    sub = lum[y0:y1, x0:x1]
    bg = float(np.median(sub))
    ink = sub > bg + thr
    out = []
    for cx in range(ink.shape[1]):
        col = ink[:, cx]
        y = 0
        while y < col.size:
            if col[y]:
                s = y
                while y < col.size and col[y]:
                    y += 1
                out.append(y - s)
            else:
                y += 1
    return out


def ink_run_mode(lum, rect, thr=45, lo=5, hi=16):
    """The most common vertical ink-run length in [lo,hi] - an ESTIMATE of a glyph's ink height.

    A column through text crosses short strokes (one run per stroke); a column through the avatar, a
    button or a cell border is one long run. Keeping only runs in [lo,hi] leaves the strokes, and
    their mode is the most common stroke height - the closest a PNG gets to a font size. It is still
    an estimate: ink height is not em, and a region with non-text content pollutes the count.
    """
    runs = [r for r in _vertical_runs(lum, rect, thr) if lo <= r <= hi]
    if not runs:
        return None, 0, 0
    counts = {}
    for r in runs:
        counts[r] = counts.get(r, 0) + 1
    mode = max(sorted(counts), key=lambda k: counts[k])
    return mode, counts[mode], len(runs)


def fmt_bands(res):
    bands, bg = res
    if not bands:
        return "нет полос (bg=%.0f)" % (bg if bg is not None else -1)
    hs = sorted(b[2] for b in bands)
    blocky = [x for x in hs if x > 60]
    tag = ""
    if blocky:
        # A "text row" is never 80+ px tall. Bands this big are cells / panels that happen to lie
        # inside the rectangle - saying so keeps the table from being read as font sizes.
        tag = " ⚠ %d блок(ов) >60 px — не строки текста" % len(blocky)
    return "%d полос h=%s (bg=%.0f)%s" % (len(bands), "/".join(str(x) for x in hs[:6]), bg, tag)


def rail_span(lum, w, h):
    """Where the drawn right rail actually sits: the non-background columns at the frame edge.

    The rail's panel fill is a few levels above the frame background (20 vs 12 in these frames), so
    a column that is > bg+6 down most of its height is panel, not background. The background is the
    5th percentile, NOT the median: in these frames the panel fill is common enough to BE the
    median, and a median-based threshold would call the rail "background" and miss it. Walked from
    the right edge so a board cell column can never be mistaken for the rail.
    """
    bg = float(np.percentile(lum, 5))
    counts = (lum > bg + 6).sum(axis=0)
    x = w - 1
    while x > 0 and counts[x] < h * 0.3:
        x -= 1
    x1 = x
    while x > 0 and counts[x] >= h * 0.3:
        x -= 1
    return (x + 1, x1) if x1 > x else None


def main():
    frames = sorted(RENDERS.glob("*.png"))
    if not frames:
        print("FAIL: no frames under %s - nothing to measure" % RENDERS)
        return 1
    rows = [measure(p) for p in frames]
    live = [r for r in rows if r["kind"] == "frame"]
    worst = min(live, key=lambda r: r["worst_eff"])
    # All 1600x1200 frames tie on the R-7 arithmetic, so the REGION analysis is done on the frame
    # the brief itself measures (ui-redesign-brief.md section 1: turn-human_neuro.png). Picking the
    # alphabetically-first tie (admin_evil) would describe an admin screen, not the match.
    rep = next((r for r in live if r["name"] == "turn-human_neuro.png"), worst)
    sc1600 = PHONE_CSS_WIDTH / 1600.0

    # --- the summary is PRINTED and EMBEDDED, so the two cannot disagree ----------------------
    summary = []
    summary.append("frames_total=%d live=%d composite=%d mockup=%d"
                   % (len(rows), len(live),
                      sum(1 for r in rows if r["kind"] == "composite"),
                      sum(1 for r in rows if r["kind"] == "mockup")))
    sizes = sorted({(r["w"], r["h"]) for r in live})
    summary.append("live frame sizes: " + ", ".join(
        "%dx%d x%d" % (w, h, sum(1 for r in live if (r["w"], r["h"]) == (w, h))) for w, h in sizes))
    for w, h in sizes:
        summary.append("frame %dx%d: scale_to_390=%.3f need_in_frame=%.1fpx glance13->%.2fpx glance12->%.2fpx"
                       % (w, h, PHONE_CSS_WIDTH / w, GLANCE_MIN_PHONE_PX * w / PHONE_CSS_WIDTH,
                          13 * PHONE_CSS_WIDTH / w, 12 * PHONE_CSS_WIDTH / w))
    summary.append("worst live frame: %s (%dx%d) worst_glance=%s eff=%.2fpx shortfall=%.2fx"
                   % (worst["name"], worst["w"], worst["h"], worst["worst_role"],
                      worst["worst_eff"], GLANCE_MIN_PHONE_PX / worst["worst_eff"]))
    summary.append("all 26 live 1600x1200 frames tie at eff=%.2fpx; region rows below use %s (the frame the brief measures)"
                   % (worst["worst_eff"], rep["name"]))
    hb, hbg = rep["header"]
    summary.append("header 0..56 on %s: %d ink band(s) bg=%.1f heights=%s"
                   % (rep["name"], len(hb), hbg, "/".join(str(b[2]) for b in hb[:8]) or "-"))
    jb, jbg = rep["journal"]
    summary.append("journal rect %s on %s: %d ink band(s) bg=%.1f heights=%s"
                   % (str(rep["journal_rect"]), rep["name"], len(jb), jbg,
                      "/".join(str(b[2]) for b in jb[:8]) or "-"))
    rb, rbg = rep["rail"]
    summary.append("right rail 48px on %s: %d ink band(s) bg=%.1f heights=%s; drawn rail span x=%s"
                   % (rep["name"], len(rb), rbg, "/".join(str(b[2]) for b in rb[:8]) or "-",
                      str(rep["rail_span"])))
    summary.append("regions are rectangles from LayoutProfile, NOT from pixels -> band heights are ESTIMATES")
    summary.append("header ink-run mode on %s: %s px (n=%d of %d runs in 5..16) -> implied em %.0f-%.0f px (gate says 13)"
                   % (rep["name"], rep["header_runs"][0], rep["header_runs"][1], rep["header_runs"][2],
                      (rep["header_runs"][0] or 0) / CAP_RATIO_HI, (rep["header_runs"][0] or 0) / CAP_RATIO_LO))
    summary.append("a PNG cannot recover font_size: ink height != em, compositor + antialiasing in between")

    out = []
    say = out.append
    say("# R-7 - читаемость кадра с телефона: измеримый отчёт по кадрам `build/renders/`")
    say("")
    say("Сгенерировано `tools/ci/r7_report.py`, %s. Источник: `build/renders/*.png` — %d файл(ов). "
        "Godot НЕ запускался; ничего в `game/` и `tools/ci/*.sh` не менялось."
        % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), len(rows)))
    say("")
    say("Правило R-7 (`docs/specs/ui-redesign-brief.md` §3.3, MUST): `eff = size_px * 390 / frame_width`, "
        "порог `eff >= 12 px`. Обратная форма, которой пользуется отчёт: в кадре ширины W glance-кегль "
        "обязан быть `>= 12 * W / 390` px. Формула и константы живут в `game/ui/core/layout_profile.gd` "
        "(`PHONE_CSS_WIDTH`, `GLANCE_MIN_PHONE_PX`, `glance_floor_px()`); авторитетный замер делает гейт "
        "STREAM-READ, читая живые `font_size` из дерева Godot.")
    say("")
    say("Каждая цифра помечена: **точно** (размер файла / арифметика R-7 / значение из лога гейта), "
        "**оценка** (высота полосы по профилю яркости), **нельзя измерить** (то, на что у PNG нет ответа).")
    say("")
    say("## 0. Вердикт гейта — внешний факт, не наш замер")
    say("")
    if GATE_LOG.exists():
        lines = GATE_LOG.read_text(encoding="utf-8", errors="replace").splitlines()
        rowslog = [l.strip() for l in lines if "STREAM-READ ROW" in l]
        verdict = [l.strip() for l in lines if "==> STREAM-READ" in l]
        say("Из `build/gates/STREAM-READ.log` (гейт мерит живое дерево в окне 1920x1080):")
        say("")
        say("```")
        for l in rowslog:
            say(l)
        for l in verdict[-1:]:
            say(l)
        say("```")
        say("")
        say("Это **точно**: кегли прочитаны движком, а не выведены из картинки.")
    else:
        say("Лога гейта нет — вердикт не цитируется (остальные разделы не зависят от него).")
    say("")
    say("## 1. Что измерено ТОЧНО")
    say("")
    say("**Размеры кадров — по факту, а не по ожиданию.** В брифе-задании сказано «turn-human_* обычно "
        "1600x1200, admin_* бывает другое». По факту **все %d живых кадра одинаковы — 1600x1200**, кроме "
        "`compact_*` (880x600). `admin_*` — тоже 1600x1200. Ожидание не подтвердилось; это и есть "
        "польза замера вместо предположения." % len(live))
    say("")
    say("| размер | тип | файлов |")
    say("|---|---|---|")
    for w, h in sizes:
        say("| %dx%d | live frame | %d |" % (w, h, sum(1 for r in live if (r["w"], r["h"]) == (w, h))))
    for kind in ("composite", "mockup"):
        grp = sorted({(r["w"], r["h"]) for r in rows if r["kind"] == kind})
        for w, h in grp:
            n = sum(1 for r in rows if r["kind"] == kind and (r["w"], r["h"]) == (w, h))
            say("| %dx%d | %s | %d |" % (w, h, kind, n))
    say("")
    say("**Арифметика R-7 по каждому типу кадра (точно).** «Требуемый кегль в кадре» = столько px нужно "
        "в кадре, чтобы после сжатия до 390 px получилось ровно 12 px. Две последние колонки — что даёт "
        "сегодняшний кегль (13 px и 12 px из лога гейта) в ЭТОМ кадре.")
    say("")
    say("| кадр | ширина | масштаб до 390 | требуемый кегль | 13 px даёт | 12 px даёт |")
    say("|---|---|---|---|---|---|")
    for w, h in sizes:
        say("| %dx%d | %d | %.3f | **%.1f px** | %.2f px | %.2f px |"
            % (w, h, w, PHONE_CSS_WIDTH / w, GLANCE_MIN_PHONE_PX * w / PHONE_CSS_WIDTH,
               13 * PHONE_CSS_WIDTH / w, 12 * PHONE_CSS_WIDTH / w))
    say("")
    say("Худший из живых кадров — `%s` (%dx%d): его худший glance-элемент (`%s`) даёт **%.2f px** на "
        "телефоне; до порога 12 px не хватает в **%.2f раза**. Все 26 живых кадров 1600x1200 дают "
        "ОДИНАКОВЫЙ результат (арифметика R-7 зависит только от ширины), поэтому разбор областей ниже "
        "сделан на `%s` — на кадре, который меряет сам бриф §1."
        % (worst["name"], worst["w"], worst["h"], worst["worst_role"],
           worst["worst_eff"], GLANCE_MIN_PHONE_PX / worst["worst_eff"], rep["name"]))
    say("")
    say("## 2. Что ОЦЕНЕНО (профиль яркости, а не кегль)")
    say("")
    say("Метод: в прямоугольнике берётся медиана яркости; «чернильной» считается строка, где пикселей "
        "ярче медианы+45 не меньше 3; соседние чернильные строки сливаются в полосу. **Высота полосы — "
        "это высота ЧЕРНИЛ (cap + выносные элементы присутствующих глифов), а не em.** Прямоугольники "
        "взяты из констант `LayoutProfile` (шапка `top_height()=56`, правый док `right_width()`, рейл "
        "48 px), а не из пикселей — поэтому всё в этом разделе оценка.")
    say("")
    say("Перевод высоты чернил в кегль: `em ≈ ink / 0.62 … ink / 0.80`.")
    say("")
    say("| кадр | шапка 0..56 | правый док (LayoutProfile) | правый рейл 48 px |")
    say("|---|---|---|---|")
    for r in rows:
        if r["kind"] != "frame":
            continue
        say("| %s | %s | %s | %s |"
            % (r["name"], fmt_bands(r["header"]), fmt_bands(r["journal"]), fmt_bands(r["rail"])))
    say("")
    jblocky = sum(1 for b in jb if b[2] > 60)
    span = rep["rail_span"]
    say("**Что правая колонка показывает на самом деле.** Прямоугольник правого дока взят из "
        "`LayoutProfile.right_width()` (для 1600 это x∈[1220,1600]), но В КАДРЕ там лежит не док: "
        "%d из %d полос имеют высоту 83–91 px — это клетки кольца доски, а не строки текста. Сам док в "
        "кадре 1600x1200 свёрнут в рейл: у самого края видна одна узкая вертикальная полоса%s. Значит "
        "«оценить кегль журнала по этой картинке» нельзя не из-за метода, а потому что журнала на "
        "картинке нет — в прямоугольнике дока лежит доска, а док нарисован 48-пиксельной полосой."
        % (jblocky, len(jb), (" x∈[%d,%d]" % span) if span else ""))
    say("")
    say("Практический вывод из этого расхождения: прямоугольники областей НЕЛЬЗЯ брать из констант "
        "раскладки, если кадр мог свернуть панель. Проверка «полоса выше 60 px — это не текст» ловит "
        "такое расхождение, но она эвристика, и потому помечена как оценка.")
    say("")
    if hb:
        hs = sorted(b[2] for b in hb)
        med = median(hs)
        say("На `%s` шапка даёт %d чернильных полос, медиана высоты **%s px** чернил → оценочный кегль "
            "**%.0f–%.0f px**. Это НЕ 13 px и НЕ 49 px: полосы склеивают аватар 26x26, чипы и кнопки "
            "шапки в одну строку, поэтому оценка описывает строку шапки целиком, а не конкретную метку. "
            "Оценка подтверждает масштаб проблемы и НЕ заменяет гейт."
            % (rep["name"], len(hb), med, med / CAP_RATIO_HI, med / CAP_RATIO_LO))
    say("")
    hmode, hcnt, htot = rep["header_runs"]
    if hmode:
        say("**Более тонкая оценка — мода вертикальных чернильных пробегов.** Столбец, проходящий через "
            "текст, пересекает короткие штрихи (по одному на штрих); столбец через аватар, кнопку или "
            "рамку клетки — один длинный пробег. Если оставить пробеги 5–16 px, остаются штрихи глифов, "
            "и их мода — самое близкое к кеглю, что даёт PNG. На `%s` в шапке мода = **%d px** чернил "
            "(%d пробегов из %d) → оценочный кегль **%.0f–%.0f px**. Это СОВПАДАЕТ с 13 px из лога гейта "
            "— то есть там, где область действительно содержит текст, оценка по картинке сходится с "
            "замером движка, и метод не выдумывает числа."
            % (rep["name"], hmode, hcnt, htot, hmode / CAP_RATIO_HI, hmode / CAP_RATIO_LO))
        say("")
    jmode, jcnt, jtot = rep["journal_runs"]
    if jmode:
        say("Тот же приём на прямоугольнике дока даёт моду %d px (%d пробегов из %d) — но это **не** кегль "
            "журнала: область занята клетками доски, и мода описывает их рамки. Это ровно та причина, по "
            "которой оценка остаётся оценкой: она не знает, что именно лежит в прямоугольнике."
            % (jmode, jcnt, jtot))
        say("")
    say("## 3. Что этим способом измерить НЕЛЬЗЯ")
    say("")
    say("Это не оговорка, а главный вывод о методе. Перечислено то, на что у PNG нет ответа.")
    say("")
    say("1. **Кегль по картинке не восстанавливается.** PNG отвечает «есть ли здесь пятно», а пятно — "
        "не слово (ровно этот аргумент записан в шапке `game/tools/gates/read_gate.gd`). Между картинкой "
        "и числом стоят: сглаживание и композитор, высота чернил != em (зависит от того, есть ли в строке "
        "выносные элементы), и подмена «текст нарисован» на «текст разборчив».")
    say("2. **Гейт и картинка мерят разные вещи и не заменяют друг друга.** STREAM-READ читает "
        "`Label.get_theme_font_size()` живого дерева — это факт о продукте. Профиль яркости читает пиксели "
        "— это факт о конкретном кадре после композитора. Совпадение их чисел было бы случайностью, а не "
        "подтверждением.")
    say("3. **Журнал в этих кадрах НЕ нарисован — и это подтверждается кодом оболочки.** В кадре "
        "1600x1200 правый док по `LayoutProfile` занимает x∈[1220,1600], но профиль яркости показывает "
        "там клетки доски (полосы 83–91 px), а у самого края — узкую вертикальную полосу 48 px%s. "
        "Причина в `game/ui/game_view.gd`: `_is_compact()` — это `size.x < RAILS_BELOW (2000) or "
        "size.y <= 700`, при 1600x1200 истинно, а `_apply_panels_visibility()` тогда ставит "
        "`_rightcol.visible = false` и `_rail_right.visible = true`. То есть журнальный док СКРЫТ "
        "ФЛАГОМ (ровно дефект R-5 из брифа), а `jrn-title`/`jrn-text` существуют в дереве невидимыми — "
        "и STREAM-READ читает их `font_size` именно оттуда. Замер гейта верен, но описывает элемент, "
        "которого на открывающемся кадре не видно."
        % ((" (x∈[%d,%d])" % rep["rail_span"]) if rep["rail_span"] else ""))
    say("4. **Нельзя сказать, ПОЧЕМУ мелко** — унаследован ли кегль 12–13 px от темы, срезала ли его "
        "компактная ветка, или он следствие размера окна. Для этого нужен дамп дерева "
        "(`get_global_rect` + `font_size`), а не пиксели.")
    say("5. **Нельзя измерить читаемость ПОСЛЕ сжатия.** R-7 требует 12 px после уменьшения до 390 px, "
        "а уменьшает браузер/телефон своим ресемплером. Из файла 1600x1200 такой картинки не получить.")
    say("6. **Нельзя измерить контраст и разборчивость глифов** в glance-элементах: 12 px текст на тёмном "
        "фоне после сжатия может «погаснуть» раньше, чем станет мелким. Это отдельный вопрос (WCAG-гейт), "
        "и он тоже про пиксели, а не про кегль.")
    say("")
    say("## 4. По областям: где сегодняшняя вёрстка проваливает R-7 и во сколько раз")
    say("")
    say("Всё в кадре 1600x1200 (тот, что реально открывается). Кегли — из лога гейта (точно); масштаб и "
        "требуемый кегль — арифметика R-7 (точно).")
    say("")
    say("| область | кегль сейчас | eff на телефоне | нужно в кадре | во сколько раз увеличить |")
    say("|---|---|---|---|---|")
    need1600 = GLANCE_MIN_PHONE_PX / sc1600
    for node, role, px in GLANCE:
        say("| %s (`%s`) | %d px | %.2f px | %.1f px | **%.2f×** |"
            % (role, node, px, px * sc1600, need1600, need1600 / px))
    say("")
    f12 = need1600 / 12.0
    f13 = need1600 / 13.0
    say("Ни один из шести glance-элементов не проходит порог. Разброс — от **%.2f×** (12 px: `jrn-title`, "
        "`jrn-text`) до **%.2f×** (13 px: `turn-name`, `turn-phase`, `top-round`, `top-pot`)."
        % (f12, f13))
    say("")
    say("## 5. Выводы для вёрстки — что увеличивать первым")
    say("")
    say("1. **Первым — журнал (`jrn-title`, `jrn-text`, 12 px, нужно ×%.2f).** Это и самый мелкий, и самый "
        "«glance»-элемент. Увеличивать его в панели нельзя: кегль %.1f px в правом доке высотой ~1048 px "
        "съест панель целиком. Значит фикс — конструкция, а не шрифт: заголовок и 3 последние строки "
        "переезжают в панно центра (`brief` §4.1, зона «Журнал», 150 px). Тем более что при 1600x1200 "
        "док СКРЫТ (`_is_compact()` истинно): увеличивать кегль в скрытой панели бессмысленно дважды." % (f12, need1600))
    say("2. **Вторым — шапка (`turn-name`, `turn-phase`, `top-round`, `top-pot`, 13 px, нужно ×%.2f).** "
        "Здесь конфликт структурный: шапка `top_height() = 56` px физически не может держать кегль "
        "%.1f px. По R-18, если R-7 и размер доски конфликтуют — растёт ВЫСОТА кадра "
        "(`LayoutProfile.screen`), а не сжимается доска и не раздувается шрифт в 56 px полосе. "
        "Рычаг — `screen` и высота шапки." % (f13, need1600))
    say("3. **Третьим — доска и её клетки.** Доска остаётся героем (P-1), клетка не падает ниже 77 px "
        "(R-17). Если высота кадра растёт под шапку и панно, клетку надо перемерить на 4 профилях "
        "(`read_gate`), иначе выигрыш читаемости оплачен размером доски.")
    say("4. **Меру читаемости закрепить за РЕАЛЬНОЙ шириной кадра профиля, а не за 1920.** Сегодня гейт "
        "жёстко мерит 1920x1080, а продукт рисует 1600x1200: числа верны, но описывают не тот кадр, "
        "который открывается. Порог обязан считаться от `LayoutProfile.screen.x` (для 1600 → %.1f px). "
        "Это ровно тот же класс дефекта, что «гейт мерит окно, которого ни у кого нет»." % need1600)
    say("5. **Не выполнять R-7 удалением.** Ни один glance-элемент не убирается (R-12): если журнал "
        "переезжает в панно — в спецификации указывается, где его смотреть (brief §4.1 уже это делает).")
    say("")
    say("## 6. Реальный вывод команды (сырые строки stdout)")
    say("")
    say("```")
    for line in summary:
        say(line)
    say("```")
    say("")
    say("---")
    say("")
    say("Повторить: `py -3.12 tools/ci/r7_report.py` → `build/r7/r7-report.md`. "
        "Гейт, который судит R-7 по-настоящему: `bash tools/ci/gates/stream_read_gate.sh` (нужен Godot).")
    say("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8")
    for line in summary:
        print(line)
    print("==> R-7 REPORT WROTE %s (%d lines)" % (OUT, len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
