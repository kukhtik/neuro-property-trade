"""Prove that a mockup is ALIVE - or prove that it is a picture.

A storyboard is not an animation: a file can show eleven events in eleven frames and still be a
poster. This probe measures the difference instead of trusting the file's own words.

Method (both numbers below are measured, not guessed):
  * The page is allowed to SETTLE first (network idle + fonts ready + 1s). Without that a page
    whose layout is still arriving reads as moving: on boardfirst-1-live-spacebunny the
    "no animations" pairs decayed 7.33% -> 2.99% -> 0.00%.
  * Four shots, ~0.8s apart. The verdict uses the UNION of what changed across the whole window
    (per pixel: max-min over the four shots), NOT one pair. One pair misjudges a slow loop:
    boardfirst-1-live-deepseek measured 0.27% on one pair and 2.66% on another, so a pair threshold
    called a living page dead once and alive the next time.
  * Then the same measurement with motion disabled: `prefers-reduced-motion: reduce` plus an
    injected `animation:none; transition:none` sheet - the state the product's own "Анимации"
    switch must produce.

Verdict lines (grep-able, like the rest of the toolset):
  LIVE union=<pct>% verdict=PASS|STATIC
  OFF  union=<pct>% verdict=PASS|MOVING-WHEN-OFF
  ==> LIVENESS PASSED|FAILED <file>

A file passes when it MOVES with motion on (union >= --live-min, default 0.5% of the frame) AND
holds still with motion off (union <= --off-max, default 0.05%).

Usage: py -3.12 liveness_probe.py [--live-min 0.5] [--off-max 0.05] [--gate 0.8] <file.html> [...]
"""
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright
from PIL import Image

W, H = 1600, 1200
# `*` does NOT cover pseudo-elements. Measured on boardfirst-1-live-spacebunny: with only `*`
# killed, 25 animations kept RUNNING (the browser's own document.getAnimations() listed them,
# targeting `.cell`/`.cell::after` - the wave, lot and cf keyframes). Its own reduced-motion rule
# `*{animation:none!important}` misses them too, so its "animations off" switch is a lie.
KILL = ("*,*::before,*::after{animation:none !important;transition:none !important;"
        "animation-play-state:paused !important;animation-duration:0s !important}")


def union_pct(shots):
    """Share of pixels that change at all across the window (per pixel: max-min over the shots)."""
    imgs = [Image.open(p).convert("RGB").load() for p in shots]
    n = 0
    for y in range(0, H, 2):          # every other row is enough for a share
        for x in range(0, W, 2):
            lo = hi = imgs[0][x, y]
            for px in imgs[1:]:
                c = px[x, y]
                if c < lo:
                    lo = c
                if c > hi:
                    hi = c
            if abs(hi[0] - lo[0]) + abs(hi[1] - lo[1]) + abs(hi[2] - lo[2]) > 24:
                n += 1
    return 100.0 * n / ((W // 2) * (H // 2))


def settle(page):
    try:
        page.wait_for_load_state("networkidle", timeout=5000)
    except Exception:                                    # noqa: BLE001 - a local file may settle with no network
        pass
    try:
        page.evaluate("() => document.fonts ? document.fonts.ready : true")
    except Exception:                                    # noqa: BLE001
        pass
    page.wait_for_timeout(1000)


def shoot(page, out: Path, tag: str, gate: float, count: int = 4):
    shots = []
    for k in range(count):
        png = out / f"{tag}-t{k}.png"
        page.screenshot(path=str(png), clip={"x": 0, "y": 0, "width": W, "height": H})
        shots.append(png)
        if k < count - 1:
            page.wait_for_timeout(int(gate * 1000))
    return shots


def main(argv):
    args, files = [], []
    i = 0
    while i < len(argv):
        if argv[i].startswith("--"):
            args.append((argv[i], argv[i + 1]))
            i += 2
        else:
            files.append(argv[i])
            i += 1
    opt = dict(args)
    live_min = float(opt.get("--live-min", 0.5))
    off_max = float(opt.get("--off-max", 0.05))
    gate = float(opt.get("--gate", 0.8))
    if not files:
        print(__doc__)
        return 2

    out = Path("liveness")
    out.mkdir(parents=True, exist_ok=True)
    fails = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--disable-background-timer-throttling",
                                          "--disable-backgrounding-occluded-windows",
                                          "--disable-renderer-backgrounding"])
        for f in files:
            name = Path(f).stem
            print(f"=== {name}")

            page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
            page.goto(Path(f).absolute().as_uri(), wait_until="load")
            settle(page)
            s = shoot(page, out / name, "live", gate)
            live_union = union_pct(s)
            live_ok = live_union >= live_min
            print(f"LIVE union={live_union:.2f}% verdict={'PASS' if live_ok else 'STATIC'}")
            page.close()

            page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1,
                                    reduced_motion="reduce")
            page.goto(Path(f).absolute().as_uri(), wait_until="load")
            page.add_style_tag(content=KILL)
            settle(page)
            s = shoot(page, out / f"{name}-off", "off", gate)
            off_union = union_pct(s)
            off_ok = off_union <= off_max
            print(f"OFF  union={off_union:.2f}% verdict={'PASS' if off_ok else 'MOVING-WHEN-OFF'}")
            page.close()

            passed = live_ok and off_ok
            fails += 0 if passed else 1
            print(f"==> LIVENESS {'PASSED' if passed else 'FAILED'} {name}")
        browser.close()
    print(f"TOTAL LIVENESS FAILS: {fails}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
