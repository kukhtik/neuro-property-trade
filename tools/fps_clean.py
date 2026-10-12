#!/usr/bin/env python3
"""Clean frame-rate reading for BOTH sides of a real match, with nothing else running.

The earlier "catastrophic FPS" reading was taken while several test hosts and browsers of my own
were still alive — the machine was competing with itself. This script exists so the number has one
meaning: host in one process, one browser as the friend, nothing else on the box.

Run: python tools/fps_clean.py
"""
from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import threading
import time
from statistics import mean, median

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
EXE = os.path.join(REPO, "build", "windows", "NeuroPropertyTrade.exe")

TOKEN_RE = re.compile(r"SERVER seat=(\d+) token=([0-9a-f]+)")
ADDR_RE = re.compile(r"SERVER ready (ws://[\d.]+:\d+)")


def free_port(start: int) -> int:
    for p in range(start, start + 200):
        ok = True
        for fam, host in ((socket.AF_INET, ""), (socket.AF_INET6, "::")):
            try:
                with socket.socket(fam, socket.SOCK_STREAM) as s:
                    s.bind((host, p))
            except OSError:
                ok = False
                break
        if ok:
            return p
    return start


def main() -> int:
    web_port, host_port = free_port(8160), free_port(9760)
    site = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "serve.py"), str(web_port),
         "--root", os.path.join(REPO, "build", "web")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(2.0)

    host = subprocess.Popen(
        [EXE, "--resolution", "1440x900", "--rendering-driver", "opengl3", "--",
         "--autostart", "--smoke-drive", "--smoke-seats=2", "--remote-seats=1",
         "--seed=4242", "--server-bind=0.0.0.0", f"--server-port={host_port}",
         "--round-limit=25", "--perf"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace", bufsize=1, cwd=REPO,
    )

    tokens: dict[int, str] = {}
    addr: str | None = None
    host_fps: list[int] = []

    def read_host() -> None:
        nonlocal addr
        for line in host.stdout:  # type: ignore[union-attr]
            if m := TOKEN_RE.search(line):
                tokens[int(m.group(1))] = m.group(2)
            elif m := ADDR_RE.search(line):
                addr = m.group(1)
            elif line.startswith("PERF fps="):
                try:
                    host_fps.append(int(line.split("fps=")[1].split()[0]))
                except (IndexError, ValueError):
                    pass

    threading.Thread(target=read_host, daemon=True).start()
    dl = time.time() + 60
    while time.time() < dl and (addr is None or not tokens):
        time.sleep(0.25)
    if not addr or not tokens:
        print("хост не поднялся"); host.terminate(); site.terminate(); return 1

    link = f"http://127.0.0.1:{web_port}/index.html?seat={tokens[1]}&host={addr}"

    from playwright.sync_api import sync_playwright
    client_fps: list[int] = []
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False, args=[
            "--use-angle=d3d11", "--ignore-gpu-blocklist",
            # A backgrounded Chromium throttles requestAnimationFrame to ~1 fps. Without these a
            # window that slipped behind another reads as a collapsed frame rate that is not there,
            # and the whole perf section becomes a measurement artifact.
            "--disable-background-timer-throttling",
            "--disable-backgrounding-occluded-windows",
            "--disable-renderer-backgrounding",
        ])
        pg = b.new_page(viewport={"width": 1280, "height": 800})
        pg.add_init_script(
            "window.__fps=[];let f=0,t=performance.now();const loop=()=>{f++;const n=performance.now();"
            "if(n-t>=1000){window.__fps.push(Math.round(f*1000/(n-t)));f=0;t=n}requestAnimationFrame(loop)};loop();"
        )
        pg.goto(link, wait_until="load")
        pg.bring_to_front()
        for _ in range(30):
            time.sleep(3)
            fps = pg.evaluate("window.__fps")
            if fps:
                client_fps.extend(fps)
                pg.evaluate("window.__fps=[]")
        # whether the page believed it was visible: 1 fps + hidden is throttling, not the game
        vis = pg.evaluate("document.visibilityState")
        print(f"  (страница считала себя: {vis})")
        b.close()

    host.terminate(); site.terminate()

    print()
    print("=" * 68)
    print("  ЧИСТЫЙ ЗАМЕР (кроме этих двух процессов на машине ничего нет)")
    print("=" * 68)
    hp = [v for v in host_fps if v > 5]
    cf = [v for v in client_fps if v > 0]
    if hp:
        print(f"  ХОСТ .exe 1440x900 : median={median(hp):.0f} mean={mean(hp):.0f} min={min(hp)} max={max(hp)} n={len(hp)}")
    if cf:
        print(f"  БРАУЗЕР   1280x800 : median={median(cf):.0f} mean={mean(cf):.0f} min={min(cf)} max={max(cf)} n={len(cf)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
