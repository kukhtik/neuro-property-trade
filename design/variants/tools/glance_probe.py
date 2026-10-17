"""R-7 evidence for a variant mockup: what font sizes the "at a glance" facts are rendered at
(brief §3.3). For every pattern the probe reports the SIZE RANGE of elements carrying it —
the glance element is the largest rendering, so the max is the number that matters.

Also reports the largest text inside the board ring (the dice sum should win there) and the
tile size (ring width / 11; R-17 floor 77px at the 1600x1200 canvas).

Usage: py -3.12 glance_probe2.py <file.html> [...]
"""
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

W, H = 1600, 1200

JS = r"""
(patterns) => {
  const recs = {};
  const leafText = (el) => Array.from(el.childNodes)
    .filter(n => n.nodeType === 3).map(n => n.textContent).join(' ');
  const info = (el) => {
    const cs = getComputedStyle(el), b = el.getBoundingClientRect();
    return { fs: parseFloat(cs.fontSize),
             visible: cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity) > 0.05,
             text: leafText(el).trim().replace(/\s+/g, ' ').slice(0, 44),
             cx: b.x + b.width / 2, cy: b.y + b.height / 2 };
  };
  for (const key of Object.keys(patterns)) {
    const hits = [];
    for (const el of document.querySelectorAll('body *')) {
      const own = leafText(el);
      if (!own) continue;
      if (!patterns[key].some(p => own.includes(p))) continue;
      hits.push(info(el));
    }
    hits.sort((a, b) => b.fs - a.fs);
    recs[key] = hits.slice(0, 3);
  }
  let ring = document.querySelector('[data-region="board"]');
  if (!ring) {
    let biggest = null;
    for (const el of document.querySelectorAll('div,section,table,ul')) {
      const n = el.childElementCount;
      if (n < 36 || n > 48) continue;
      const b = el.getBoundingClientRect();
      if (b.width < 200 || Math.abs(b.width - b.height) / b.width > 0.18) continue;
      if (!biggest || b.width * b.height > biggest.area) biggest = { el, area: b.width * b.height };
    }
    ring = biggest ? biggest.el : null;
  }
  if (ring) {
    const b = ring.getBoundingClientRect();
    const inset = b.width / 11;
    const cx0 = b.x + inset, cy0 = b.y + inset, cx1 = b.x + b.width - inset, cy1 = b.y + b.height - inset;
    let best = null;
    for (const el of document.querySelectorAll('body *')) {
      const own = leafText(el).trim();
      if (!own || own.length > 24) continue;
      const r = info(el);
      if (r.cx < cx0 || r.cx > cx1 || r.cy < cy0 || r.cy > cy1) continue;
      if (!best || r.fs > best.fs) best = r;
    }
    recs.__center_largest = best ? [best] : [];
    recs.__tile_px = [Math.round(b.width / 11 * 10) / 10];
  } else {
    recs.__center_largest = [];
    recs.__tile_px = [null];
  }
  return recs;
}
"""

TARGETS = {
    "чей ход (ХОД)": ["ХОД", "Ход: "],
    "фаза (Начало хода)": ["Начало хода"],
    "сумма броска (8)": ["= 8", "8 =", " 8"],
    "деньги Хост $1215": ["$1215"],
    "деньги Neuro $980": ["$980"],
    "деньги evil $640": ["$640"],
    "деньги Mira $1500": ["$1500"],
    "событие (Crest Square)": ["Crest Square"],
    "событие (+$70)": ["+$70"],
}
FLOOR = 20.0  # px at the 1600x1200 canvas (my instruction to the agents; R-7 scaled)


def main(files):
    bad = 0
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": W, "height": H})
        for f in files:
            page.goto(Path(f).absolute().as_uri(), wait_until="load")
            page.wait_for_timeout(300)
            res = page.evaluate(JS, TARGETS)
            tile = res.pop("__tile_px")[0]
            center = res.pop("__center_largest")
            print(f"=== {Path(f).name}   tile={tile}px")
            for k, hits in res.items():
                if not hits:
                    print(f"  MISSING  {k}")
                    bad += 1
                    continue
                top = hits[0]
                ok = top["visible"] and top["fs"] >= FLOOR
                if not ok:
                    bad += 1
                sizes = ", ".join(f"{h['fs']:g}" for h in hits)
                print(f"  {'ok  ' if ok else 'FAIL'} {k}: max {top['fs']:g}px (all: {sizes}) "
                      f"visible={top['visible']}  \"{top['text']}\"")
            if center:
                c = center[0]
                cok = c["fs"] >= 40
                print(f"  {'ok  ' if cok else 'FAIL'} крупнейший текст в центре кольца: {c['fs']:g}px "
                      f"\"{c['text']}\"")
                if not cok:
                    bad += 1
            else:
                print("  MISSING  крупнейший текст в центре кольца")
                bad += 1
        b.close()
    print(f"\nGLANCE FAILS: {bad} (floor {FLOOR:g}px; центр ≥40px)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
