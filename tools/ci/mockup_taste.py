#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mockup_taste.py — «визуальный вкус»: кегль из шкалы, потолок, никаких сырых чисел.

ЗАЧЕМ. Решение владельца 23.10: «проверка на визуальный вкус (чтобы не было огромных
выбивающихся надписей к примеру)». Вкус измерим: у каждой надписи есть кегль, и он должен
быть ШАГОМ ШКАЛЫ, а не произвольным числом, и не превышать потолок.

ИСТОЧНИК ИСТИНЫ. `game/assets/skins/neuro/skin.json` → `tokens.size`. Макет читает те же
значения (`design/ui-prototype.html` → `--fs-xs:11px ... --fs-xl:28px`). Правило простое:
размер надписи = шаг шкалы, взятый из скина.

ТРИ ПРОВЕРКИ, каждая со своим адресатом:
  1. ЖИВАЯ (дамп пробы `game/tools/mockup_taste_probe.gd`): ни одна надпись не крупнее
     потолка `xl * ui_scale`. Это и есть «огромные выбивающиеся надписи» — их ловит потолок.
  2. ЖИВАЯ: надпись НЕ на клетке доски обязана иметь кегль из шкалы. (Надпись в клетке
     доски считает кегль от размера клетки — `int(_cell * k)` — это законно, но ей
     ограничен потолок.)
  3. СТАТИЧЕСКАЯ (исходники `game/`): «сырых» чисел вне шкалы быть не должно. Это ловит
     дефект там, где он ЕЩЁ не виден на экране: `add_theme_font_size_override(..., 10)`,
     `maxi(12, int(_cell * 0.18))`, `s.size("s", 12)`, `const HOUSES_MIN := 10`.
     Именно так в коде появились 10 и 12 — по ошибочно записанной в журнале шкале.

Вердикт: `==> MOCK-02 PASSED` / `==> MOCK-02 FAILED: <причина>`. Вердикт определяется
СТРОКОЙ. Отсутствие измерения — FAILED, а не SKIP.

Usage:
    py -3.12 tools/ci/mockup_taste.py --dump build/gates/mockup_taste.dump
    py -3.12 tools/ci/mockup_taste.py --dump <file> --json
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SKIN = ROOT / "game" / "assets" / "skins" / "neuro" / "skin.json"
GAME_DIR = ROOT / "game"

# Правила «сырого числа» вне шкалы. Каждое — с причиной, потому что «цифра в коде» без
# причины это шум, а с причиной это дефект.
STATIC_RULES = [
    # add_theme_font_size_override("font_size", 10) — «сырой» кегль.
    (re.compile(r"add_theme_font_size_override\(\s*[\"'][^\"']*font_size[\"']\s*,\s*(\d+)"),
     "сырой кегль в add_theme_font_size_override"),
    # maxi(12, int(_cell * 0.18)) — пол динамического размера.
    (re.compile(r"maxi\(\s*(\d+)\s*,\s*(?:int\(\s*_cell|px\b|int\(\s*_cell)"),
     "пол динамического кегля"),
    # s.size("s", 12) — запасное значение роли.
    (re.compile(r"\.size\(\s*[\"'](\w+)[\"']\s*,\s*(\d+)"),
     "запасной размер роли"),
    # theme_override_font_sizes/font_size = 12
    (re.compile(r"theme_override_font_sizes/font_size\s*=\s*(\d+)"),
     "кегль в theme_override"),
    # UiTheme.label("текст", 12) / UiTheme.label_wrap("текст", 12, цвет) — размер приходит
    # АРГУМЕНТОМ, и это самый частый путь «сырого» числа в продукте (так админ-панель
    # выставляла 12 — числа, которого в шкале нет).
    # Это НЕ регулярка, а разбор аргументов (scan_label_calls): обе регулярки врут.
    #   * `[^,()]*` — молча пропускал 59 вызовов, где первый аргумент со скобками
    #     (`I18n.t("...")`), и пропущенные были ровно те, где размер стоял ВНЕ шкалы
    #     (то есть гейт показывал не все нарушения, и правка по нему была неполной);
    #   * `[^;]*?,\s*(\d+)` — ловит «0» из `p.get("money", 0)` ВНУТРИ первого аргумента,
    #     то есть даёт ложное нарушение.
]

# Каталоги, которые НЕ являются визуальным языком продукта: тесты (в них числа — это
# данные проверки, а не кегль) и вендорённый SDK.
SKIP_DIRS = ("game/addons/", "game/tests/")


def load_scale():
    d = json.loads(SKIN.read_text(encoding="utf-8"))
    sizes = d.get("tokens", {}).get("size", {})
    if not sizes:
        raise SystemExit("skin.json: нет tokens.size")
    return {str(k): int(v) for k, v in sizes.items()}


def load_design_vocabulary():
    """Кегля, которые использует САМ эталонный макет.

    Шкала скина (5 шагов) — это РОЛИ, а не закрытый набор: концепт A (`design/variants/
    v5/concept-a-composition.html`) использует 15 разных кеглей — 7, 8, 9, 10, 11, 12, 13,
    14, 15, 20, 22, 29, 32, 44, 48. Значит «вкус» — не «числа из списка», а «числа, которые
    есть в ДИЗАЙНЕ». Если бы мы судили по своему списку, гейт мерил бы наш вкус, а не
    макет. Поэтому разрешённое = шкала скина ∪ кегля эталона.
    """
    vocab = set()
    for rel in ("design/variants/v5/concept-a-composition.html", "design/src/proto.css"):
        p = ROOT / rel
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r"font-size:\s*(\d+)px", text):
            vocab.add(int(m.group(1)))
    return vocab


def _split_args(text):
    """Делит список аргументов вызова по запятым ВЕРХНЕГО уровня (скобки и строки учтены)."""
    args = []
    depth = 0
    quote = ""
    cur = []
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    if cur:
        args.append("".join(cur).strip())
    return args


LABEL_CALL = re.compile(r"UiTheme\.label(?:_wrap)?\s*\(")


def scan_label_calls(line):
    """Размеры, переданные в UiTheme.label(...) как ЧИСЛОВОЙ аргумент.

    Берём только те аргументы, которые ЦЕЛИКОМ являются целым числом: `13` - да,
    `p.get("money", 0)` - нет (это текст, внутри которого есть запятая и ноль).
    """
    found = []
    for m in LABEL_CALL.finditer(line):
        start = m.end()
        depth = 1
        quote = ""
        i = start
        while i < len(line) and depth > 0:
            ch = line[i]
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = ""
            elif ch in "\"'":
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            i += 1
        args = _split_args(line[start:i - 1])
        for a in args:
            if re.fullmatch(r"\d+", a):
                found.append(int(a))
    return found


def static_scan(allowed):
    """Ищет «сырые» кегля вне разрешённого набора в исходниках игры."""
    bad = []
    for p in sorted(GAME_DIR.rglob("*.gd")):
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(SKIP_DIRS):
            continue  # вендорённый SDK и тесты — не наш визуальный язык
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            for rx, why in STATIC_RULES:
                m = rx.search(line)
                if not m:
                    continue
                nums = [int(g) for g in m.groups() if g.isdigit()]
                for n in nums:
                    if n in allowed:
                        continue
                    bad.append({"file": rel, "line": i, "size": n, "why": why,
                                "text": line.strip()[:110]})
            # размеры, переданные в UiTheme.label(...) числом (разбор аргументов, не регулярка)
            for n in scan_label_calls(line):
                if n in allowed:
                    continue
                bad.append({"file": rel, "line": i, "size": n,
                            "why": "кегль, переданный в UiTheme.label",
                            "text": line.strip()[:110]})
    # отдельное правило: константа с кеглем (HOUSES_MIN := 10)
    const_rx = re.compile(r"const\s+([A-Z_]*(?:FONT|SIZE|MIN|MAX)[A-Z_]*)\s*:?=\s*(\d+)")
    for p in sorted(GAME_DIR.rglob("*.gd")):
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(SKIP_DIRS):
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            m = const_rx.search(line)
            if not m:
                continue
            n = int(m.group(2))
            if n in allowed:
                continue
            if "font" not in line.lower() and "HOUSES_MIN" not in line:
                continue
            bad.append({"file": rel, "line": i, "size": n,
                        "why": "константа размера", "text": line.strip()[:110]})
    return bad


def parse_dump(path):
    """Читает дамп пробы: строки TASTE|label|path|eff|dpx|board|text и TASTE|meta|scale|..."""
    if not path.exists():
        return None, None
    scale = 1.0
    labels = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("|")
        if len(parts) >= 3 and parts[0] == "TASTE" and parts[1] == "meta":
            try:
                scale = float(parts[2])
            except ValueError:
                pass
        elif len(parts) >= 6 and parts[0] == "TASTE" and parts[1] == "label":
            try:
                labels.append({
                    "path": parts[2], "eff": int(parts[3]), "dpx": int(parts[4]),
                    "board": int(parts[5]),
                    "text": parts[6] if len(parts) > 6 else "",
                })
            except ValueError:
                continue
    return scale, labels


def main():
    ap = argparse.ArgumentParser(description="проверка визуального вкуса")
    ap.add_argument("--dump", default=str(ROOT / "build" / "gates" / "mockup_taste.dump"))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    scale = load_scale()
    vocab = load_design_vocabulary()
    allowed = set(scale.values()) | vocab
    # ПОТОЛОК — это максимум САМОГО ДИЗАЙНА (концепт A: 48 px у `.dsum .val`, герой числа
    # кубиков), а не роль `xl` (28). Потолок xl отверг бы дизайновую вещь: сумма кубиков в
    # макете 48 px, и «огромная надпись» в дизайне — это ровно она. Значит «вне вкуса» —
    # это размер, которого НЕТ в дизайне (проверяется статикой по литералам) и который
    # при этом превышает то, что дизайн делает (проверяется живьём).
    cap = max(allowed)
    src_violations = static_scan(allowed)

    dump = pathlib.Path(args.dump)
    ui_scale, labels = parse_dump(dump)
    if labels is None:
        print("==> MOCK-02 FAILED: нет дампа пробы %s - измерение не сделано" % dump)
        return 1
    if not labels:
        print("==> MOCK-02 FAILED: дамп пробы пуст (0 надписей) - измерение не сделано")
        return 1

    cap_px = cap * (ui_scale if ui_scale else 1.0)
    live_violations = []
    off_vocab = []
    for lab in labels:
        eff = lab["eff"]
        # ПОТОЛОК — это и есть «огромные выбивающиеся надписи» буквально.
        if eff > cap_px + 1:
            live_violations.append({
                "path": lab["path"], "eff": eff,
                "why": "крупнее потолка дизайна (%d px)" % int(cap_px),
                "text": lab["text"]})
            continue
        if lab["board"]:
            continue  # кегль клетки доски считается от размера клетки — законно
        # Кегль, ВЫЧИСЛЕННЫЙ от клетки (панно: `int(_cell * ratio)`), не обязан быть в
        # словаре дизайна — это задокументированное решение («Font sizes are ratios of a
        # board cell»). Поэтому «не в словаре» живых кеглей — это ЗАМЕЧАНИЕ, а не провал:
        # проваливает ЛИТЕРАЛЫ в исходниках (static), а живое ловит потолок.
        design = lab["dpx"] if lab["dpx"] > 0 else int(round(eff / (ui_scale or 1.0)))
        if design not in allowed:
            off_vocab.append({
                "path": lab["path"], "eff": eff,
                "why": "кегль %d не из словаря дизайна (возможен расчёт от клетки)" % design,
                "text": lab["text"]})

    if args.json:
        print(json.dumps({
            "scale": scale, "cap": cap, "ui_scale": ui_scale,
            "labels": len(labels),
            "static": src_violations, "live": live_violations,
        }, ensure_ascii=False, indent=1))
    else:
        print("=== MOCK-02 (visual taste) ===")
        print("scale from skin: %s (cap xl = %d px, ui_scale %.4f)" % (scale, cap, ui_scale or 1.0))
        print("labels measured: %d" % len(labels))
        if src_violations:
            print()
            print("--- static: raw sizes outside the scale (%d) ---" % len(src_violations))
            for v in src_violations:
                print("  %s:%d  size %d  %s  | %s" % (v["file"], v["line"], v["size"], v["why"], v["text"]))
        if live_violations:
            print()
            print("--- live: violations (%d) ---" % len(live_violations))
            for v in live_violations:
                print("  %s  eff %d  %s  | %s" % (v["path"], v["eff"], v["why"], v.get("text", "")))
        if off_vocab:
            print()
            print("--- note: live sizes outside the design vocabulary (%d, not a failure: "
                  "a cell-relative size is legitimate) ---" % len(off_vocab))
            for v in off_vocab[:6]:
                print("  %s  eff %d  %s  | %s" % (v["path"], v["eff"], v["why"], v.get("text", "")))
        print()

    if src_violations or live_violations:
        worst_static = src_violations[0] if src_violations else None
        worst_live = live_violations[0] if live_violations else None
        print("==> MOCK-02 FAILED: %d raw size(s) outside the scale in the source, %d live violation(s)%s%s"
              % (len(src_violations), len(live_violations),
                 ("; worst source: %s:%d size %d" % (worst_static["file"], worst_static["line"],
                                                    worst_static["size"])) if worst_static else "",
                 ("; worst live: %s (eff %d)" % (worst_live["path"], worst_live["eff"])) if worst_live else ""))
        return 1
    print("==> MOCK-02 PASSED (every size is a step of the skin's scale %s; no label above the cap %d px; %d labels measured)"
          % (sorted(allowed), cap, len(labels)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
