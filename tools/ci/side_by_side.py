"""Render the MOCKUP and the RESULT at the same size, side by side.

The value comparison (`compare_mockup.py`) checks what is DECLARED — palette, ratios, regions. It
cannot say whether the thing LOOKS like the mockup. This does that part: it opens the mockup in a
browser, screenshots it at the app's own resolution, and puts the two frames together so they can
be judged against each other rather than in turn.

It is a JUDGEMENT AID, not a value gate. There is no threshold that means "looks right": the two
are different renderers with different fonts, so it produces an image and stops there.

TWO THINGS IT NO LONGER DOES (both were real defects, not style):

  * pair the CURRENT mockup with LAST RUN's app frame. The app half used to be hard-coded to
    `build/smoke/admin.png`, which by then was a build from a day earlier — the HG-11 sin with a
    picture instead of a number. `--app` chooses the frame and `--started` makes a stale one a
    hard failure;
  * fail with an empty error text. Every refusal now says what it wanted and where it looked, and
    a missing playwright/Pillow is named as such (that is how this tool came to be reported as
    "падает с пустым текстом ошибки").

Run:  python tools/ci/side_by_side.py [--theme neuro] [--scene turn-human] \
          [--app build/renders/turn-human_neuro.png] [--out build/renders/side_by_side.png] \
          [--mockup design/ui-prototype.html] [--size 1440x900] [--started <epoch>]
"""
import argparse
import os
import pathlib
import sys
import time

PROJ = pathlib.Path(__file__).resolve().parents[2]
## The mockup lives IN the repository since the v3 redesign and is generated from the game
## (design/tools/build_prototype.py); a desktop path would make this tool usable on exactly
## one machine.
DEFAULT_MOCKUP = PROJ / "design" / "ui-prototype.html"
DEFAULT_APP = PROJ / "build" / "smoke" / "admin.png"
DEFAULT_OUT = PROJ / "build" / "smoke" / "side_by_side.png"


def fail(msg: str) -> int:
    print("FAIL: %s" % msg)
    return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mockup", default=str(DEFAULT_MOCKUP))
    ap.add_argument("--app", default=str(DEFAULT_APP))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--theme", default="neuro")
    ap.add_argument("--scene", default="turn-human")
    ap.add_argument("--size", default="1440x900")
    ap.add_argument("--started", type=float, default=0.0,
                    help="epoch seconds this run began; an app frame older than that is stale")
    ap.add_argument("theme_positional", nargs="?", default=None)
    ap.add_argument("scene_positional", nargs="?", default=None)
    args = ap.parse_args()

    # the two legacy positional arguments (`side_by_side.py neuro turn-human`) still work
    theme = args.theme_positional or args.theme
    scene = args.scene_positional or args.scene
    mockup = pathlib.Path(args.mockup)
    app = pathlib.Path(args.app)
    out = pathlib.Path(args.out)
    try:
        WIDTH, HEIGHT = (int(x) for x in args.size.lower().split("x"))
    except ValueError:
        return fail("--size wants WxH (got `%s`)" % args.size)

    if not mockup.exists():
        return fail("no mockup at %s" % mockup)
    if not app.exists():
        return fail("no app frame at %s (run the capture that produces it first)" % app)
    if args.started and os.path.getmtime(app) < args.started - 2:
        return fail("the app frame %s is OLDER than this run (mtime %s) - a side-by-side against "
                    "last run's build is not evidence"
                    % (app, time.strftime("%Y-%m-%d %H:%M:%S",
                                          time.localtime(os.path.getmtime(app)))))
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # noqa: BLE001
        return fail("playwright is not importable (%s) - the mockup half cannot be rendered; "
                    "on this machine that interpreter is `py -3.12`" % exc)

    out.parent.mkdir(parents=True, exist_ok=True)
    mock_png = out.parent / (out.stem + "-mockup.png")
    print("mockup  %s (scene=%s)" % (mockup.name, scene))
    print("theme   %s" % theme)
    print("app     %s" % app)
    print("size    %dx%d (the app's own)" % (WIDTH, HEIGHT))

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": WIDTH, "height": HEIGHT})
        url = "%s?theme=%s&scene=%s&static=1&anim=off&probe=off" % (mockup.as_uri(), theme, scene)
        try:
            page.goto(url, wait_until="networkidle", timeout=60000)
        except Exception as exc:  # noqa: BLE001
            browser.close()
            return fail("the mockup did not load (%s): %s" % (url, exc))
        page.wait_for_timeout(600)
        page.screenshot(path=str(mock_png), full_page=False)
        browser.close()
    print("wrote   %s" % mock_png)

    # --- put them side by side ---------------------------------------------------------
    try:
        from PIL import Image, ImageDraw
    except Exception as exc:  # noqa: BLE001
        return fail("Pillow is not importable (%s) - cannot compose the two frames" % exc)
    a = Image.open(app).convert("RGB")
    b = Image.open(mock_png).convert("RGB")
    h = max(a.height, b.height)
    pad, label = 12, 26
    canvas = Image.new("RGB", (a.width + b.width + pad * 3, h + label * 2), (10, 12, 16))
    canvas.paste(b, (pad, label))                       # mockup on the left: it is the target
    canvas.paste(a, (pad * 2 + b.width, label))         # result on the right
    d = ImageDraw.Draw(canvas)
    d.text((pad, 6), "МАКЕТ — %s" % theme, fill=(232, 237, 243))
    d.text((pad * 2 + b.width, 6), "ПРИЛОЖЕНИЕ — %s" % theme, fill=(232, 237, 243))
    canvas.save(out)
    print("wrote   %s  (%dx%d)" % (out, canvas.width, canvas.height))
    print()
    print("Open it, or use the report. This is for the eye, not a threshold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
