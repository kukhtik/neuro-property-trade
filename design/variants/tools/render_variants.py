"""Render local HTML mockups to PNG at 1600x1200 (the brief's measured frame) and
report the geometry needed for the R-2 measurement.

Ring detection (in order):
  1. an element carrying data-region="board" (the registry id);
  2. the largest near-square element with 36-48 element children (the 40 tiles).
Center = that box inset by one tile (width/11).

Usage: py -3.12 render_variants2.py <out_dir> <file.html> [<file.html> ...]
"""
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

W, H = 1600, 1200

GEOM_JS = """
() => {
  const r = (el) => { const b = el.getBoundingClientRect();
    return [Math.round(b.x), Math.round(b.y), Math.round(b.width), Math.round(b.height)]; };
  let board = document.querySelector('[data-region="board"]');
  let how = board ? 'data-region' : null;
  if (!board) {
    let best = null;
    for (const el of document.querySelectorAll('div,section,table,ul')) {
      const n = el.childElementCount;
      if (n < 36 || n > 48) continue;
      const b = el.getBoundingClientRect();
      if (b.width < 200) continue;
      if (Math.abs(b.width - b.height) / b.width > 0.18) continue;
      if (!best || b.width * b.height > best.area) { best = { el, area: b.width * b.height }; }
    }
    if (best) { board = best.el; how = 'children=' + best.el.childElementCount; }
  }
  if (!board) return { how: null, ring: null, center: null, regions: {} };
  const ring = r(board);
  const inset = ring[2] / 11;
  const center = [Math.round(ring[0] + inset), Math.round(ring[1] + inset),
                  Math.round(ring[2] - 2 * inset), Math.round(ring[3] - 2 * inset)];
  const regions = {};
  for (const el of document.querySelectorAll('[data-region]')) regions[el.dataset.region] = r(el);
  return { how, ring, center, regions };
}
"""


def main(out_dir, files):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--disable-background-timer-throttling",
                                          "--disable-backgrounding-occluded-windows",
                                          "--disable-renderer-backgrounding"])
        page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
        errors = []
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: errors.append(str(e)))
        for f in files:
            errors.clear()
            page.goto(Path(f).absolute().as_uri(), wait_until="load")
            page.wait_for_timeout(300)
            png = out / (Path(f).stem + ".png")
            page.screenshot(path=str(png), clip={"x": 0, "y": 0, "width": W, "height": H})
            geom = page.evaluate(GEOM_JS)
            print(f"PNG {png}")
            print(f"  console_errors={len(errors)} ring_via={geom['how']} ring={geom['ring']} center={geom['center']}")
            if geom.get("regions"):
                print(f"  regions={geom['regions']}")
            for e in errors[:3]:
                print("  ERR:", e[:160])
        browser.close()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
