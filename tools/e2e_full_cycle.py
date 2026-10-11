#!/usr/bin/env python3
"""Full cycle end-to-end: host a match like a user would, have a REAL BROWSER join it as the
second player, and play until someone wins.

WHAT "LIKE A USER" MEANS HERE
  1. the host starts and opens its lobby;
  2. seats are configured — seat 0 for the host, seat 1 REMOTE for the friend (the same rows a
     person fills in the settings dialog, driven through the dialog's own API);
  3. the match starts (the same button);
  4. the host's console shows one invitation link per friend — the link is opened in a real
     browser;
  5. the browser player is driven by its own auto-play (the client answers the legal set the host
     offers), and the match runs until END_GAME or the round limit calls it;
  6. a winner is reported.

WHY A BROWSER AND NOT A SECOND .EXe: the browser is the weaker link — it is the slower renderer,
the one with the WebSocket, and the one a friend actually uses. A cycle that only passes on two
native builds proves nothing about the shipped path.

Run:  python tools/e2e_full_cycle.py [--headless] [--port N] [--web-port N]
"""
from __future__ import annotations

import argparse
import os
import re
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

ADDR_RE = re.compile(r"SERVER ready (ws://[\d.]+:\d+)")
TOKEN_RE = re.compile(r"SERVER seat=(\d+) token=([0-9a-f]+)")
WIN_RE = re.compile(r"(?:winner|КОНЕЦ|END_GAME)")


def free_port(start: int) -> int:
    """The first free port at or after `start`. 8080 is Docker's on many machines, and a site
    server that cannot bind dies silently — the page then serves nothing and the whole cycle
    reports "the friend never joined"."""
    import socket as sk
    for p in range(start, start + 200):
        # BOTH families: a port can be taken on IPv6 only (Docker binds `[::]:8080` on this
        # machine), and testing just IPv4 would hand back a port that then fails to bind.
        taken = False
        for family in (sk.AF_INET, sk.AF_INET6):
            try:
                with sk.socket(family, sk.SOCK_STREAM) as probe:
                    probe.bind(("" if family == sk.AF_INET else "::", p))
            except OSError:
                taken = True
                break
        if not taken:
            return p
    return start


def lan_address() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        addr = s.getsockname()[0]
        s.close()
        return addr
    except OSError:
        return "127.0.0.1"


def main() -> int:
    ap = argparse.ArgumentParser(description="Full cycle: host + real browser, to a winner.")
    ap.add_argument("--port", type=int, default=9080)
    ap.add_argument("--web-port", type=int, default=0, help="0 = pick a free port")
    ap.add_argument("--rounds", type=int, default=60, help="round limit that closes the match")
    ap.add_argument("--minutes", type=float, default=12.0, help="hard stop for the whole cycle")
    ap.add_argument("--headless", action="store_true", help="do not print the frame rate")
    args = ap.parse_args()

    # ---- 1. the site the friend will open ------------------------------------------------
    # A default of 0 means "find one": 8080 belongs to Docker on this machine and the site
    # server cannot bind to it.
    if args.web_port == 0:
        args.web_port = free_port(8080)
        print(f"  (порт сайта выбран автоматически: {args.web_port})")
    site = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "serve.py"), str(args.web_port), "--root", os.path.join(REPO, "build", "web")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)

    # ---- 2. the host, configured the way the settings dialog does it ----------------------
    # `--autostart --smoke-drive --smoke-seats=2 --remote-seats=1` is exactly the host's
    # "invite a friend" fixture: seat 0 is the host's own seat, seat 1 is REMOTE.
    host_cmd = [
        os.path.join(REPO, "build", "windows", "NeuroPropertyTrade.exe"),
        "--resolution", "1440x900", "--rendering-driver", "opengl3",
        "--",
        "--autostart", "--smoke-drive", "--smoke-seats=2", "--remote-seats=1",
        "--server-bind=0.0.0.0", f"--server-port={args.port}",
        f"--round-limit={args.rounds}", "--perf",
        "--proxy-remote=1",          # so a stalled friend never hangs the match
    ]
    host = subprocess.Popen(host_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", bufsize=1, cwd=REPO)

    tokens: dict[int, str] = {}
    addr: str | None = None
    perf: list[str] = []
    deadline = time.time() + 30.0

    def reader() -> None:
        nonlocal addr
        for line in host.stdout:  # type: ignore[union-attr]
            line = line.rstrip()
            m = TOKEN_RE.search(line)
            if m:
                tokens[int(m.group(1))] = m.group(2)
                continue
            m = ADDR_RE.search(line)
            if m:
                addr = m.group(1)
                continue
            if line.startswith("PERF"):
                perf.append(line)

    import threading
    t = threading.Thread(target=reader, daemon=True)
    t.start()
    while time.time() < deadline and (addr is None or not tokens):
        if host.poll() is not None:
            break
        time.sleep(0.2)

    if not addr or not tokens:
        print("FAIL: the host never announced an address and a seat token")
        host.terminate(); site.terminate()
        return 1

    host_lan = lan_address()
    web = f"http://{host_lan}:{args.web_port}/index.html"
    link = f"{web}?seat={tokens[1]}&host={addr}"
    print()
    print("=" * 74)
    print("  ШАГ 3 — ПАРТИЯ НАЧАЛАСЬ, ссылку для друга открываю в браузере")
    print("=" * 74)
    print(f"  адрес:     {addr}")
    print(f"  ссылка:    {link}")

    # ---- 3. the friend opens the link in a real browser ----------------------------------
    from playwright.sync_api import sync_playwright
    agreed = []
    with sync_playwright() as p:
        b = p.chromium.launch(headless=False, args=["--use-angle=d3d11", "--ignore-gpu-blocklist"])
        pg = b.new_page(viewport={"width": 1280, "height": 800})
        pg.add_init_script(
            "window.__log=[];window.__fps=[];let f=0,t=performance.now();"
            "for(const m of ['log','error']){const o=console[m].bind(console);"
            "console[m]=(...a)=>{window.__log.push(a.join(' '));o(...a)}}"
            "const loop=()=>{f++;const n=performance.now();if(n-t>=1000)"
            "{window.__fps.push(Math.round(f*1000/(n-t)));f=0;t=n}requestAnimationFrame(loop)};loop();"
        )
        # A page that fails to load is invisible in a headless run: `goto` raises, or the log stays
        # empty, and the cycle would report only "the friend never joined". Catch it and say why.
        try:
            resp = pg.goto(link, wait_until="load")
            print(f"  браузер: HTTP {resp.status if resp else 'нет ответа'} из {link}")
            if resp is not None and resp.status >= 400:
                print(f"  ответ: {resp.text()[:200]}")
        except Exception as exc:  # noqa: BLE001
            print(f"  браузер: страница не открылась — {exc}")
        pg.bring_to_front()

        joined = deadline_ts = time.time() + 45
        ok = False
        while time.time() < joined:
            time.sleep(1)
            out = pg.evaluate("window.__log")
            if any("JOINED" in l for l in out):
                ok = True
                break
        print(f"\n  ШАГ 4 — друг зашёл по ссылке: {ok}")
        if not ok:
            print("  консоль браузера:")
            for l in pg.evaluate("window.__log")[:12]:
                print("   ", l[:130])
            b.close(); host.terminate(); site.terminate()
            return 1

        # ---- 4. play until the match ends -----------------------------------------------
        print("  ШАГ 5 — ИДЁТ ИГРА (друг отвечает на предложенные действия)")
        stop = time.time() + args.minutes * 60.0
        ended = False
        winner = ""
        while time.time() < stop:
            time.sleep(3)
            out = pg.evaluate("window.__log")
            agreed = [l for l in out if "VERDICT" in l]
            if any(re.search(r"END_GAME|KOHEЦ|побед", l, re.I) for l in out):
                ended = True
                break
            # the host's own log tells us when the engine is done
            if host.poll() is not None:
                break
        if ended:
            winner = next((l for l in out if "winner" in l.lower()), "")

        fps = [f for f in pg.evaluate("window.__fps") if f > 0]
        verdicts = [l for l in agreed]
        print()
        print("=" * 74)
        print("  РЕЗУЛЬТАТ")
        print("=" * 74)
        print(f"  ходов принято движком: {len(verdicts)}")
        ok_n = sum(1 for l in verdicts if "ok=true" in l)
        no_n = sum(1 for l in verdicts if "ok=false" in l)
        print(f"    принято: {ok_n}   отвергнуто: {no_n}")
        if perf:
            import statistics
            vals = [int(l.split("fps=")[1].split()[0]) for l in perf]
            vals = [v for v in vals if v > 5]
            if vals:
                print(f"  FPS хоста (.exe): median={statistics.median(vals):.0f} mean={statistics.mean(vals):.0f} "
                      f"min={min(vals)} max={max(vals)} замеров={len(vals)}")
        if fps:
            import statistics
            print(f"  FPS браузера: median={statistics.median(fps):.0f} mean={statistics.mean(fps):.0f} "
                  f"min={min(fps)} max={max(fps)} замеров={len(fps)}")
        print(f"  партия завершена: {ended}")
        if winner:
            print(f"  {winner}")
        pg.screenshot(path=os.path.join(REPO, "build", "e2e_final.png"))
        b.close()

    host.terminate()
    site.terminate()
    return 0 if ok_n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
