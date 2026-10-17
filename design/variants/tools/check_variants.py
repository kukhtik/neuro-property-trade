"""Static compliance checks for an NPT UI variant mockup (HTML).

Checks that CAN be decided from the file text, per docs/specs/ui-redesign-brief.md:
  file      : self-contained, single file, no <script>, no external http(s) asset
  canvas    : body 1600x1200
  R-9/R-10  : no icon glyphs / emoji in visible text (words only; — • … → allowed)
  R-4/R-5   : the five on-turn facts are present in the markup (turn, phase, dice+sum,
              cash of ALL four seats, last event)
  content   : the scene data of scene-data.md is used verbatim (seat names, cash, journal)
  board     : at least 40 tile-ish elements

Usage: py -3.12 check_variants.py <file.html> [...]
"""
import re
import sys
from pathlib import Path

EMOJI_RANGES = [(0x2600, 0x27BF), (0x1F000, 0x1FAFF), (0x25A0, 0x25FF),
                (0x2190, 0x21FF), (0x2B00, 0x2BFF), (0xFE0F, 0xFE0F)]
ALLOWED_GLYPHS = {"\u2192", "\u2014", "\u2022", "\u2026"}  # -> — • …
CASH = ["$1215", "$980", "$640", "$1500"]
NAMES = ["Хост", "Neuro", "evil", "Mira"]
JOURNAL = ["Mira бросает 4+4", "Mira продаёт с клетки 27",
           "evil закладывает клетку 11", "evil попадает в тюрьму"]


def bad_glyphs(text):
    out = []
    for ch in text:
        if ch in ALLOWED_GLYPHS:
            continue
        cp = ord(ch)
        if any(lo <= cp <= hi for lo, hi in EMOJI_RANGES):
            out.append(ch)
    return sorted(set(out))


def main(files):
    fails_total = 0
    for f in files:
        p = Path(f)
        src = p.read_text(encoding="utf-8", errors="replace")
        body = re.sub(r"<style.*?</style>", "", src, flags=re.S | re.I)
        body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
        res = []

        def check(name, ok, detail=""):
            res.append((ok, name, detail))

        ext = re.findall(r'(?:src|href)\s*=\s*"(https?:[^"]+)"', src, re.I)
        check("self-contained (no external asset)", not ext, ",".join(ext[:3]))
        check("no <script>", not re.search(r"<script", src, re.I))
        check("canvas body 1600x1200",
              bool(re.search(r"width\s*:\s*1600px", src)) and bool(re.search(r"height\s*:\s*1200px", src)))
        glyphs = bad_glyphs(body)
        check("R-9/R-10 no icon glyphs", not glyphs, "".join(glyphs))
        check("R-4 turn owner", "ХОД" in body.upper() or "ход" in body)
        check("R-4 phase", "ФАЗА" in body.upper())
        check("R-4 dice 5+3 and sum 8",
              ("5" in body and "3" in body) and bool(re.search(r">\s*8\s*<", body)))
        for c in CASH:
            check(f"R-4 cash {c} visible", c in body)
        for n in NAMES:
            check(f"scene seat {n}", n in body)
        check("R-4 last event", any(j.split()[1] in body for j in JOURNAL) or "Crest Square" in body)
        for j in JOURNAL:
            check(f"scene journal line “{j}”", j in body)
        check("board has >=40 tiles", len(re.findall(r'class="[^"]*tile[^"]*"', src, re.I)) >= 40,
              str(len(re.findall(r'class="[^"]*tile[^"]*"', src, re.I))))
        check("R-15 hero action word", "Бросок" in body)

        bad = [r for r in res if not r[0]]
        fails_total += len(bad)
        print(f"=== {p.name}: {len(res) - len(bad)}/{len(res)} checks passed")
        for ok, name, detail in res:
            if not ok:
                print(f"  FAIL {name} {('— ' + detail) if detail else ''}")
    print(f"\nTOTAL FAILS: {fails_total}")
    return 1 if fails_total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
