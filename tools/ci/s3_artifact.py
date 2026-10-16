"""S3, half A: measure the RELEASE BUILD in a real browser (docs/program.md P1.1).

WHY IT EXISTS: every check in this repo ran against the source tree. The promise S3
("the stream picture can be read") is about the thing that gets shipped, and the
interface has twice been tested against a build older than the code. So this driver
opens the artifact exported by the SAME run, at the two sizes the promise names
(1280x720 desktop, 390x844 phone), and answers only what a browser can answer honestly:

  * does it boot and draw a board at all (frames that are not blank),
  * does the canvas fill the viewport (no letterboxing, no scrollbars),
  * does the page stay error-free,
  * what colours are on the frame (palette is then checked against the skin tokens
    by tools/ci/palette_report.py - one implementation, not two).

What it CANNOT answer - and says so instead of guessing - is text legibility and
"is anything outside the window": that needs the live tree, which lives in the
packed build and is measured by the native half of tools/ci/scenario_s3.sh
(phone_fit_probe + the READ gate). Two halves, one verdict, no invented number.

Usage:
    py -3.12 tools/ci/s3_artifact.py --web build/s3/web --out build/s3 \
        --sizes 1280x720,390x844 --url-extra "seat=abc&host=ws://127.0.0.1:19100"
"""

import argparse
import http.server
import pathlib
import socketserver
import sys
import threading
import time

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
SKIP = ("--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
        "--no-sandbox")


class Handler(http.server.SimpleHTTPRequestHandler):
    """COOP/COEP: the Godot wasm runtime refuses to start without cross-origin isolation."""

    def __init__(self, *a, directory=None, **kw):
        super().__init__(*a, directory=str(directory), **kw)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *a):
        pass


def serve(directory: pathlib.Path, port: int):
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", port), lambda *a, **k: Handler(*a, directory=directory, **k))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def load_tokens(skin_json):
    import json
    data = json.loads(pathlib.Path(skin_json).read_text(encoding="utf-8"))

    def walk(d, out):
        for k, v in d.items():
            if isinstance(v, dict):
                walk(v, out)
            elif isinstance(v, str) and v.startswith("#") and len(v) == 7:
                out[k] = tuple(int(v[i:i + 2], 16) for i in (1, 3, 5))
        return out

    return list(walk(data.get("tokens", {}), {}).values())


def palette_coverage(png: pathlib.Path, tokens, allow, delta=8):
    """Share of the frame that wears the skin's own colours.

    NOT a per-cluster strict check: a live frame is not a still. Translucent plates blend the
    board through themselves (that is a design decision, not a foreign colour), so cluster
    counts on a live frame float between 2 and 12 and their sizes between 124px and 6.5k px.
    Coverage is stable under all of that and still collapses the moment the UI wears another
    skin - which is the defect this check exists for (the game once painted `default` while the
    comparison read `neuro`).
    """
    from PIL import Image
    im = Image.open(png).convert("RGB")
    px = im.load()
    w, h = im.size
    inside = 0
    step = 2 if w * h > 400_000 else 1     # a 1280x720 frame does not need every pixel
    total = 0
    for y in range(0, h, step):
        for x in range(0, w, step):
            c = px[x, y]
            total += 1
            if any(max(abs(c[i] - t[i]) for i in range(3)) <= delta for t in tokens) \
                    or c in allow:
                inside += 1
    return inside / float(total or 1)


def frame_stats(png: pathlib.Path) -> dict:
    from PIL import Image
    im = Image.open(png).convert("RGB")
    got = im.getcolors(maxcolors=1 << 24)
    n = len(got) if got else 1 << 24
    top = (max(got)[0] / float(im.width * im.height)) if got else 1.0
    return {"colours": n, "top_share": top}


def wait_ready(page, msgs, boot_s: int) -> bool:
    """The app says so itself: the browser prints JOINED when the host accepts its seat.

    Colour counting alone accepted the BOOT SCREEN (the Godot loading splash is flat but has
    plenty of colours) - the first runs measured that, not the game. Wait for the app's own
    line; if it never comes, say so instead of photographing a splash screen.
    """
    deadline = time.time() + boot_s
    while time.time() < deadline:
        if any("JOINED pid=" in m for m in msgs):
            page.wait_for_timeout(2000)          # let the first state render
            return True
        page.wait_for_timeout(500)
    return False


def measure(page, out: pathlib.Path, label: str, w: int, h: int) -> dict:
    """Report the geometry facts of whatever is on screen right now."""
    shot = out / f"{label}.png"
    page.screenshot(path=str(shot))
    canvas = page.evaluate("""() => {
        const c = document.querySelector('canvas');
        if (!c) return null;
        const r = c.getBoundingClientRect();
        return {x: r.x, y: r.y, w: r.width, h: r.height,
                bw: c.width, bh: c.height};
    }""")
    doc = page.evaluate("""() => ({
        sw: document.documentElement.scrollWidth,
        sh: document.documentElement.scrollHeight,
        iw: window.innerWidth, ih: window.innerHeight})""")
    st = frame_stats(shot)
    return {"label": label, "want": (w, h), "canvas": canvas, "doc": doc,
            "colours": st["colours"], "top_share": st["top_share"], "shot": str(shot)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--web", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sizes", default="1280x720,390x844")
    ap.add_argument("--url-extra", default="")
    ap.add_argument("--port", type=int, default=8783)
    ap.add_argument("--boot", type=int, default=30, help="seconds to wait for a drawn frame")
    ap.add_argument("--ignore-console", default="NEURO_SDK_WS_URL environment variable is not set",
                    help="console-error allowlist (one substring, ';'-separated). "
                         "Current entry, with its reason: the vendored SDK addon prints this as an "
                         "ERROR at boot whenever no SDK seat is configured, which is every normal "
                         "run - it is noise from third-party code, not a page fault. Any OTHER "
                         "error still fails the half.")
    ap.add_argument("--skin", default="game/assets/skins/neuro/skin.json")
    ap.add_argument("--allowlist", default="tools/ci/palette_allowlist_browser.txt")
    ap.add_argument("--coverage-floor", type=float, default=0.90,
                    help="share of frame pixels that must sit within delta<=8 of a skin token. "
                         "0.90 is calibrated on live frames of the shipping build, whose "
                         "translucent plates blend the board through themselves; a UI wearing "
                         "ANOTHER skin (the defect this guards) drops far below it.")
    args = ap.parse_args()

    web = (ROOT / args.web).resolve() if not pathlib.Path(args.web).is_absolute() else pathlib.Path(args.web)
    out = (ROOT / args.out).resolve() if not pathlib.Path(args.out).is_absolute() else pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if not (web / "index.html").exists():
        print(f"FAIL: no web export at {web}")
        return 2
    for stale in sorted(out.glob("*.png")):
        stale.unlink()                   # a frame from a previous run is not evidence

    serve(web, args.port)
    time.sleep(0.7)
    tokens = load_tokens(ROOT / args.skin if not pathlib.Path(args.skin).is_absolute() else args.skin)
    allow_path = ROOT / args.allowlist if not pathlib.Path(args.allowlist).is_absolute() else pathlib.Path(args.allowlist)
    allow = set()
    for line in allow_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#") and len(line) >= 7:
            import re as _re
            m = _re.match(r"#([0-9a-fA-F]{6})", line[1:])
            if m:
                allow.add(tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4)))
    if not tokens:
        print("FAIL: no colour tokens read from the skin - the palette check would be blind")
        return 2
    sizes = [s.strip() for s in args.sizes.split(",") if s.strip()]
    extra = ("&" + args.url_extra) if args.url_extra else ""
    failures, rows = [], []

    with sync_playwright() as p:
        browser = p.chromium.launch(args=list(SKIP))
        for spec in sizes:
            w, h = (int(x) for x in spec.split("x"))
            label = f"frame_{w}x{h}"
            page = browser.new_page(viewport={"width": w, "height": h})
            errors, msgs = [], []

            def on_console(m, errors=errors, msgs=msgs):
                msgs.append(m.text)
                if m.type == "error":
                    errors.append(m.text)

            page.on("console", on_console)
            page.on("pageerror", lambda e: errors.append("pageerror: %s" % e))
            url = f"http://127.0.0.1:{args.port}/index.html?{extra.lstrip('&')}" if extra \
                else f"http://127.0.0.1:{args.port}/index.html"
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=45000)
                page.wait_for_selector("canvas", timeout=30000)
            except Exception as exc:  # noqa: BLE001
                failures.append(f"{label}: the build never showed a canvas ({exc})")
                page.close()
                continue
            ready = wait_ready(page, msgs, args.boot)
            m = measure(page, out, label, w, h)
            cov = palette_coverage(pathlib.Path(m["shot"]), tokens, allow)
            m["cov"] = cov
            allowed = [p for p in args.ignore_console.split(";") if p]
            # Godot prints an error as a MESSAGE plus stack frame lines ("   at: push_error
            # (…)"). The frame belongs to the message above it, so it is skipped only when
            # that message was allowlisted - an unrelated stack line still fails the half.
            real, prev_allowed = [], False
            for e in errors:
                is_frame = e.strip().startswith("at: ")
                if any(a in e for a in allowed) or (is_frame and prev_allowed):
                    prev_allowed = True
                    continue
                prev_allowed = False
                real.append(e)
            ignored = len(errors) - len(real)
            print(f"S3 ART {label} joined={ready} canvas={m['canvas']} doc={m['doc']} "
                  f"colours={m['colours']} top_share={m['top_share']:.2f} "
                  f"token_coverage={cov:.3f} console_errors={len(real)} "
                  f"console_ignored={ignored} frame={pathlib.Path(m['shot']).name}")
            page.close()

            if cov < args.coverage_floor:
                failures.append(f"{label}: only {cov * 100:.1f}% of the frame sits within the "
                                f"skin's own colours (floor {args.coverage_floor * 100:.0f}%) - "
                                f"the UI is not wearing this skin")

            if not ready:
                failures.append(f"{label}: the build never printed JOINED within {args.boot}s - "
                                f"the frame is the boot screen, not a match (build/s3/{label}.png)")
            if m["colours"] < 24:
                failures.append(f"{label}: the frame is blank ({m['colours']} colours)")
            elif m["top_share"] > 0.90:
                failures.append(f"{label}: one colour covers {m['top_share'] * 100:.0f}% of the "
                                f"frame - that is a splash screen or a dead picture")
            c = m["canvas"]
            if not c:
                failures.append(f"{label}: no canvas")
            else:
                dx = abs(c["w"] - w)
                dy = abs(c["h"] - h)
                if dx > 2 or dy > 2:
                    failures.append(f"{label}: the canvas is {int(c['w'])}x{int(c['h'])} in a "
                                    f"{w}x{h} window ({int(dx)}x{int(dy)}px of it not drawn)")
            d = m["doc"]
            if d["sw"] > d["iw"] + 2 or d["sh"] > d["ih"] + 2:
                failures.append(f"{label}: the page overflows ({d['sw']}x{d['sh']} in "
                                f"{d['iw']}x{d['ih']}) - a scrollbar on a stream picture")
            if real:
                failures.append(f"{label}: {len(real)} console error(s), first: {real[0][:120]} "
                                f"({ignored} allowlisted)")
            rows.append(m)
        browser.close()

    if failures:
        print("S3 ARTIFACT FAILED: " + failures[0])
        for f in failures[1:]:
            print("   also: " + f)
        return 1
    print(f"S3 ARTIFACT PASSED ({len(rows)} size(s) of the release build reached a live match, "
          f"canvas == window, no console error, palette coverage "
          f"{min(r.get('cov', 1.0) for r in rows) if rows else 1.0:.3f}; frames in {out})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
