#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble design/ui-prototype.html from the parts in design/src/.

What is hand-authored (design work):
    src/proto.css   the design system: tokens usage, layout, components
    src/proto.html  the body: regions, overlays, modals (JS fills the rest)
    src/proto.js    logic: i18n, board render, scenes, demo engine, self-audit

What is GENERATED here (never hand-typed):
    the per-theme palette blocks   <- game/assets/skins/*/skin.json + extends
    the SVG sprite                 <- game/assets/{tokens,type_icons,dice,houses,corner_icons}
    data.js / i18n.json            <- design/tools/build_data.py (separate step)
    NPT_PROPOSED                   <- src/strings_proposed.json
    the declarations block         <- src/declarations.json (also written to design/regions.json)

Run:  python design/tools/build_data.py && python design/tools/build_prototype.py
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design"
SRC = DESIGN / "src"
GAME = ROOT / "game"

SKIN_ORDER = ["neuro", "evil", "default", "classic"]
SKIN_DIR = GAME / "assets" / "skins"
ASSET_DIRS = {
    "tokens": GAME / "assets" / "tokens",
    "type_icons": GAME / "assets" / "type_icons",
    "corner_icons": GAME / "assets" / "corner_icons",
    "dice": GAME / "assets" / "dice",
    "houses": GAME / "assets" / "houses",
}

VAR_MAP = {
    "bg": "--bg", "surface.1": "--s1", "surface.2": "--s2", "surface.3": "--s3",
    "line": "--line", "text": "--tx", "muted": "--mu", "accent": "--ac",
    "on_accent": "--acx", "accent2": "--hi", "money": "--money", "danger": "--bad",
    "warn": "--warn", "ink": "--ink", "ring_bg": "--ring-bg",
    "dice_bg": "--dice-bg", "dice_ink": "--dice-ink",
    "board.bg2": "--board-bg2", "board.bg3": "--board-bg3",
}


def load_skin(sid: str) -> dict:
    return json.loads((SKIN_DIR / sid / "skin.json").read_text(encoding="utf-8"))


_cache: dict = {}


def resolved_colors(sid: str) -> dict:
    """Skin colours with the extends chain applied (evil -> neuro -> default)."""
    if sid in _cache:
        return _cache[sid]
    data = load_skin(sid)
    col = dict(data.get("tokens", {}).get("color", {}))
    base = dict(resolved_colors(data["extends"])) if data.get("extends") else {}
    merged = base
    merged.update(col)
    _cache[sid] = merged
    return merged


def theme_block(sid: str, decl: dict) -> str:
    col = resolved_colors(sid)
    ext = decl["theme_extensions"]
    pairs = []
    for token, var in VAR_MAP.items():
        if token in col:
            pairs.append(f"{var}:{col[token]}")
    groups = col.get("group") or ext.get("group_fallback", {}).get(sid) or {}
    for g, v in groups.items():
        pairs.append(f"--g-{g}:{v}")
    players = list(col.get("player") or [])
    players += ext.get("player_extra", {}).get(sid, [])
    for i, v in enumerate(players):
        pairs.append(f"--p{i}:{v}")
    for name, per in ext.items():
        if name in ("note", "player_extra", "group_fallback") or not isinstance(per, dict):
            continue
        v = per.get(sid)
        if isinstance(v, str):
            pairs.append(f"--{name.replace('_', '-')}:{v}")
    return ':root[data-theme="%s"]{%s}' % (sid, ";".join(pairs))


def svg_symbol(stem: str, path: pathlib.Path) -> str:
    txt = path.read_text(encoding="utf-8")
    m = re.search(r'viewBox="([^"]+)"', txt)
    if not m:
        raise SystemExit(f"no viewBox in {path}")
    body = txt[txt.index(">") + 1: txt.rindex("</svg>")]
    prefix = f"as-{stem}-"
    body = re.sub(r'id="([A-Za-z][\w-]*)"', lambda mm: f'id="{prefix}{mm.group(1)}"', body)
    body = re.sub(r"url\(#([\w-]+)\)", lambda mm: f"url(#{prefix}{mm.group(1)})", body)
    body = re.sub(r"\s+", " ", body).strip()
    return f'<symbol id="as-{stem}" viewBox="{m.group(1)}">{body}</symbol>'


def build_sprite() -> str:
    syms = []
    for name, folder in ASSET_DIRS.items():
        for svg in sorted(folder.glob("*.svg")):
            stem = svg.stem  # top_hat, die_3, house, ...
            syms.append(svg_symbol(stem, svg))
    return '<svg width="0" height="0" style="position:absolute" aria-hidden="true">' + "".join(syms) + "</svg>"


def main() -> int:
    decl = json.loads((SRC / "declarations.json").read_text(encoding="utf-8"))
    proposed = json.loads((SRC / "strings_proposed.json").read_text(encoding="utf-8"))
    proposed = {k: v for k, v in proposed.items() if not k.startswith("_")}
    proto_css = (SRC / "proto.css").read_text(encoding="utf-8")
    proto_html = (SRC / "proto.html").read_text(encoding="utf-8")
    proto_js = (SRC / "proto.js").read_text(encoding="utf-8")
    data_js = (SRC / "data.js").read_text(encoding="utf-8")

    theme_css = "\n".join(theme_block(sid, decl) for sid in SKIN_ORDER)
    if "/*__THEME_BLOCKS__*/" not in proto_css:
        raise SystemExit("proto.css lost its /*__THEME_BLOCKS__*/ marker")
    css = proto_css.replace("/*__THEME_BLOCKS__*/", theme_css)

    sprite = build_sprite()

    decl_json = json.dumps(decl, ensure_ascii=False, separators=(",", ":"))
    decl_json = decl_json.replace("</", "<\\/")  # never let JSON close the script tag
    proposed_json = json.dumps(proposed, ensure_ascii=False, separators=(",", ":"))

    out = f"""<!doctype html>
<!-- =====================================================================
     NEURO PROPERTY TRADE — UI v3 prototype “Broadcast Table”
     Built by design/tools/build_prototype.py — edit design/src/*, not this file.
     Standalone: opens offline as a file:// page, no network, no build step.
     Machine-readable surfaces:
       · :root[data-theme="<skin>"]  palettes (hex) generated from game skins
       · [design-decl script block]   regions / breakpoints / text roles / widths
       · window.NPT_DATA             board + i18n + skins, straight from game files
       · window.NPT_PROPOSED         new strings the design needs (see coverage.md)
     ===================================================================== -->
<html lang="ru" data-theme="neuro">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="design/tools/build_prototype.py">
<title>Neuro Property Trade — UI v3 · прототип (фоновый стол)</title>
<style>
{css}
</style>
</head>
<body>
{sprite}
{proto_html}
<script id="design-decl" type="application/json">{decl_json}</script>
<script>
{data_js}</script>
<script>window.NPT_PROPOSED = {proposed_json};</script>
<script>
{proto_js}</script>
</body>
</html>
"""
    target = DESIGN / "ui-prototype.html"
    target.write_text(out, encoding="utf-8")

    (DESIGN / "regions.json").write_text(
        json.dumps({"regions": decl["regions"], "legacy_region_alias": decl["legacy_region_alias"]},
                   ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8",
    )

    n_sym = out.count("<symbol id=")
    print(f"themes: {len(SKIN_ORDER)}  symbols: {n_sym}  proposed strings: {len(proposed)}")
    print(f"wrote {target} ({target.stat().st_size} bytes)")
    print(f"wrote {DESIGN / 'regions.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
