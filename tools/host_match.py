#!/usr/bin/env python3
"""Host a match AND serve the game, then print one ready-to-send link per friend.

WHAT THIS REPLACES: hosting was two windows, a game flag, a web server, and then copying address
and token pairs out of a console by hand — and the link had to be assembled by the host from parts
that appear in different places. Here it is one thing to run and one link per friend to forward.

THE ORDER MATTERS. The game prints its addresses and seat tokens to stdout only after its server
binds, and the site must already be listening before a friend opens a link to it, so this starts
the site first, waits for the game to announce itself, and only then builds the links.

Run:  python host_match.py [friends] [--port N] [--web-port N]
      python host_match.py 3
"""
from __future__ import annotations

import argparse
import os
import re
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, "Neuro Property Trade.exe")
SITE = os.path.join(HERE, "site")

ADDR_RE = re.compile(r"SERVER ready (ws://[\d.]+:\d+)")
TOKEN_RE = re.compile(r"SERVER seat=(\d+) token=([0-9a-f]+)")


def lan_address() -> str:
    """The address to hand to friends. Not 127.0.0.1 — that only works on this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))     # no packet is sent; this only selects a route
        addr = s.getsockname()[0]
        s.close()
        return addr
    except OSError:
        return "127.0.0.1"


def start_site(port: int, quiet: bool = True) -> subprocess.Popen:
    """Serve `site/` so friends can open a link. The export is the nothreads template, so no
    COOP/COEP headers are needed — see tools/serve.py."""
    serve = os.path.join(HERE, "serve.py")
    out = subprocess.DEVNULL if quiet else None
    return subprocess.Popen(
        [sys.executable, serve, str(port), "--root", SITE],
        stdout=out, stderr=out,
    )


def wait_for(proc: subprocess.Popen, pattern: re.Pattern, timeout: float) -> str | None:
    """Read the child's stdout until `pattern` matches. Returns the last match, or None."""
    deadline = time.time() + timeout
    found: str | None = None
    while time.time() < deadline:
        line = proc.stdout.readline() if proc.stdout else ""
        if not line:
            if proc.poll() is not None:
                break
            time.sleep(0.05)
            continue
        line = line.rstrip()
        m = pattern.search(line)
        if m:
            found = m.group(0)
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description="Host a Neuro Property Trade match for friends.")
    ap.add_argument("friends", nargs="?", type=int, default=3, help="how many friends join (default 3)")
    ap.add_argument("--port", type=int, default=9080, help="game server port (default 9080)")
    ap.add_argument("--web-port", type=int, default=8080, help="site port (default 8080)")
    args = ap.parse_args()

    if not os.path.isfile(EXE):
        print("Не нахожу игру рядом с этим файлом:", EXE, file=sys.stderr)
        print("host_match.py должен лежать в одной папке с «Neuro Property Trade.exe».", file=sys.stderr)
        return 1
    if not os.path.isdir(SITE):
        print("Не нахожу папку site/ рядом с этим файлом.", file=sys.stderr)
        return 1
    if args.friends < 1:
        print("Друзей должно быть хотя бы один.", file=sys.stderr)
        return 1

    host = lan_address()
    seats = args.friends + 1

    print("=" * 72)
    print("  NEURO PROPERTY TRADE — партия для друзей")
    print("=" * 72)
    print(f"  Друзей: {args.friends}   Всего мест: {seats}")
    print()

    site = start_site(args.web_port)
    time.sleep(1.5)
    if site.poll() is not None:
        print(f"Не смог запустить раздачу сайта (порт {args.web_port} занят?).", file=sys.stderr)
        return 1
    print(f"  Сайт раздаётся:  http://{host}:{args.web_port}/")

    game = subprocess.Popen(
        [EXE, "--",
         "--autostart", "--smoke-drive",
         f"--smoke-seats={seats}", f"--remote-seats={args.friends}",
         "--server-bind=0.0.0.0", f"--server-port={args.port}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
        cwd=HERE,
    )

    # Collect everything the game announces, with a hard time limit so a silent failure to bind
    # does not leave the host staring at a blank prompt.
    tokens: dict[int, str] = {}
    addr: str | None = None
    deadline = time.time() + 30.0

    def reader() -> None:
        nonlocal addr
        for line in game.stdout:            # type: ignore[union-attr]
            line = line.rstrip()
            m = TOKEN_RE.search(line)
            if m:
                tokens[int(m.group(1))] = m.group(2)
                continue
            m = ADDR_RE.search(line)
            if m:
                addr = m.group(1)

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    while time.time() < deadline and (addr is None or len(tokens) < args.friends):
        if game.poll() is not None:
            break
        time.sleep(0.2)

    if addr is None or len(tokens) < args.friends:
        print()
        print("Игра не объявила адрес и токены за 30 секунд.", file=sys.stderr)
        if game.poll() is not None:
            print(f"Игра завершилась с кодом {game.returncode}.", file=sys.stderr)
        else:
            print("Порт занят другой программой? Попробуйте --port 9180.", file=sys.stderr)
        game.terminate()
        site.terminate()
        return 1

    # WHERE THE GAME ACTUALLY IS. The build may sit at the site root or under `game/`, and a link
    # pointing at a directory that does not exist gives the friend a 404 — which is exactly what
    # happened the first time (dist/site holds the build at its root, the link said /game/).
    if os.path.isfile(os.path.join(SITE, "game", "index.html")):
        web = f"http://{host}:{args.web_port}/game/index.html"
    else:
        web = f"http://{host}:{args.web_port}/index.html"
    print(f"  Игра слушает:    {addr}")
    print()
    print("=" * 72)
    print("  ОТПРАВЬТЕ КАЖДОМУ ДРУГУ ЕГО ССЫЛКУ")
    print("=" * 72)
    for i, pid in enumerate(sorted(tokens)):
        link = f"{web}?seat={tokens[pid]}&host={addr}"
        print(f"  Друг {i + 1}:")
        print(f"    {link}")
        print()
    print("=" * 72)
    print("  Ссылки личные: кто получил — займёт это место. Пересылайте лично.")
    print("  Друг открывает ссылку в браузере и сразу играет. Устанавливать нечего.")
    print("  Вы играете в открывшемся окне игры.")
    print("  Остановить: Ctrl+C или закройте это окно.")
    print("=" * 72)

    try:
        game.wait()
    except KeyboardInterrupt:
        pass
    finally:
        game.terminate()
        site.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
