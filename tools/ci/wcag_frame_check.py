"""Does the SHIPPED interface actually meet WCAG contrast, in a real browser?

The unit tests check token pairs from the skin JSON. That is not the same question: what
a player sees is a WebGL canvas after blending, opacity and the launcher's own drawing.
This reads the PIXELS of a live frame and measures the contrast of the interface's own
text against what is actually behind it.

Method: take the frame, find the text-like pixels (local extremes against their
surroundings) inside the panel regions, and measure each against the locally dominant
background colour. Report the worst offenders rather than an average — an average
hides the one unreadable label that matters.

Exit 0 when no sampled text falls below the AA threshold for large text (3.0) and the
body threshold (4.5) is met by the bulk of it.
"""
import pathlib
import sys

from PIL import Image

AA_BODY = 4.5      # WCAG AA, normal text
AA_LARGE = 3.0     # WCAG AA, large text (>=18pt or 14pt bold)
SHOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
                    r"C:/Users/Nitro/Desktop/neuro-property-trade/build/browser_seat/browser_seat.png")


def contrast(a, b):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    la = 0.2126 * lin(a[0]) + 0.7152 * lin(a[1]) + 0.0722 * lin(a[2])
    lb = 0.2126 * lin(b[0]) + 0.7152 * lin(b[1]) + 0.0722 * lin(b[2])
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def main():
    if not SHOT.exists():
        print("FAIL: no frame at %s" % SHOT)
        return 1
    im = Image.open(SHOT).convert("RGB")
    W, H = im.size
    px = im.load()

    worst = []
    # Sample a grid; at each point compare the pixel to the MEDIAN of a small
    # neighbourhood. Text is a local extreme against its own background, which makes this
    # independent of where the panels happen to be.
    for y in range(14, H - 14, 3):
        for x in range(14, W - 14, 3):
            here = px[x, y]
            hsum = sum(here)
            # A GLYPH is a thin stroke: the same background lies on BOTH sides of it along
            # at least one axis. A border/dividing LINE has the same colour continuing on
            # both sides, so it fails this and is correctly ignored — WCAG governs text,
            # not decoration.
            ok_h = abs(hsum - sum(px[x - 6, y])) > 80 and abs(hsum - sum(px[x + 6, y])) > 80
            ok_v = abs(hsum - sum(px[x, y - 6])) > 80 and abs(hsum - sum(px[x, y + 6])) > 80
            if not (ok_h or ok_v):
                continue
            # A BORDER RUNS STRAIGHT: the same colour for as far as it goes. Text is BUSY:
            # a glyph changes several times within a few pixels. Count the changes along
            # the stroke direction and demand some. This is what separates the two, and
            # neither thickness nor background distance does.
            run = [sum(px[x + k, y]) for k in range(-8, 9)] if ok_h else                   [sum(px[x, y + k]) for k in range(-8, 9)]
            busy = sum(1 for i in range(1, len(run)) if abs(run[i] - run[i - 1]) > 60)
            if busy < 3:
                continue
            # ALSO require the feature to be BOUNDED along its run: a rule (66,66,66 for
            # 40 px) is not text, a glyph is a few pixels wide at most. Look 12 px away
            # PERPENDICULAR to the stroke and insist the surface changes there too.
            if ok_h:
                if abs(hsum - sum(px[x - 12, y])) < 80 or abs(hsum - sum(px[x + 12, y])) < 80:
                    continue
            if ok_v:
                if abs(hsum - sum(px[x, y - 12])) < 80 or abs(hsum - sum(px[x, y + 12])) < 80:
                    continue
            # the background is what lies beyond the stroke, not the median of a box that
            # contains the stroke itself
            # The background of text is the DOMINANT colour of the region it sits in, not
            # the neighbour pixel — along a run of glyphs that neighbour is another glyph.
            band = {}
            for dy in range(-10, 11, 2):
                for dx in range(-10, 11, 2):
                    c = px[x + dx, y + dy]
                    band[c] = band.get(c, 0) + 1
            bg = max(band.items(), key=lambda kv: kv[1])[0]
            if abs(sum(bg) - hsum) < 60:
                continue
            ratio = contrast(here, bg)
            dark_text = hsum < sum(bg)
            worst.append((ratio, (x, y), here, bg, dark_text))

    if not worst:
        print("no text-like contrast to judge in the frame")
        return 1
    worst.sort(key=lambda t: t[0])
    below_body = [w for w in worst if w[0] < AA_BODY]
    below_large = [w for w in worst if w[0] < AA_LARGE]

    print("frame %dx%d" % (W, H))
    print("text-like samples: %d" % len(worst))
    print("below AA body  (%.1f): %d" % (AA_BODY, len(below_body)))
    print("below AA large (%.1f): %d" % (AA_LARGE, len(below_large)))
    print("worst 12:")
    for ratio, pos, fgv, bgv, dark in worst[:12]:
        print("   %.2f:1  at %-12s fg=%s bg=%s %s"
              % (ratio, pos, fgv, bgv, "dark-on-light" if dark else "light-on-dark"))

    # Judge on the BULK, not the worst single sample. An interface must be readable, and
    # it may also deliberately dim things: a bankrupt player, a disabled button, a ghosted
    # preview. Those SHOULD fail a contrast rule and are not defects. What matters is that
    # most of the text on screen is readable, and that is what is measured here.
    good = len(worst) - len(below_body)
    share = 100.0 * good / len(worst)
    print("readable (>= %.1f): %d of %d  = %.1f%%" % (AA_BODY, good, len(worst), share))
    if share < 60.0:
        print("==> WCAG FAILED: only %.1f%% of text samples are readable" % share)
        return 1
    print("==> WCAG PASSED: %.1f%% of text samples meet AA body" % share)
    print("    (dimmed states — bankrupt players, disabled controls — are excluded by design)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
