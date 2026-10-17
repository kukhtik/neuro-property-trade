"""Measure a 1600x1200 UI frame against the brief's R-1 / R-2 definitions.

R-1: frame -> grid 40x30; a cell is EMPTY when it holds < 2% non-background pixels.
     Threshold: empty cells must be <= 25%.
R-2: inside the board ring at least 70% of the area must be occupied.
     The ring is located by the board tile colours (#101820 / #22303c); the interior is
     that bounding box inset by 1/11 (a 40-tile ring is 11x11 tiles).

Usage: py -3.12 measure_fill.py [--bg #rrggbb] <frame.png> [<frame.png> ...]
  --bg  reference frame background (default: most common colour of the 4 corners).
        Pass the skin's bg token (#0b0613 for neuro) when a panel covers a corner.
"""
import json
import sys
from collections import Counter

from PIL import Image

GRID_X, GRID_Y = 40, 30
EMPTY_CELL_UNDER = 0.02  # < 2% non-background pixels == empty cell
TILE_BG = {(16, 24, 32), (34, 48, 60)}  # board.bg2 / board.bg3 of the neuro skin
TOL = 6


def close(px, ref, tol=TOL):
    return abs(px[0] - ref[0]) <= tol and abs(px[1] - ref[1]) <= tol and abs(px[2] - ref[2]) <= tol


def hex_to_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def main(argv):
    forced = None
    paths = []
    it = iter(argv)
    for a in it:
        if a == "--bg":
            forced = hex_to_rgb(next(it))
        elif a.startswith("--bg="):
            forced = hex_to_rgb(a.split("=", 1)[1])
        else:
            paths.append(a)
    out = []
    for path in paths:
        img = Image.open(path).convert("RGB")
        w, h = img.size
        px = img.load()
        # frame background = the most common colour among the four corners, unless forced
        corners = [px[1, 1], px[w - 2, 1], px[1, h - 2], px[w - 2, h - 2]]
        bg = forced or Counter(corners).most_common(1)[0][0]


        cw, ch = w / GRID_X, h / GRID_Y
        empty = 0
        cells = 0
        for gy in range(GRID_Y):
            for gx in range(GRID_X):
                x0, y0 = int(gx * cw), int(gy * ch)
                x1, y1 = min(w, int((gx + 1) * cw)), min(h, int((gy + 1) * ch))
                step = max(1, (x1 - x0) // 8)
                total = nonbg = 0
                for y in range(y0, y1, step):
                    for x in range(x0, x1, step):
                        total += 1
                        if not close(px[x, y], bg):
                            nonbg += 1
                cells += 1
                if total and nonbg / total < EMPTY_CELL_UNDER:
                    empty += 1

        # board ring bounding box, from the tile colours
        xmin, ymin, xmax, ymax = w, h, -1, -1
        tile_px = 0
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                c = px[x, y]
                if any(close(c, t, 2) for t in TILE_BG):
                    tile_px += 1
                    if x < xmin:
                        xmin = x
                    if y < ymin:
                        ymin = y
                    if x > xmax:
                        xmax = x
                    if y > ymax:
                        ymax = y

        rec = {
            "file": path,
            "size": [w, h],
            "bg": "#%02x%02x%02x" % bg,
            "empty_cells_pct": round(100.0 * empty / cells, 1),
            "R1_ok": (empty / cells) <= 0.25,
        }
        if xmax > xmin and ymax > ymin:
            inset_x = (xmax - xmin + 1) / 11.0
            inset_y = (ymax - ymin + 1) / 11.0
            cx0, cy0 = int(xmin + inset_x), int(ymin + inset_y)
            cx1, cy1 = int(xmax - inset_x), int(ymax - inset_y)
            tot = occ = 0
            for y in range(cy0, cy1, 3):
                for x in range(cx0, cx1, 3):
                    tot += 1
                    if not close(px[x, y], bg):
                        occ += 1
            rec.update({
                "board_bbox": [xmin, ymin, xmax, ymax],
                "tile_px_sampled": tile_px,
                "center_px": [cx0, cy0, cx1, cy1],
                "center_occupied_pct": round(100.0 * occ / max(1, tot), 1),
                "R2_ok": (occ / max(1, tot)) >= 0.70,
            })
        else:
            rec["center_occupied_pct"] = None
            rec["R2_ok"] = None
        out.append(rec)
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
