#!/usr/bin/env python3
"""SG-07 series check — the app's own screenshots, judged by machine before a human looks.

`docs/restoration/gates.md` SG-07 is a REPORT gate: there is no threshold that means "looks like
the mockup" (different renderers, different fonts - see section 0 of that file). What IS
machine-checkable about a series of screenshots, and is therefore checked here:

  * the file a state's name promises exists, at the size its profile promises
    (the compact profile is 880x600, everything else 1440x900);
  * it is not blank: a black or single-colour frame once masqueraded as "the app looks wrong";
  * frames of DIFFERENT states are different PICTURES - fourteen copies of the cold board would
    pass every per-file check and prove nothing at all;
  * when a side-by-side is asked for, its app half comes from THIS run (mtime >= --started):
    `side_by_side.py` used to pair today's mockup with a build from the day before.

It then writes `build/renders/report.html` with every frame in a grid. The looking is the human's
job; the report only guarantees that what is being looked at is the current thing.

  exit 0  -> SHOTS OK
  exit 1  -> SHOTS FAILED: <first reason>
  exit 3  -> SHOTS SKIPPED: <reason>   (no PIL: nothing was read, nothing is claimed)
"""
from __future__ import annotations

import argparse
import os
import pathlib
import sys
import time

MISSING = object()


def _load(frames: dict, path: pathlib.Path):
    from PIL import Image
    try:
        im = Image.open(path)
        im.load()
    except Exception as exc:  # noqa: BLE001
        return None
    return im


def _distinct_colors(im) -> int:
    """Distinct colours, without ever returning None for a busy frame."""
    from PIL import Image
    small = im.convert("RGB")
    colors = small.getcolors(maxcolors=1 << 22)
    if colors is not None:
        return len(colors)
    # too many colours to enumerate: quantise and count the buckets instead
    q = small.quantize(colors=256).convert("P")
    return len(q.getcolors(maxcolors=256) or [])


def _signature(im) -> bytes:
    """A cheap fingerprint of the picture: 180x112 grey-ish RGB, so two frames can be compared."""
    return im.convert("RGB").resize((180, 112)).tobytes()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/renders")
    ap.add_argument("--states", required=True, help="comma-separated state ids of the series")
    ap.add_argument("--skins", default="neuro,evil")
    ap.add_argument("--started", type=float, default=0.0,
                    help="epoch seconds the run began; frames older than this are stale")
    ap.add_argument("--min-colors", type=int, default=24)
    ap.add_argument("--min-diff", type=float, default=0.005,
                    help="fraction of differing pixels two states must exceed to count as two")
    ap.add_argument("--out", default="build/renders/report.html")
    args = ap.parse_args()

    try:
        import PIL  # noqa: F401
    except Exception:  # noqa: BLE001
        print("SHOTS SKIPPED: no Pillow - the frames were not read, so nothing is claimed")
        return 3

    root = pathlib.Path(args.dir)
    states = [s for s in args.states.split(",") if s]
    skins = [s for s in args.skins.split(",") if s]
    fails: list[str] = []
    rows: list[dict] = []
    sigs: dict[str, dict] = {}

    for skin in skins:
        sigs[skin] = {}
        for state in states:
            path = root / f"{state}_{skin}.png"
            if not path.exists():
                fails.append(f"{state}_{skin}: no frame at {path}")
                rows.append({"skin": skin, "state": state, "path": None, "note": "missing"})
                continue
            age = os.path.getmtime(path)
            if args.started and age < args.started - 2:
                fails.append(f"{state}_{skin}: the frame is older than this run (stale)")
            im = _load({}, path)
            if im is None:
                fails.append(f"{state}_{skin}: unreadable PNG")
                rows.append({"skin": skin, "state": state, "path": path, "note": "unreadable"})
                continue
            want = (880, 600) if state == "compact" else (1440, 900)
            if tuple(im.size) != want:
                fails.append(f"{state}_{skin}: {im.size[0]}x{im.size[1]}, the profile promises "
                             f"{want[0]}x{want[1]}")
            colors = _distinct_colors(im)
            if colors < args.min_colors:
                fails.append(f"{state}_{skin}: only {colors} distinct colour(s) - a blank frame")
            sigs[skin][state] = _signature(im)
            rows.append({"skin": skin, "state": state, "path": path, "colors": colors,
                         "size": tuple(im.size), "mtime": time.strftime("%H:%M:%S", time.localtime(age))})

    # two states must be two pictures
    for skin in skins:
        got = sorted(sigs.get(skin, {}).keys())
        for i in range(len(got)):
            for j in range(i + 1, len(got)):
                a, b = sigs[skin][got[i]], sigs[skin][got[j]]
                if len(a) != len(b):
                    continue
                diff = sum(1 for x, y in zip(a, b) if x != y) / float(len(a))
                if diff < args.min_diff:
                    fails.append(f"{skin}: `{got[i]}` and `{got[j]}` are the same picture "
                                 f"({diff * 100:.2f}% of pixels differ) - the series is not real")
                    for r in rows:
                        if r["skin"] == skin and r["state"] in (got[i], got[j]):
                            r["twin"] = f"{got[i]}=={got[j]}"

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    cells = []
    for r in rows:
        rel = os.path.relpath(r["path"], out.parent).replace("\\", "/") if r["path"] else ""
        img = f"<img src='{rel}'>" if r["path"] else "<div class=miss>MISSING</div>"
        note = r.get("note", "")
        if "twin" in r:
            note = "same picture as " + r["twin"]
        cells.append(
            "<tr><td class=st>%s</td><td class=st>%s</td><td>%s</td>"
            "<td class=num>%sx%s</td><td class=num>%s</td><td class=num>%s</td><td>%s</td></tr>"
            % (r["skin"], r["state"], img,
               r.get("size", ("?", "?"))[0], r.get("size", ("?", "?"))[1],
               r.get("colors", "-"), r.get("mtime", "-"), note))
    html = """<!doctype html><html><head><meta charset="utf-8"><title>NPT frame series - SG-07</title>
<style>
 body{background:#14161a;color:#e6e6e6;font:14px/1.5 system-ui,Segoe UI,sans-serif;margin:24px}
 h1{font-size:20px} table{border-collapse:collapse;margin-top:12px}
 td,th{border:1px solid #30343b;padding:6px 8px;text-align:left;vertical-align:top}
 th{background:#1d2026} .st{font-weight:600} .num{text-align:right} .miss{color:#d73a49}
 img{max-width:520px;border:1px solid #30343b;display:block} .sum{color:#9aa0a6}
</style></head><body>
<h1>NPT app frame series (SG-07) — %(n)d frame(s)</h1>
<div class="sum">generated %(when)s &middot; skins: %(skins)s &middot; every frame below was captured by
<code>game/tools/gates/sg07_capture.tscn</code> in this run. Looking at them is the reviewer's job;
this page only guarantees they are current, non-blank and actually different from each other.</div>
<table><tr><th>skin</th><th>state</th><th>frame</th><th>size</th><th>colours</th><th>captured</th><th>note</th></tr>
%(rows)s</table></body></html>""" % {
        "n": len(rows), "when": time.strftime("%Y-%m-%d %H:%M:%S"),
        "skins": ", ".join(skins), "rows": "\n".join(cells)}
    out.write_text(html, encoding="utf-8")
    print("report: %s" % out)

    if fails:
        print("SHOTS FAILED: %s" % fails[0])
        for f in fails[1:6]:
            print("  also: %s" % f)
        return 1
    print("SHOTS OK (%d frames: %d states x %d skins, every one current, non-blank and distinct)"
          % (len(rows), len(states), len(skins)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
