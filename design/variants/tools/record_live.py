"""Записать анимацию макета в MP4: кадры каждые 0.2 с, затем ffmpeg.

Зачем: PNG-рендер и страница сравнения статичны по построению, а живой файл надо УВИДЕТЬ.
usage: py -3.12 record_live.py <out_dir> <seconds> <file.html> [...]
"""
import subprocess
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright
from PIL import Image, ImageChops

W, H = 1600, 1200
FPS_STEP = 0.2


def main(out_dir, seconds, files):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    frames_dir = out / "frames"
    frames_dir.mkdir(exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--disable-background-timer-throttling",
                                          "--disable-backgrounding-occluded-windows",
                                          "--disable-renderer-backgrounding"])
        for f in files:
            stem = Path(f).stem
            page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
            page.goto(Path(f).absolute().as_uri(), wait_until="load")
            page.wait_for_timeout(1200)          # оседание + первый кадр шкалы
            n = int(seconds / FPS_STEP)
            shots = []
            for k in range(n):
                png = frames_dir / f"{stem}-{k:04d}.png"
                page.screenshot(path=str(png), clip={"x": 0, "y": 0, "width": W, "height": H})
                shots.append(png)
                page.wait_for_timeout(int(FPS_STEP * 1000))
            page.close()

            first = Image.open(shots[0]).convert("RGB")
            biggest = 0
            for s in shots[1:]:
                d = ImageChops.difference(first, Image.open(s).convert("RGB")).convert("L")
                biggest = max(biggest, d.getextrema()[1])
            mp4 = out / f"{stem}.mp4"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "5",
                            "-i", str(frames_dir / f"{stem}-%04d.png"),
                            "-vf", "scale=1200:-2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                            "-crf", "20", str(mp4)], check=True)
            for s in shots:
                s.unlink()
            print(f"{mp4.name}: кадров {n}, наибольшее отличие кадра от первого = {biggest}/255, "
                  f"{mp4.stat().st_size} байт")
        browser.close()


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]), sys.argv[3:])
