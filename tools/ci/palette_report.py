#!/usr/bin/env python3
"""SG-03 — «палитра кадра ⊆ токены скина» (docs/restoration/gates.md).

Every significant colour in a REAL rendered frame must be within Δ<=8 of a skin token, or be
explained in the allowlist (antialiasing, shadows, art). Stage 1 is a REPORT: unexplained
colours are counted and written out, the gate stays green. `--calibrate` moves the current
unexplained colours into the allowlist file (owner reviews the diff); after that, `--strict`
turns NEW unexplained colours into a red.

Usage:
  palette_report.py --frame build/gates/SG-03-frame-neuro.png --skin game/assets/skins/neuro/skin.json
      [--allowlist tools/ci/palette_allowlist.txt] [--calibrate] [--strict]
      [--report build/gates/SG-03-neuro]

Verdict lines (read by the shell gate):
  ==> SG-03 REPORT <skin>: <U> unexplained (>=<N>px), <A> allowlisted, <T> tokens
  ==> SG-03 FAILED <skin>: <reason>        (blank/unreadable frame, or strict with new colours)
"""
import argparse
import json
import pathlib
import re
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - CI without Pillow
    print("==> SG-03 REPORT PIL-MISSING: Pillow is not installed, palette analysis skipped")
    sys.exit(0)

DELTA = 8          # Chebyshev distance to a token that still counts as "the token"
MIN_PIXELS = 120   # a colour patch smaller than this is noise (AA, subpixel text), not a region
BLANK_UNIQUE = 60  # fewer unique colours than this in a 1440x900 frame = something is wrong


def parse_hex(s: str):
    s = s.strip().lstrip("#")
    if len(s) < 6:
        return None
    try:
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    except ValueError:
        return None


def load_via_json(path: pathlib.Path, seen=None):
    """tokens.color.* -> list of rgb tuples; follows `extends` (neuro extends default)."""
    seen = seen or set()
    data = json.loads(path.read_text(encoding="utf-8"))
    out = []
    parent = data.get("extends")
    if parent and parent not in seen:
        seen.add(parent)
        pp = path.parent.parent / parent / "skin.json"
        if pp.exists():
            out += load_via_json(pp, seen)
    tok = data.get("tokens", {}).get("color", {})

    def walk(v):
        if isinstance(v, str):
            c = parse_hex(v)
            if c:
                out.append(c)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, dict):
            # token groups nest (`color.group.red`, `color.player[]`) - the first version only
            # walked one level and reported nested tokens as "unexplained"
            for x in v.values():
                walk(x)

    for v in tok.values():
        walk(v)
    return out


def load_allowlist(path: pathlib.Path):
    out = []
    if path and path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            # a hex colour on these lines IS `#`-prefixed, so "cut at the first #" would eat
            # the colour itself and silently parse an EMPTY allowlist - take the hex token.
            m = re.search(r"#([0-9a-fA-F]{6})", line)
            if m:
                c = parse_hex(m.group(0))
                if c:
                    out.append(c)
    return out


def dist(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frame", required=True)
    ap.add_argument("--skin", required=True)
    ap.add_argument("--allowlist", default="tools/ci/palette_allowlist.txt")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--report", default="")
    args = ap.parse_args()

    frame = pathlib.Path(args.frame)
    skin_path = pathlib.Path(args.skin)
    skin = skin_path.parent.name
    if not frame.exists():
        print("==> SG-03 FAILED %s: no frame at %s" % (skin, frame))
        return 1
    img = Image.open(frame).convert("RGB")
    colors = img.getcolors(maxcolors=1 << 22) or []
    colors.sort(reverse=True)
    if len(colors) < BLANK_UNIQUE:
        print("==> SG-03 FAILED %s: frame looks blank (%d unique colours at %dx%d)"
              % (skin, len(colors), img.width, img.height))
        return 1
    if colors and colors[0][0] > img.width * img.height * 0.97:
        print("==> SG-03 FAILED %s: one colour covers >97%% of the frame" % skin)
        return 1

    tokens = load_via_json(skin_path)
    allow_path = pathlib.Path(args.allowlist)
    allow = load_allowlist(allow_path)

    unexplained = []   # (pixels, rgb)
    allowed = []
    for count, rgb in colors:
        if count < MIN_PIXELS:
            continue
        if any(dist(rgb, t) <= DELTA for t in tokens):
            continue
        hit = next((a for a in allow if dist(rgb, a) <= DELTA), None)
        if hit is not None:
            allowed.append((count, rgb))
        else:
            unexplained.append((count, rgb))
    unexplained.sort(reverse=True)

    report_base = pathlib.Path(args.report) if args.report else None
    if report_base:
        report_base.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "skin": skin, "frame": str(frame), "tokens": len(tokens),
            "unexplained": [{"px": c, "rgb": "#%02x%02x%02x" % r} for c, r in unexplained],
            "allowlisted": [{"px": c, "rgb": "#%02x%02x%02x" % r} for c, r in allowed],
        }
        report_base.with_suffix(".json").write_text(json.dumps(payload, indent=1), encoding="utf-8")

    if args.calibrate and unexplained:
        lines = allow_path.read_text(encoding="utf-8").splitlines() if allow_path.exists() else [
            "# SG-03 palette allowlist - colours that are explained (antialiasing, shadows, art)",
            "# and therefore allowed beyond the skin tokens. One hex per line; `#` starts a comment.",
            "",
        ]
        existing = {a for a in allow} | {t for t in tokens}
        fresh = [(c, r) for c, r in unexplained if not any(dist(r, e) <= DELTA for e in existing)]
        for c, r in fresh:
            lines.append("#%02x%02x%02x   # %d px, auto-calibrated %s" % (r[0], r[1], r[2], c, frame.name))
        allow_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("SG-03 calibrated: %d colour(s) appended to %s" % (len(fresh), allow_path))

    u = len(unexplained)
    print("==> SG-03 REPORT %s: %d unexplained (>=%dpx), %d allowlisted, %d tokens"
          % (skin, u, MIN_PIXELS, len(allowed), len(tokens)))
    for c, r in unexplained[:8]:
        print("    unexplained: #%02x%02x%02x  %d px" % (r[0], r[1], r[2], c))
    if args.strict and u > 0:
        print("==> SG-03 FAILED %s: strict mode - %d unexplained colour(s) beyond tokens+allowlist" % (skin, u))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
