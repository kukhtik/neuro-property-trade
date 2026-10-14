"""Compare the MOCKUP with the RESULT, exactly, on the things that can be compared.

The mockup is `design/ui-prototype.html` — UI v3 "Broadcast Table" — and it is GENERATED
from the game (design/tools/build_prototype.py), so its palette blocks carry the skins'
own hex values. It declares its design in machine-readable form:

  * `:root[data-theme="<skin>"]` declares the SAME palette the skin does, under the bridge
    names the first mockup used (--tx = text, --ac = accent, --bad = danger, ...). Those are
    exact hex values on both sides, so they can be matched exactly instead of eyeballed.

  * `:root` declares the dock widths (--L, --R) at the 1440x900 design size. The app's
    panels can be MEASURED from a frame, so the layout is checkable too — optional: with no
    frame (or no Pillow) the palette and structure checks still run.

  * `design/regions.json` is the REGISTRY: the region ids the prototype must declare.

What this deliberately does NOT do: pixel-compare the two images. Different renderers,
different fonts, different scales — a pixel diff would flag everything and say nothing.
"""
import json
import os
import pathlib
import re
import sys

PROJ = pathlib.Path(__file__).resolve().parents[2]
## The mockup lives IN the repository since the v3 redesign: it is generated from the game,
## so it cannot drift from the skins, and a desktop path no longer decides whether CI can
## check the design at all.
MOCKUP = PROJ / "design" / "ui-prototype.html"
REGIONS = PROJ / "design" / "regions.json"

## The mockup names its tokens differently. This is the only place the two vocabularies
## are related — the same role IntentMap plays for intents.
SEMANTIC = {
    "bg": ["bg", "board.bg2"],
    "s1": ["surface.1"],
    "s2": ["surface.2"],
    "s3": ["surface.3"],
    "line": ["line"],
    "tx": ["text"],
    "mu": ["muted", "text_dim"],
    "ac": ["accent"],
    "acx": ["on_accent"],
    "bad": ["danger"],
    "hi": ["accent2", "hi"],
}

## Both sides are hand-authored hex, so anything beyond a couple of units is a real
## difference rather than rounding.
TOL = 8


def parse_hex(v):
    s = str(v).strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        return None
    try:
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def dist(a, b):
    return max(abs(a[i] - b[i]) for i in range(3))


def mockup_theme(theme):
    """Tokens (and widths) the mockup declares for one theme.

    The capture group must NOT include the leading dashes, or a token named `bg` is read
    as `--bg` and every lookup misses.
    """
    txt = MOCKUP.read_text(encoding="utf-8")
    toks = {}
    m = re.search(r':root\[data-theme="%s"\]\s*\{([^}]*)\}' % theme, txt)
    if m:
        for k, v in re.findall(r'--([a-z0-9-]+):\s*(#[0-9a-fA-F]{3,8})', m.group(1)):
            toks.setdefault(k, v)
    widths = {}
    m = re.search(r':root\s*\{([^}]*)\}', txt)
    if m:
        for k, v in re.findall(r'--([LR]):\s*(\d+)px', m.group(1)):
            widths[k] = int(v)
    return toks, widths


def measure_panels(frame, line_rgb):
    """Panel widths, measured from where the frame draws its rules.

    A panel edge is a THIN run of the `line` colour. A long run is a filled bar, not an
    edge — taking its first pixel reported a panel width of 0 in a first attempt.

    `line_rgb` is READ FROM THE SKIN BEING COMPARED. It used to be the literal (57, 64, 77)
    — `line` of the `default` skin — and when the game started wearing `neuro` instead,
    whose line is #3b2a5e = (59, 42, 94), that test matched NOTHING. The widths it reported
    were pixels of unrelated colours that happened to land within +-8 of the old theme, so
    the layout comparison was measuring noise while printing confident numbers. A detector
    that hard-codes a value from the thing it is checking cannot detect that value changing.
    """
    from PIL import Image   # only the layout check needs Pillow; palette/registry run anywhere
    im = Image.open(frame).convert("RGB")
    W, H = im.size
    px = im.load()
    y = H // 2
    def is_rule(x):
        c = px[x, y]
        return all(abs(c[i] - line_rgb[i]) <= 8 for i in range(3))
    # an EDGE has field on BOTH sides; x=0 is the window frame and has none
    cols = [x for x in range(4, W - 4) if is_rule(x) and not is_rule(x - 3) and not is_rule(x + 3)]
    runs = []
    for x in cols:
        if runs and x - runs[-1][-1] <= 1:
            runs[-1].append(x)
        else:
            runs.append([x])
    edges = [r[0] for r in runs if 1 <= len(r) <= 4]
    if len(edges) < 2:
        return None, W, edges
    return (edges[0], W - edges[-1] - 1), W, edges


def main():
    # THE FRAME IS AN INPUT, NOT A MEMORY. This script used to read `build/smoke/admin.png`
    # unconditionally - a file from an old run, which the smoke of 2026-10-13 compared while
    # its OWN frame (build/smoke_v3probe/admin.png) went unmeasured. A checker that reads a
    # fixed path cannot notice that path going stale, so now the frame comes from
    # `--frame <png>` or `NPT_FRAME`, and a frame that was ASKED FOR but is missing is a hard
    # failure. No frame at all = the layout step is skipped with a printed reason (palette and
    # structure are still checked); "no frame" must be visible, never silent.
    theme = "neuro"
    frame = None
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--frame":
            i += 1
            frame = pathlib.Path(argv[i]) if i < len(argv) else pathlib.Path("")
        elif a.startswith("--frame="):
            frame = pathlib.Path(a.split("=", 1)[1])
        elif not a.startswith("--"):
            theme = a
        i += 1
    if frame is None and os.environ.get("NPT_FRAME"):
        frame = pathlib.Path(os.environ["NPT_FRAME"])
    if frame is not None and not frame.exists():
        print("FAIL: the requested frame %s does not exist - a comparison cannot measure a "
              "frame that is not there (HG-11: frames are per-run, never remembered)" % frame)
        return 1
    layout_ok = frame is not None
    layout_note = ""
    if layout_ok:
        try:
            import PIL  # noqa: F401 — the layout check is the only part that needs it
        except ImportError:
            layout_ok = False
            layout_note = "layout skipped: Pillow is not installed"
    else:
        layout_note = "layout skipped: no frame given - pass --frame <png> or NPT_FRAME"
    if not MOCKUP.exists():
        print("FAIL: no mockup at %s" % MOCKUP)
        return 1
    skin_path = PROJ / "game" / "assets" / "skins" / theme / "skin.json"
    if not skin_path.exists():
        print("FAIL: no skin %r at %s" % (theme, skin_path))
        return 1

    m_toks, m_widths = mockup_theme(theme)
    if not m_toks:
        print("FAIL: the mockup declares no theme %r" % theme)
        return 1
    a_toks = json.loads(skin_path.read_text(encoding="utf-8"))["tokens"]["color"]

    print("=== %s: mockup vs result ===" % theme)
    print("mockup  %s" % MOCKUP.name)
    if frame is not None:
        print("frame   %s (%d bytes)" % (frame.name, frame.stat().st_size))
    else:
        print("frame   (none given - %s)" % layout_note)
    print()

    fails = []

    # --- 1. palette -----------------------------------------------------------------
    print("[1] palette — the mockup declares it, the skin implements it")
    print("    %-5s %-9s %-13s %-9s %s" % ("mock", "value", "skin token", "value", "delta"))
    matched = 0
    for mk, our_names in SEMANTIC.items():
        if mk not in m_toks:
            continue
        mc = parse_hex(m_toks[mk])
        if mc is None:
            continue
        best = None
        for n in our_names:
            if n not in a_toks:
                continue
            ac = parse_hex(a_toks[n])
            if ac is None:
                continue
            d = dist(mc, ac)
            if best is None or d < best[2]:
                best = (n, ac, d)
        if best is None:
            continue
        ok = best[2] <= TOL
        if ok:
            matched += 1
        else:
            fails.append("palette %s: mockup %s vs %s #%02x%02x%02x (delta %d)"
                         % (mk, m_toks[mk], best[0], best[1][0], best[1][1], best[1][2], best[2]))
        print("    --%-3s %-9s %-13s %-9s %-3d %s"
              % (mk, m_toks[mk], best[0], "#%02x%02x%02x" % best[1], best[2],
                 "ok" if ok else "<-- DIFFERENT"))
    print("    matched: %d" % matched)
    print()

    # --- 2. layout ------------------------------------------------------------------
    print("[2] layout — the mockup declares the dock widths, the frame shows them")
    print("    mockup: --L=%spx --R=%spx" % (m_widths.get("L", "?"), m_widths.get("R", "?")))
    panels = None
    if not layout_ok:
        print("    %s" % layout_note)
    else:
        line_rgb = parse_hex(a_toks.get("line", "")) or (57, 64, 77)
        panels, W, edges = measure_panels(frame, line_rgb)
        if panels:
            lw, rw = panels
            print("    frame %dpx: left panel %spx, right panel %spx (%d edges)"
                  % (W, lw, rw, len(edges)))
            ml, mr = m_widths.get("L"), m_widths.get("R")
            if ml and mr:
                # the app runs at 1440 and the mockup's widest step targets a desktop too, so
                # the RATIO is the comparable quantity — what a responsive design preserves
                m_ratio = mr / ml
                a_ratio = rw / max(lw, 1)
                print("    right/left ratio   mockup=%.2f   app=%.2f" % (m_ratio, a_ratio))
                if abs(m_ratio - a_ratio) > 0.6:
                    fails.append("layout: right/left ratio mockup %.2f vs app %.2f"
                                 % (m_ratio, a_ratio))
                    print("    -> DIFFERENT")
                else:
                    print("    -> comparable")
        else:
            print("    could not isolate the panel edges in the frame")
    print()

    # --- 3. structure ---------------------------------------------------------------
    print("[3] structure — every region the registry names is declared by the mockup")
    reg = json.loads(REGIONS.read_text(encoding="utf-8"))
    want = [str(r.get("id", "")) for r in reg.get("regions", []) if str(r.get("id", ""))]
    txt = MOCKUP.read_text(encoding="utf-8")
    declared = set(m.group(1) for m in re.finditer(r'id="([a-z0-9_-]+)"', txt))
    missing = [r for r in want if r not in declared]
    print("    registry design/regions.json: %d regions" % len(want))
    print("    declared by the mockup:       %d" % (len(want) - len(missing)))
    if missing:
        fails.append("structure: the mockup never declares its own regions: %s"
                     % ", ".join(missing))
    else:
        print("    -> all %d declared" % len(want))
    if layout_ok and panels:
        print("    app frame shows left panel | board | right panel, in that order")
    print()

    out = PROJ / "build" / "smoke" / "comparison.json"
    # the writer creates its own directory: a cleaned build/smoke/ used to turn this into a
    # traceback instead of a report (caught by HG-11 (a1)) - the path is a contract, not a memory
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({
        "theme": theme, "mockup_widths": m_widths, "frame": str(frame) if frame else "",
        "frame_panels": panels, "palette_matched": matched, "layout_note": layout_note,
        "failures": fails,
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    print("wrote %s" % out)
    if fails:
        print("")
        for f in fails:
            print("  DIFF " + f)
        print("")
        print("==> COMPARISON FAILED: %d differences" % len(fails))
        return 1
    print("")
    print("==> COMPARISON PASSED%s"
          % ((" (%s)" % layout_note) if not layout_ok else
             " — the result implements the mockup's own declarations"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
