#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render the prototype's states to PNG (design/renders/) and run the DOM smoke checks.

This is the prototype's probe: it OPENS the built ui-prototype.html in Chromium
(Playwright), asks the page for window.__smoke() (page errors, unresolved i18n keys,
tile/token counts, geometry), and only then takes the screenshot. A render whose
smoke check fails is reported and does not count as a good take.

Usage:
    py -3.12 design/tools/render_prototype.py --list
    py -3.12 design/tools/render_prototype.py --states turn-human,purchase --themes neuro,evil
    py -3.12 design/tools/render_prototype.py --all
"""

import argparse
import json
import pathlib
import sys

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTO = ROOT / "design" / "ui-prototype.html"
OUT = ROOT / "design" / "renders"

# (name, scene, size, extra query params) — sizes: "1440x900" default
STATES = [
    ("cold",            "cold",         None, {}),
    ("turn-human",      "turn-human",   None, {}),
    ("move",            "move",         None, {}),
    ("purchase",        "purchase",     None, {}),
    ("auction",         "auction",      None, {}),
    ("auction-watch",   "auction-watch", None, {}),
    ("trade",           "trade",        None, {}),
    ("trade-in",        "trade-in",     None, {}),
    ("build",           "build",        None, {}),
    ("jail",            "jail",         None, {}),
    ("ai",              "ai",           None, {}),
    ("neuro",           "neuro",        None, {}),
    ("reject",          "reject",       None, {}),
    ("win",             "win",          None, {}),
    ("observer",        "observer",     None, {}),
    ("settings",        "settings",     None, {}),
    ("settings-rules",  "settings",     None, {"tab": "rules"}),
    ("settings-tempo",  "settings",     None, {"tab": "tempo"}),
    ("settings-iface",  "settings",     None, {"tab": "iface"}),
    ("settings-data",   "settings",     None, {"tab": "data"}),
    ("rules",           "rules",        None, {}),
    ("invite",          "invite",       None, {}),
    ("join-connecting", "join",         None, {"join": "connecting"}),
    ("join-failed",     "join",         None, {"join": "failed"}),
    ("join-none",       "join",         None, {"join": "none"}),
    ("admin-quick",     "admin",        None, {}),
    ("admin-edits",     "admin",        None, {"tab": "edits"}),
    ("admin-state",     "admin",        None, {"tab": "state"}),
    ("toasts",          "toasts",       None, {}),
    ("empty",           "empty",        None, {}),
    ("compact",         "turn-human",   "880x600", {}),
]

EXPECT_JOURNAL = {"cold": 0, "empty": 0}


def build_url(path: pathlib.Path, scene: str, size: str, theme: str, extra: dict) -> str:
    params = {"probe": "off", "static": "1", "fit": "0", "anim": "off",
              "scene": scene, "theme": theme, "size": size}
    params.update(extra)
    q = "&".join(f"{k}={v}" for k, v in params.items())
    return path.resolve().as_uri() + "?" + q


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--states", default="")
    ap.add_argument("--themes", default="neuro,evil")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for name, scene, size, extra in STATES:
            print(f"{name:16s} scene={scene:14s} size={size or '1440x900'} {extra or ''}")
        return 0

    want = set(s.strip() for s in args.states.split(",") if s.strip()) if args.states else None
    themes = [t.strip() for t in args.themes.split(",") if t.strip()]
    picks = [s for s in STATES if (args.all or args.states == "" or s[0] in want)]
    if args.states == "" and not args.all:
        picks = [s for s in STATES if s[0] in {"cold", "turn-human", "purchase", "auction", "win", "observer"}]

    OUT.mkdir(parents=True, exist_ok=True)
    failures = []
    table = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for theme in themes:
            (OUT / theme).mkdir(exist_ok=True)
            for name, scene, size, extra in picks:
                size = size or "1440x900"
                w, h = (int(x) for x in size.split("x"))
                page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
                url = build_url(PROTO, scene, size, theme, extra)
                try:
                    page.goto(url, wait_until="load")
                    page.wait_for_function("() => window.__ready === true", timeout=8000)
                    page.wait_for_function("() => !!document.getElementById('smokeOut')", timeout=8000)
                    smoke = json.loads(page.evaluate("window.__smoke()"))
                except Exception as exc:  # noqa: BLE001
                    failures.append(f"{theme}/{name}: page did not become ready: {exc}")
                    page.close()
                    continue
                page.wait_for_timeout(250)
                shot = OUT / theme / f"{name}.png"
                page.screenshot(path=str(shot))
                page.close()

                problems = []
                if smoke["errors"]:
                    problems.append("page errors: " + "; ".join(smoke["errors"][:3]))
                if smoke["unresolved"]:
                    problems.append(f"unresolved i18n keys: {smoke['unresolved']}")
                if smoke["badText"]:
                    problems.append("DOM shows {%…}/undefined/NaN")
                if not smoke["board"][0] or smoke["board"][0] != smoke["board"][1]:
                    problems.append(f"board not square: {smoke['board']}")
                if smoke["tiles"] != 40:
                    problems.append(f"tiles={smoke['tiles']} (want 40)")
                want_rows = EXPECT_JOURNAL.get(name)
                if want_rows is not None and smoke["journalRows"] > want_rows:
                    problems.append(f"journal rows {smoke['journalRows']} (want {want_rows})")
                if not smoke["tokens"] and scene not in ("cold", "empty"):
                    problems.append("no tokens on the board")
                verdict = "OK " if not problems else "BAD"
                if problems:
                    failures.append(f"{theme}/{name}: " + " | ".join(problems))
                table.append(f"  {verdict} {theme}/{name:16s} {size:9s} profile={smoke['profile']:7s} "
                             f"board={smoke['board'][0]}px tiles={smoke['tiles']} tokens={smoke['tokens']:2d} "
                             f"rows={smoke['journalRows']:3d} :: {shot.name}")
        browser.close()

    print("\n".join(table))
    print()
    # pixel sanity: header sample should sit near the theme's surface.1
    from PIL import Image
    skin = {t: json.loads((ROOT / "game/assets/skins" / t / "skin.json").read_text(encoding="utf-8"))
            for t in themes}
    def hex_rgb(s):
        s = s.lstrip("#")
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    for theme in themes:
        col = skin[theme]["tokens"]["color"]
        s1 = hex_rgb(col["surface.1"])
        for shot in sorted((OUT / theme).glob("*.png")):
            im = Image.open(shot).convert("RGB")
            px = im.load()
            sample = px[im.width // 2, 8]  # top bar band
            delta = max(abs(sample[i] - s1[i]) for i in range(3))
            if delta > 24:
                failures.append(f"{theme}/{shot.name}: header pixel {sample} far from surface.1 {s1} (delta {delta})")
            colors = im.convert("RGB").getcolors(maxcolors=1 << 24)
            ncolors = len(colors) if colors else 1 << 24
            if ncolors < 60:
                failures.append(f"{theme}/{shot.name}: only {ncolors} distinct colours — looks blank")
    print(f"renders: {len(picks) * len(themes)}  failures: {len(failures)}")
    for f in failures:
        print("  FAIL " + f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
