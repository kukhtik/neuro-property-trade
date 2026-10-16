#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check the design package against the GAME — the parts that must agree.

What it verifies (all read from the built files, not from declarations again):
  1. ui-prototype.html declares :root[data-theme="<skin>"] for neuro / evil / default,
     and every mapped token equals game/assets/skins/<skin>/skin.json (via the
     extends chain) — the palette in the mockup IS the skin, byte for byte.
  2. Every data-i18n / data-i18n-tip key used by the prototype exists in the merged
     game dictionary (game/i18n/data_*.gd, i18n.gd merge order) or in
     design/src/strings_proposed.json.
  3. Region registry: every id in design/regions.json exists in the prototype, and
     the prototype adds no undeclared data-od-id region.
  4. Board: the prototype's embedded board (window.NPT_DATA.board) equals
     game/data/board.json — same tiles, same order, same costs.
  5. Text roles: every JS template that writes text carries t-value/t-para … this
     one is enforced live by the prototype's own audit (see render_prototype.py
     which reads #auditOut); here we only assert the two role classes exist.

Exit 0 = the package agrees with the game on all of the above.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design"
GAME = ROOT / "game"
SKIN_ORDER = ["neuro", "evil", "default"]
VAR_MAP = {
    "bg": "--bg", "surface.1": "--s1", "surface.2": "--s2", "surface.3": "--s3",
    "line": "--line", "text": "--tx", "muted": "--mu", "accent": "--ac",
    "on_accent": "--acx", "accent2": "--hi", "money": "--money", "danger": "--bad",
    "warn": "--warn", "ink": "--ink", "ring_bg": "--ring-bg",
}


def fail(msg, fails):
    fails.append(msg)
    print("  FAIL " + msg)


def main() -> int:
    fails = []
    html = (DESIGN / "ui-prototype.html").read_text(encoding="utf-8")
    # Static-markup view: dynamic keys built inside JS templates are NOT counted here —
    # they are verified live by render_prototype.py (unresolved-keys count + the {%…%}
    # text scan across every state).
    html_static = re.sub(r"<!--.*?-->", "", html, flags=re.S)
    html_static = re.sub(r"<script\b[^>]*>.*?</script>", "", html_static, flags=re.S)
    decl = json.loads((DESIGN / "src" / "declarations.json").read_text(encoding="utf-8"))
    proposed = json.loads((DESIGN / "src" / "strings_proposed.json").read_text(encoding="utf-8"))
    proposed = {k: v for k, v in proposed.items() if not k.startswith("_")}

    # 1. palettes -------------------------------------------------------------
    print("[1] palette: mockup :root[data-theme] vs game skins")
    for sid in SKIN_ORDER:
        block = re.search(r':root\[data-theme="%s"\]\s*\{([^}]*)\}' % sid, html)
        if not block:
            fail(f"no :root[data-theme=\"{sid}\"] block", fails)
            continue
        css = dict(re.findall(r"(--[a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{3,8})", block.group(1)))
        # resolve skin with extends
        chain = []
        cur = sid
        while cur:
            chain.append(cur)
            cur = json.loads((GAME / "assets" / "skins" / cur / "skin.json").read_text(encoding="utf-8")).get("extends")
        col = {}
        for c in reversed(chain):
            col.update(json.loads((GAME / "assets" / "skins" / c / "skin.json").read_text(encoding="utf-8"))
                       .get("tokens", {}).get("color", {}))
        checked = 0
        for token, var in VAR_MAP.items():
            if token not in col:
                continue
            got = css.get(var)
            want = col[token]
            checked += 1
            if not got or got.lower() != str(want).lower():
                fail(f"{sid}: {var} mockup={got} skin={want}", fails)
        # extension tokens must be present with hex values
        for ext_tok in ("--scrim", "--glow", "--good", "--ring-bg"):
            if ext_tok not in css:
                fail(f"{sid}: token {ext_tok} missing", fails)
        # player colours p0..p5 straight from the skin
        players = col.get("player") or []
        for i, want in enumerate(players):
            got = css.get(f"--p{i}")
            if got is None or got.lower() != str(want).lower():
                fail(f"{sid}: --p{i} mockup={got} skin={want}", fails)
        print(f"    {sid}: {checked} mapped tokens + {len(players)} player colours checked")

    # 1b. SIZES ------------------------------------------------------------------
    # WHY THIS EXISTS: the check above compares COLOURS only, so the mockup's `--fs-*` scale (the
    # type ramp the whole prototype is laid out with) could drift from the game's `tokens.size`
    # with nothing to notice - the prototype would keep drawing 13px body text while the game
    # rendered 14. A harness that hardcodes a value from the thing it inspects cannot report that
    # value changing; these five numbers are read from BOTH sides and compared.
    print("[1b] sizes: mockup --fs-* vs game skins' tokens.size")
    fs_block = re.search(r":root\s*\{([^}]*)\}", html)
    if not fs_block:
        fail("no :root { } block to read the --fs-* scale from", fails)
    else:
        sizes_css = dict(re.findall(r"(--fs-[a-z0-9]+)\s*:\s*(\d+)px", fs_block.group(1)))
        # the sizes are declared once at :root (they are not per-theme), so compare against the
        # skins that declare them; a skin that inherits must resolve to the same numbers.
        for sid in SKIN_ORDER:
            chain = []
            cur = sid
            while cur:
                chain.append(cur)
                cur = json.loads((GAME / "assets" / "skins" / cur / "skin.json").read_text(encoding="utf-8")).get("extends")
            sz = {}
            for c in reversed(chain):
                sz.update(json.loads((GAME / "assets" / "skins" / c / "skin.json").read_text(encoding="utf-8"))
                          .get("tokens", {}).get("size", {}))
            n = 0
            for token, var in (("xs", "--fs-xs"), ("s", "--fs-s"), ("m", "--fs-m"), ("l", "--fs-l"), ("xl", "--fs-xl")):
                if token not in sz:
                    continue
                got = sizes_css.get(var)
                want = str(sz[token])
                n += 1
                if got != want:
                    fail(f"{sid}: {var} mockup={got}px skin={want}px", fails)
            print(f"    {sid}: {n} size tokens checked")

    # 2. i18n -----------------------------------------------------------------
    print("[2] i18n: every static key used by the prototype resolves")
    used = set(re.findall(r'data-i18n(?:-tip)?="([^"]+)"', html_static))
    # keys that only ever appear inside strings built by JS (renderers pass them to t())
    keys_in_html = used
    dict_path = DESIGN / "i18n.json"
    game_dict = json.loads(dict_path.read_text(encoding="utf-8"))
    missing = sorted(k for k in keys_in_html if k not in game_dict and k not in proposed)
    if missing:
        fail(f"{len(missing)} keys unresolved: {missing[:8]}", fails)
    print(f"    {len(keys_in_html)} static keys checked against {len(game_dict)} game keys + {len(proposed)} proposed")

    # 3. regions --------------------------------------------------------------
    print("[3] regions: registry vs prototype")
    reg = json.loads((DESIGN / "regions.json").read_text(encoding="utf-8"))
    ids_decl = {r["id"] for r in reg["regions"]}
    ids_html = set(re.findall(r'data-od-id="([a-z-]+)"', html))
    if ids_decl - ids_html:
        fail(f"declared regions missing in HTML: {sorted(ids_decl - ids_html)}", fails)
    if ids_html - ids_decl:
        fail(f"HTML regions not in registry: {sorted(ids_html - ids_decl)}", fails)
    print(f"    {len(ids_decl)} regions declared and present")

    # 4. board ----------------------------------------------------------------
    print("[4] board data: prototype NPT_DATA vs game/data/board.json")
    m = re.search(r"window\.NPT_DATA = (\{.*?\});\n", html, re.DOTALL)
    if not m:
        fail("NPT_DATA not found in prototype", fails)
    else:
        data = json.loads(m.group(1))
        game_board = json.loads((GAME / "data" / "board.json").read_text(encoding="utf-8"))
        if data["board"] != game_board:
            fail("embedded board differs from game/data/board.json", fails)
        else:
            print(f"    board equal: {len(game_board['tiles'])} tiles")

    # 5. text roles -----------------------------------------------------------
    print("[5] text roles: both role classes exist; audit hook present")
    for cls in ("t-value", "t-para"):
        if f'"{cls}"' not in html and f".{cls}" not in html:
            fail(f"role class {cls} unused in prototype", fails)
    if "data-grow" not in html:
        fail("no data-grow markers found", fails)
    print("    roles + grow markers present (live counts come from render_prototype.py)")

    # 6. coverage completeness -------------------------------------------------
    print("[6] coverage.md mentions every F-01..F-73 and P-1..P-16")
    cov = (DESIGN / "coverage.md").read_text(encoding="utf-8")
    missing_f = [f"F-{i:02d}" for i in range(1, 74) if f"F-{i:02d}" not in cov]
    missing_p = [f"P-{i}" for i in range(1, 17) if f"**P-{i}**" not in cov]
    if missing_f:
        fail(f"coverage.md missing F-ids: {missing_f}", fails)
    if missing_p:
        fail(f"coverage.md missing P-ids: {missing_p}", fails)
    print(f"    F-ids present: {73 - len(missing_f)}/73   P-ids present: {16 - len(missing_p)}/16")

    print()
    if fails:
        print(f"==> PACKAGE CHECK: {len(fails)} failures")
        return 1
    print("==> PACKAGE CHECK PASSED — the prototype agrees with the game on palette, i18n, regions, board")
    return 0


if __name__ == "__main__":
    sys.exit(main())
