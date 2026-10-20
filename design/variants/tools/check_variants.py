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
        # The TEXT of the mockup, with the markup taken out. Without this, a mockup that
        # emphasises part of a line - `<b>Mira</b> бросает 4+4` - cannot match a check that
        # looks for the literal "Mira бросает 4+4", and a perfectly good journal line is
        # reported missing. The 19.10 sweep files happened to put each line inside ONE
        # span, so they never hit it; concept A puts the name in <b> and did.
        # A tag is markup, not content: the check is about WHAT the screen says.
        text = re.sub(r"<[^>]+>", " ", body)
        text = re.sub(r"&nbsp;?", " ", text)
        text = re.sub(r"\s+", " ", text)
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
        # the CONTENT checks read the TEXT, not the markup - see the note on `text` above
        check("R-4 turn owner", "ХОД" in text.upper() or "ход" in text)
        check("R-4 phase", "ФАЗА" in text.upper())
        check("R-4 dice 5+3 and sum 8",
              ("5" in text and "3" in text) and bool(re.search(r">\s*8\s*<", body)))
        for c in CASH:
            # "$1215" - but a mockup may split the sign and the number into two elements
            # (`<span>$</span><span>1215</span>`), which the tag-stripped text renders as
            # "$ 1215". Both are the same amount on the screen.
            amount = c.lstrip("$")
            check(f"R-4 cash {c} visible",
                  c in text or re.search(r"\$\s*" + re.escape(amount) + r"\b", text) is not None)
        for n in NAMES:
            check(f"scene seat {n}", n in text)
        check("R-4 last event", any(j.split()[1] in text for j in JOURNAL) or "Crest Square" in text)
        for j in JOURNAL:
            check(f"scene journal line “{j}”", j in text)
        # A WHOLE BOARD, NOT A FRAGMENT. The check must count the board's OWN elements, and the
        # name they carry is a convention, not a fact: the first sweep used `class="tile"`, the
        # product uses `data-cell` (and `cell_flashing`, `_cell`), and concept A used
        # `class="c corner" data-cell="0"`. Counting only the words "tile"/"cell" in a class
        # string called a perfectly good 40-cell board a fragment, and the 19.10 sweep files -
        # which the same check calls 22/22 - would also have failed it. So: an element counts
        # as a board cell when it CARRIES the board's own marker (data-cell=), and that
        # marker is what the product's own tests and probes look for. The class-name heuristic
        # stays as a second way in, for a mockup that names its cells but marks them otherwise.
        marked = len(re.findall(r'data-cell\s*=', src))
        tile_like = len(re.findall(r'class="[^"]*(tile|cell)[^"]*"', src, re.I))
        board_cells = max(marked, tile_like)
        check("board has >=40 tiles", board_cells >= 40, f"marked={marked} class_named={tile_like}")
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
