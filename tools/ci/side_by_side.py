"""Render the MOCKUP and the RESULT at the same size, side by side.

The value comparison (compare_mockup.py) checks what is DECLARED — palette, ratios,
regions. It cannot say whether the thing LOOKS like the mockup. This does that part: it
opens the mockup in a browser, screenshots it at the app's own resolution, and puts the two
frames together so they can be judged against each other rather than in turn.

It is a JUDGEMENT AID, not a gate. There is no threshold that means "looks right": the two
are different renderers with different fonts, so it produces an image and stops there.
"""
import os
import pathlib
import sys

from playwright.sync_api import sync_playwright

PROJ = pathlib.Path(__file__).resolve().parents[2]
## The mockup lives IN the repository since the v3 redesign and is generated from the game
## (design/tools/build_prototype.py); a desktop path would make this tool usable on exactly
## one machine.
MOCKUP = PROJ / "design" / "ui-prototype.html"
OUT = PROJ / "build" / "smoke"
APP = OUT / "admin.png"
WIDTH, HEIGHT = 1440, 900


def main():
    theme = sys.argv[1] if len(sys.argv) > 1 else "neuro"
    if not MOCKUP.exists():
        print("FAIL: no mockup at %s" % MOCKUP)
        return 1
    if not APP.exists():
        print("FAIL: no app frame at %s (run smoke_all_roles.py first)" % APP)
        return 1

    # The prototype is driven by its own query contract (design/tools/render_prototype.py
    # uses the same one): `scene=` picks the demo state, `static=1` freezes the demo loop,
    # `anim=off` kills tweens. `turn-human` is the mid-match state the app frame shows;
    # another scene can be passed as the second argument.
    scene = sys.argv[2] if len(sys.argv) > 2 else "turn-human"
    mock_png = OUT / "mockup.png"
    print("mockup  %s (scene=%s)" % (MOCKUP.name, scene))
    print("theme   %s" % theme)
    print("size    %dx%d (the app's own)" % (WIDTH, HEIGHT))

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": WIDTH, "height": HEIGHT})
        url = "%s?theme=%s&scene=%s&static=1&anim=off&probe=off" % (MOCKUP.as_uri(), theme, scene)
        page.goto(url, wait_until="networkidle", timeout=60000)
        page.wait_for_timeout(600)
        page.screenshot(path=str(mock_png), full_page=False)
        browser.close()
    print("wrote   %s" % mock_png)

    # --- put them side by side ---------------------------------------------------------
    from PIL import Image, ImageDraw
    a = Image.open(APP).convert("RGB")
    b = Image.open(mock_png).convert("RGB")
    h = max(a.height, b.height)
    pad, label = 12, 26
    canvas = Image.new("RGB", (a.width + b.width + pad * 3, h + label * 2), (10, 12, 16))
    canvas.paste(b, (pad, label))                       # mockup on the left: it is the target
    canvas.paste(a, (pad * 2 + b.width, label))         # result on the right
    d = ImageDraw.Draw(canvas)
    d.text((pad, 6), "МАКЕТ — %s" % theme, fill=(232, 237, 243))
    d.text((pad * 2 + b.width, 6), "ПРИЛОЖЕНИЕ — %s" % theme, fill=(232, 237, 243))
    side = OUT / "side_by_side.png"
    canvas.save(side)
    print("wrote   %s  (%dx%d)" % (side, canvas.width, canvas.height))
    print()
    print("Open it, or use the report. This is for the eye, not a threshold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
