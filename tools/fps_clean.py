#!/usr/bin/env python3
"""Clean frame-rate reading for BOTH sides of a real match, with nothing else running.

The earlier "catastrophic FPS" reading was taken while several test hosts and browsers of my own
were still alive — the machine was competing with itself. This script exists so the number has one
meaning: host in one process, one browser as the friend, nothing else on the box.

The measurement is a GATE, not a ritual:
  * a PREFLIGHT refuses to start while another game host or serve.py is already on the machine —
    numbers taken next to a competing process measure the machine, not the build;
  * exit 1 when the browser lands under 30 median fps — that is the regression signal, and a run
    catches it without a human judging a number;
  * exit 2 when the number itself is invalid (the page was hidden: Chromium throttles
    requestAnimationFrame to ~1 fps, an artifact that must not be published as a regression).

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
## Which build to measure: after the restoration the FRESH exports live in build/current/
## (build/{web,windows} keep the pre-swap archive as the "working join" reference). Measure the
## fresh one when it exists - a perf number taken on yesterday's exe is not this session's number.
def _pick(*cands: str) -> str:
    for c in cands:
        if os.path.exists(c):
            return c
    return cands[0]


EXE = _pick(os.path.join(REPO, "build", "current", "windows", "NeuroPropertyTrade.exe"),
            os.path.join(REPO, "build", "windows", "NeuroPropertyTrade.exe"))
WEB_ROOT = _pick(os.path.join(REPO, "build", "current", "web"),
                 os.path.join(REPO, "build", "web"))
## The host writes its PERF samples to `<log-dir>/perf.log` — they must not ride in the run log
## (146 of 160 lines there were samples). The game truncates the file when a session starts.
LOGDIR = os.path.join(REPO, "build", "fps_run")

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


def stray_processes() -> list[str]:
    """Game hosts and serve.py instances already alive on this machine.

    A measurement taken next to another host measures the competition, not the build — that was
    the whole lesson of the first "catastrophic FPS" reading. Windows: command lines via CIM.
    A check that cannot LOOK must not pretend it looked: if the listing fails, the run proceeds
    without the preflight, and says so.
    """
    hits: list[str] = []
    try:
        ps = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-CimInstance Win32_Process | ForEach-Object { $_.Name + '|' + $_.CommandLine }"],
            # decode, do not explode: some command lines carry OEM-encoded Cyrillic (0xCD) and a
            # strict utf-8 reader thread dies on them, leaving `stdout = None` — the exact crash
            # the first run of this preflight produced. ASCII markers survive replacement chars.
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
        )
    except Exception:  # noqa: BLE001 — no listing, no preflight; the run is not blocked by it
        return []
    for line in (ps.stdout or "").splitlines():
        low = line.lower()
        # MATCH THE PROCESS, NOT THE SENTENCE. The old rule scanned the whole command line for the
        # words `godot` / `serve.py` / `neuropropertytrade`, so ANY wrapper that merely MENTIONED
        # one of them counted as a competing game: a monitoring command naming the gate script, a
        # shell printing the word in a `-match` pattern, a grep. Observed live - SG-10 answered
        # "another host was alive - the machine was competing with itself" in 1.09s and skipped a
        # perfectly quiet machine. What actually competes is a running game or a web host, i.e.
        # the EXECUTABLE: the shipped `NeuroPropertyTrade.exe`, a `Godot_*.exe` capture, or a
        # python running this tool's own sibling `serve.py`.
        if "fps_clean" in low:          # this check's own family (it is started from the same dir)
            continue
        name = low.split("|")[0].strip() if "|" in low else ""
        if name.endswith("neuropropertytrade.exe") or name.startswith("godot"):
            hits.append(line.strip())
        elif name.startswith("python") and "serve.py" in low:
            hits.append(line.strip())
    return hits


def main() -> int:
    strays = stray_processes()
    if strays:
        print("СТОП: на машине уже крутится игра или serve.py — замер мерил бы конкуренцию машины с собой:")
        for s in strays[:10]:
            print("   " + s)
        print("остановите лишние процессы и повторите: число без этого не значит ничего")
        return 1
    if not os.path.exists(EXE):
        print(f"нет {EXE} — сначала соберите билд (tools/build_all.sh)")
        return 1
    if not os.path.isdir(WEB_ROOT):
        print("нет build/current/web (или build/web) — сначала соберите web-экспорт")
        return 1

    # a stale perf.log from a previous run would be read as this run's numbers — remove it
    # (the game truncates on its first write anyway)
    os.makedirs(LOGDIR, exist_ok=True)
    perf_path = os.path.join(LOGDIR, "perf.log")
    if os.path.exists(perf_path):
        os.remove(perf_path)

    web_port, host_port = free_port(8160), free_port(9760)
    site = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "serve.py"), str(web_port),
         "--root", WEB_ROOT],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(2.0)

    host = subprocess.Popen(
        [EXE, "--resolution", "1440x900", "--rendering-driver", "opengl3", "--",
         "--autostart", "--smoke-drive", "--smoke-seats=2", "--remote-seats=1",
         "--seed=4242", "--server-bind=0.0.0.0", f"--server-port={host_port}",
         "--round-limit=25", "--perf", f"--log-dir={LOGDIR.replace(os.sep, '/')}"],
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
        # WHAT THE PAGE BELIEVED ABOUT ITSELF: 1 fps + hidden is throttling, not the game. Focus
        # is the sharper of the two - Chromium stops drawing for an OCCLUDED window while
        # `visibilityState` still says "visible" (measured: median=1 with `visible`, max=58: the
        # frame rate of a window nobody is looking at, published as a regression).
        vis = pg.evaluate("document.visibilityState")
        focused = bool(pg.evaluate("document.hasFocus()"))
        print(f"  (страница считала себя: {vis}; в фокусе: {focused})")
        b.close()

    host.terminate(); site.terminate()

    # the host's samples come from perf.log, not from its process output: the run log keeps only
    # events now. Read after the host stopped writing.
    if os.path.exists(perf_path):
        with open(perf_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("PERF fps="):
                    try:
                        host_fps.append(int(line.split("fps=")[1].split()[0]))
                    except (IndexError, ValueError):
                        pass

    print()
    print("=" * 68)
    print("  ЧИСТЫЙ ЗАМЕР (кроме этих двух процессов на машине ничего нет)")
    print("=" * 68)
    hp = [v for v in host_fps if v > 5]
    cf = [v for v in client_fps if v > 0]
    if hp:
        print(f"  ХОСТ .exe 1440x900 : median={median(hp):.0f} mean={mean(hp):.0f} min={min(hp)} max={max(hp)} n={len(hp)}")
    if not cf:
        print("  БРАУЗЕР: ни одного кадра — замер недействителен, повторите прогон")
        return 1
    med = median(cf)
    print(f"  БРАУЗЕР   1280x800 : median={med:.0f} mean={mean(cf):.0f} min={min(cf)} max={max(cf)} n={len(cf)}")
    # `1 fps + hidden` is throttling, not the game. The same reading must not be both published
    # AND acted upon: visibility decides whether a low number is a regression or an artifact.
    if med >= 30:
        print(f"  ==> FPS OK (браузер median={med:.0f} >= 30, порог регрессии)")
        return 0
    # A LOW NUMBER HAS TO EARN THE WORD "REGRESSION". A window nobody is looking at gets its
    # frames throttled to ~1/s while the samples also contain real ~50 fps bursts (the compositor
    # drew it while it was in front). A build that really regressed cannot produce 50 fps bursts
    # at all: it is slow in every sample. So: unfocused OR bimodal => the number measures the
    # desktop, not the build, and the gate SKIPs with that reason instead of reddening a healthy
    # release. (The earlier guard used `visibilityState` alone, which stays "visible" for an
    # occluded window - the very case it was written for.)
    peak = max(cf)
    # DID ANYTHING EVER DRAW? A window that never got composited reports a flat 1/s from the first
    # sample on (measured with occlusion detection switched off: median=1, peak=5). No build is
    # that slow - a real regression is slow, not absent - so this is a measurement about the
    # desktop, not about the game, and it must not be published as a regression either.
    opening = max(cf[:3]) if len(cf) >= 3 else peak
    if opening < 5:
        print(f"  ==> замер НЕДЕЙСТВИТЕЛЕН: median={med:.0f}, пик за первую секунду {opening} — "
              f"окно браузера так и не было нарисовано (его перекрыли)")
        return 2
    if focused is False:
        print(f"  ==> замер НЕДЕЙСТВИТЕЛЕН: median={med:.0f}, но окно браузера НЕ в фокусе — "
              f"это троттлинг композитора, не дефект сборки")
        return 2
    if peak >= 40:
        print(f"  ==> замер НЕДЕЙСТВИТЕЛЕН: median={med:.0f} при пике {peak} — окно рисовалось "
              f"рывками (его перекрыли); регрессия так не выглядит")
        return 2
    if vis == "visible":
        print(f"  ==> FPS REGRESSION: браузер median={med:.0f} < 30 (пик {peak}, окно в фокусе и видимо)")
        return 1
    print(f"  ==> замер НЕДЕЙСТВИТЕЛЕН: median={med:.0f}, но страница считала себя «{vis}» — троттлинг, не дефект")
    return 2


if __name__ == "__main__":
    sys.exit(main())
