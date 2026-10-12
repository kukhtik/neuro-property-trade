#!/usr/bin/env python3
"""Full user-path cycle: host a match, a real browser joins as the second player, play to a winner.

WHY THIS ONE SCRIPT: the cycle kept failing and being mis-diagnosed because the interesting lines
(`PLAYED`, `IDLE`, `VERDICT`) are printed by the BROWSER CLIENT, not the host. Reading the host log
made a broken client look like a healthy match. So this script keeps the client's console as a
first-class output, next to both frame rates, and it is the only thing that is allowed to say the
cycle passed.

Run: python tools/cycle_check.py
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
WEB_ROOT = os.path.join(REPO, "build", "web")

TOKEN_RE = re.compile(r"SERVER seat=(\d+) token=([0-9a-f]+)")
ADDR_RE = re.compile(r"SERVER ready (ws://[\d.]+:\d+)")


def free_port(start: int) -> int:
    """Both address families: Docker binds [::]:8080 here, so an IPv4-only probe lies."""
    for p in range(start, start + 200):
        taken = False
        for fam, host in ((socket.AF_INET, ""), (socket.AF_INET6, "::")):
            try:
                with socket.socket(fam, socket.SOCK_STREAM) as s:
                    s.bind((host, p))
            except OSError:
                taken = True
                break
        if not taken:
            return p
    return start


def main() -> int:
    web_port = free_port(8140)
    host_port = free_port(9700)
    print(f"порты: сайт {web_port}, хост {host_port}")

    site = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "serve.py"), str(web_port), "--root", WEB_ROOT],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(2.0)

    # «настройка партии», как её задаёт диалог: сид, два места, лимит времени на ход и на партию.
    host_cmd = [
        EXE, "--resolution", "1440x900", "--rendering-driver", "opengl3", "--",
        "--autostart", "--smoke-drive", "--smoke-seats=2", "--remote-seats=1",
        "--seed=4242", "--server-bind=0.0.0.0", f"--server-port={host_port}",
        "--round-limit=25", "--perf",
    ]
    host = subprocess.Popen(host_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace", bufsize=1, cwd=REPO)

    tokens: dict[int, str] = {}
    addr: str | None = None
    perf: list[int] = []
    host_lines: list[str] = []

    def read_host() -> None:
        nonlocal addr
        for line in host.stdout:  # type: ignore[union-attr]
            line = line.rstrip()
            host_lines.append(line)
            if m := TOKEN_RE.search(line):
                tokens[int(m.group(1))] = m.group(2)
                continue
            if m := ADDR_RE.search(line):
                addr = m.group(1)
                continue
            if line.startswith("PERF fps="):
                try:
                    perf.append(int(line.split("fps=")[1].split()[0]))
                except (IndexError, ValueError):
                    pass

    threading.Thread(target=read_host, daemon=True).start()
    deadline = time.time() + 60.0
    while time.time() < deadline and (addr is None or not tokens):
        if host.poll() is not None:
            print("ХОСТ УПАЛ при старте")
            site.terminate()
            return 1
        time.sleep(0.25)

    if not addr or not tokens:
        print("ХОСТ НЕ ОБЪЯВИЛ адрес/токен")
        host.terminate(); site.terminate()
        return 1

    link = f"http://127.0.0.1:{web_port}/index.html?seat={tokens[1]}&host={addr}"
    print(f"ссылка для друга: {link}")

    from playwright.sync_api import sync_playwright

    client_lines: list[str] = []
    client_fps: list[int] = []
    verdicts: list[str] = []
    ended = False
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False, args=["--use-angle=d3d11", "--ignore-gpu-blocklist"])
        pg = b.new_page(viewport={"width": 1280, "height": 800})

        # EVERY console line is kept: the client's own trace is the evidence.
        pg.on("console", lambda m: client_lines.append(f"{m.type}: {m.text}"))
        pg.on("pageerror", lambda e: client_lines.append(f"PAGEERROR: {e}"))
        pg.add_init_script(
            "window.__fps=[];let f=0,t=performance.now();const loop=()=>{f++;const n=performance.now();"
            "if(n-t>=1000){window.__fps.push(Math.round(f*1000/(n-t)));f=0;t=n}requestAnimationFrame(loop)};loop();"
        )
        resp = pg.goto(link, wait_until="load")
        print(f"страница: HTTP {resp.status if resp else '—'}")
        pg.bring_to_front()

        t0 = time.time()
        browser_closed = False
        while time.time() - t0 < 900:
            time.sleep(3)
            # The game can be stopped by a human at any moment (it is a real window). Without this
            # guard a stop surfaces as a Playwright traceback and the numbers collected so far are
            # thrown away — which is how two full-cycle runs were lost.
            try:
                fps = pg.evaluate("window.__fps")
                if fps:
                    client_fps.extend(fps)
                    pg.evaluate("window.__fps=[]")
            except Exception as exc:  # noqa: BLE001
                browser_closed = True
                print(f"  окно игры закрыто извне ({type(exc).__name__}) — отчитываюсь по собранному")
                break
            if any("END_GAME" in l or "winner" in l.lower() for l in client_lines[-40:]):
                ended = True
                break
            if host.poll() is not None:
                break
        try:
            pg.screenshot(path=os.path.join(REPO, "build", "cycle_final.png"))
        except Exception:  # noqa: BLE001
            pass
        b.close()

    verdicts = [l for l in client_lines if "VERDICT" in l]
    played = [l for l in client_lines if "PLAYED" in l]
    idle = [l for l in client_lines if "IDLE" in l]
    claims = [l for l in host_lines if "SEAT CLAIMED" in l]

    print()
    print("=" * 72)
    print("  РЕЗУЛЬТАТ ПОЛНОГО ЦИКЛА")
    print("=" * 72)
    print(f"  место отдано другу:       {'да' if claims else 'НЕТ'}")
    print(f"  браузер подключился:      {'да' if any('JOINED' in l for l in client_lines) else 'НЕТ'}")
    print(f"  ходов сделано клиентом:   {len(played)}")
    print(f"  вердиктов движка:         {len(verdicts)}"
          f"  (принято {sum(1 for l in verdicts if 'ok=true' in l)},"
          f" отказано {sum(1 for l in verdicts if 'ok=false' in l)})")
    print(f"  холостых состояний:       {len(idle)}")
    hp = [v for v in perf if v > 5]
    if hp:
        print(f"  FPS хоста  (.exe):  median={median(hp):.0f} mean={mean(hp):.0f} min={min(hp)} max={max(hp)} n={len(hp)}")
    cf = [v for v in client_fps if v > 0]
    if cf:
        print(f"  FPS браузера       :  median={median(cf):.0f} mean={mean(cf):.0f} min={min(cf)} max={max(cf)} n={len(cf)}")
    print(f"  ПОБЕДА:                   {'да' if ended else 'НЕТ (партия не завершилась)'}")
    if browser_closed:
        print("  (окно игры закрыто извне — цикл прерван, а не доведён до конца)")
    win = [l for l in client_lines if "winner" in l.lower() or "EVENT" in l]
    for w in win[:3]:
        print(f"     {w[:110]}")
    if not played:
        print()
        print("  --- ПОЧЕМУ КЛИЕНТ МОЛЧАЛ (его консоль) ---")
        for l in client_lines[:14]:
            print(f"     {l[:120]}")

    host.terminate(); site.terminate()
    return 0 if ended else 1


if __name__ == "__main__":
    sys.exit(main())
