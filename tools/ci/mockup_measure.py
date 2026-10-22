#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mockup_measure.py — измеритель расхождения «макет против живого кадра».

ЗАЧЕМ. Владелец (23.10) потребовал вместо отменённой телефонной проверки проверку
КОНСИСТЕНТНОСТИ: «чтобы визуал не разваливался и всё было там и выглядело так как
должно быть, по пиксельное сравнение с макетом». Этот инструмент — тот самый замер.

ПОЧЕМУ НЕ ПОСТРОЧНЫЙ DIFF. В `tools/ci/compare_mockup.py` сказано прямо: «different
fonts, different scales - a pixel diff would flag everything and say nothing». Макет
рисует HTML в Chromium, игра - Godot; шрифты и сглаживание разные, и построчный diff
на 1600x1200 отметил бы ВСЁ. Поэтому сравниваем **структурно, по пикселям внутри зон**:
доля «не-фоновых» пикселей в каждой ячейке сетки и по кадру целиком. Это ровно тот
замер, которым §7 журнала измерял разрыв (сетка 8x6, доля ink).

АЛГОРИТМ ФОНА — ТОТ ЖЕ, ЧТО В ГЕЙТЕ `FILL` (`game/tools/gates/fill_gate.gd`):
фон = самый частый цвет ПОЛОСЫ по краю кадра (6 px, выборка через 3 px), «не фон» =
канал отличается больше чем на TOL/255. Фон берётся из КАДРА, а не из токенов: гейт
обязан работать на любом скине. Полоска, а не весь кадр — потому что самый частый цвет
всего кадра у живого продукта это `surface.2` панно (41 % кадра), и гейт начал бы
считать панель фоном.

ДОГОВОР ВЕРДИКТА. Печатает строку `==> MOCKUP-MEASURE PASSED` или
`==> MOCKUP-MEASURE FAILED: <причина>`; вердикт определяется СТРОКОЙ, а не кодом
возврата (так же, как во всех гейтах этого репозитория). Отсутствие измерения -
это FAILED, а не SKIP: «гейт, который ничего не измерил, - красный».

Usage:
    py -3.12 tools/ci/mockup_measure.py
    py -3.12 tools/ci/mockup_measure.py --mockup <png> --frame <png> --tolerance 12
    py -3.12 tools/ci/mockup_measure.py --json          # машинный вывод для гейта
"""

import argparse
import json
import pathlib
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - Pillow есть у `py -3.12`
    print("==> MOCKUP-MEASURE FAILED: нужен Pillow (py -3.12 -m pip install Pillow)")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_FRAME = ROOT / "build" / "renders" / "turn-human_neuro.png"
DEFAULT_MOCKUP = ROOT / "build" / "renders" / "side_by_side-turn-human-neuro-mockup.png"

TOL = 6              # /255, тот же допуск «не фон», что в fill_gate.gd
BAND = 6             # px, полоса по краю, из которой берётся фон
BAND_STEP = 3        # px, шаг выборки в полосе
CELL_STEP = 4        # px, шаг выборки внутри ячейки сетки
GRID = (8, 6)        # сетка зон: как в §7 журнала
DEFAULT_TOLERANCE = 12.0   # п.п., допуск расхождения доли ink по зоне

# Зона кольца в долях кадра (те же числа, что в fill_gate.gd: замер живого дерева).
RING = (0.231, 0.060, 0.536, 0.536)


def _bg_of(img):
    """Самый частый цвет полосы по краю кадра — фон приложения."""
    w, h = img.size
    counts = {}
    for y in range(0, h, BAND_STEP):
        for x in range(0, w, BAND_STEP):
            if x < BAND or y < BAND or x >= w - BAND or y >= h - BAND:
                c = img.getpixel((x, y))[:3]
                k = (c[0] // 8, c[1] // 8, c[2] // 8)
                counts[k] = counts.get(k, 0) + 1
    if not counts:
        return (0, 0, 0)
    best = max(counts.items(), key=lambda kv: kv[1])[0]
    return (best[0] * 8 + 4, best[1] * 8 + 4, best[2] * 8 + 4)


def _differs(px, bg):
    return (abs(px[0] - bg[0]) > TOL or abs(px[1] - bg[1]) > TOL
            or abs(px[2] - bg[2]) > TOL)


def _ink_fraction(img, rect, bg):
    """Доля пикселей «не фон» внутри прямоугольника (в процентах)."""
    w, h = img.size
    x0, y0, x1, y1 = rect
    x0 = max(0, int(x0)); y0 = max(0, int(y0))
    x1 = min(w, int(x1)); y1 = min(h, int(y1))
    n = 0
    tot = 0
    for y in range(y0, y1, CELL_STEP):
        for x in range(x0, x1, CELL_STEP):
            tot += 1
            if _differs(img.getpixel((x, y))[:3], bg):
                n += 1
    return (100.0 * n / tot) if tot else 0.0


def _zones(img, bg, gx, gy):
    w, h = img.size
    cw = w / gx
    ch = h / gy
    out = []
    for j in range(gy):
        row = []
        for i in range(gx):
            row.append(_ink_fraction(img, (i * cw, j * ch, (i + 1) * cw, (j + 1) * ch), bg))
        out.append(row)
    return out


def measure(path):
    img = Image.open(path).convert("RGB")
    bg = _bg_of(img)
    w, h = img.size
    gx, gy = GRID
    zones = _zones(img, bg, gx, gy)
    overall = _ink_fraction(img, (0, 0, w, h), bg)
    rx, ry, rw, rh = RING
    ring = _ink_fraction(img, (rx * w, ry * h, (rx + rw) * w, (ry + rh) * h), bg)
    return {"size": (w, h), "bg": bg, "zones": zones, "overall": overall, "ring": ring}


def main():
    ap = argparse.ArgumentParser(description="измеритель «макет против кадра»")
    ap.add_argument("--mockup", default=str(DEFAULT_MOCKUP))
    ap.add_argument("--frame", default=str(DEFAULT_FRAME))
    ap.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE,
                    help="допуск расхождения доли ink по зоне, п.п. (по умолчанию %.1f)" % DEFAULT_TOLERANCE)
    ap.add_argument("--json", action="store_true", help="машинный вывод вместо таблицы")
    args = ap.parse_args()

    mp = pathlib.Path(args.mockup)
    fp = pathlib.Path(args.frame)
    for p in (mp, fp):
        if not p.exists():
            print("==> MOCKUP-MEASURE FAILED: нет файла %s" % p)
            return 1

    mock = measure(mp)
    frame = measure(fp)

    if mock["size"] != frame["size"]:
        print("==> MOCKUP-MEASURE FAILED: frames differ in size: frame %dx%d, mockup %dx%d"
              % (frame["size"][0], frame["size"][1], mock["size"][0], mock["size"][1]))
        return 1

    gx, gy = GRID
    over = []
    for j in range(gy):
        for i in range(gx):
            d = frame["zones"][j][i] - mock["zones"][j][i]
            if abs(d) > args.tolerance:
                over.append((j, i, frame["zones"][j][i], mock["zones"][j][i], d))
    over.sort(key=lambda r: -abs(r[4]))
    d_all = frame["overall"] - mock["overall"]

    if args.json:
        print(json.dumps({
            "frame": str(fp), "mockup": str(mp), "size": frame["size"],
            "tolerance": args.tolerance,
            "zones_frame": frame["zones"], "zones_mockup": mock["zones"],
            "overall_frame": frame["overall"], "overall_mockup": mock["overall"],
            "ring_frame": frame["ring"], "ring_mockup": mock["ring"],
            "over_tolerance": [{"row": r, "col": c, "frame": f, "mockup": m, "delta": d}
                               for (r, c, f, m, d) in over],
        }, ensure_ascii=False, indent=1))
    else:
        print("=== MOCKUP-MEASURE ===")
        print("frame : %s (%dx%d)" % (fp, frame["size"][0], frame["size"][1]))
        print("mockup: %s (%dx%d)" % (mp, mock["size"][0], mock["size"][1]))
        print("tolerance: %.1f p.p.  (фон кадра: frame %s, mockup %s)"
              % (args.tolerance, frame["bg"], mock["bg"]))
        print()
        print("zone          frame%   mockup%     delta")
        for j in range(gy):
            for i in range(gx):
                d = frame["zones"][j][i] - mock["zones"][j][i]
                mark = "  <<<" if abs(d) > args.tolerance else ""
                print("r%d c%d      %7.1f  %7.1f  %+8.1f%s"
                      % (j, i, frame["zones"][j][i], mock["zones"][j][i], d, mark))
        print()
        print("overall ink : frame %.1f%%  mockup %.1f%%  delta %+.1f p.p."
              % (frame["overall"], mock["overall"], d_all))
        print("ring centre : frame %.1f%%  mockup %.1f%%  delta %+.1f p.p."
              % (frame["ring"], mock["ring"], frame["ring"] - mock["ring"]))
        if over:
            print()
            print("--- over tolerance: %d zone(s) ---" % len(over))
            for (j, i, f, m, d) in over:
                print("  r%d c%d: frame %.1f%% vs mockup %.1f%% (delta %+.1f p.p.)" % (j, i, f, m, d))
        print()

    if over:
        worst = over[0]
        print("==> MOCKUP-MEASURE FAILED: %d zone(s) over tolerance %.1f p.p. (worst: r%d c%d %+.1f p.p.)"
              % (len(over), args.tolerance, worst[0], worst[1], worst[4]))
        return 1
    print("==> MOCKUP-MEASURE PASSED (every zone within %.1f p.p.; overall ink delta %+.1f p.p.)"
          % (args.tolerance, d_all))
    return 0


if __name__ == "__main__":
    sys.exit(main())

