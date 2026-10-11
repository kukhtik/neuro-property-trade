#!/usr/bin/env python3
"""Serve the game: the landing page, the web build, and nothing else.

WHY A SERVER AND NOT JUST THE FILES: opening `index.html` from disk (`file://`) does not work —
the browser refuses to fetch the wasm and the pck across origins, and the game never boots. It has
to be served over HTTP.

WHY NO COOP/COEP HEADERS: the export is the `nothreads` template (verified in index.js:
`godot.web.template_release.wasm32.nothreads.wasm`), which needs no SharedArrayBuffer and
therefore no cross-origin isolation. That is what lets this run anywhere, including a plain LAN
host, with no header wrangling.

Run:  python tools/serve.py [port] [--root DIR]
      python tools/serve.py 8080
"""
import http.server
import os
import socket
import socketserver
import sys

PAGE = """<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Neuro Property Trade</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    background: #0b0613; color: #f7effd;
    font: 16px/1.5 system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
  }
  main { max-width: 620px; padding: 40px 28px; text-align: center; }
  h1 { font-size: 34px; margin: 0 0 6px; letter-spacing: .5px; }
  h1 span { color: #ff6fae; }
  p.lead { color: #a896c8; margin: 0 0 28px; }
  a.play {
    display: inline-block; padding: 16px 44px; border-radius: 10px;
    background: #ff6fae; color: #180a14; font-weight: 700; font-size: 18px;
    text-decoration: none; transition: transform .12s ease, background .12s ease;
  }
  a.play:hover { background: #ff8cbe; transform: translateY(-1px); }
  .card {
    margin-top: 30px; padding: 18px 20px; text-align: left;
    background: #130b1f; border: 1px solid #3b2a5e; border-radius: 12px;
  }
  .card h2 { font-size: 15px; margin: 0 0 10px; color: #5fe3ff; }
  .card ol { margin: 0; padding-left: 20px; color: #d9cfec; }
  .card li { margin: 6px 0; }
  code { background: #1b1230; padding: 2px 6px; border-radius: 5px; font-size: 13px; }
  footer { margin-top: 26px; color: #6f6288; font-size: 13px; }
</style>
</head>
<body>
<main>
  <h1>Neuro <span>Property Trade</span></h1>
  <p class="lead">Настольная игра с механикой Monopoly. Оригинальное оформление.</p>
  <a class="play" href="index.html">Играть</a>

  <div class="card">
    <h2>Как играть с друзьями</h2>
    <ol>
      <li>Один человек — ведущий. Он запускает игру и нажимает
          <code>Создать партию для друзей</code>.</li>
      <li>Игра показывает <b>ссылку для каждого друга</b> — по одной на игрока.</li>
      <li>Друг открывает свою ссылку здесь, в браузере, и сразу попадает в игру.
          Ничего скачивать не нужно.</li>
    </ol>
  </div>

  <footer>Код: MIT · контент оригинальный, торговых марок Hasbro нет</footer>
</main>
</body>
</html>
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # The landing page lives at /; everything else is served from the directory.
        if self.path in ("/", "/index.htm"):
            body = PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            # A game build changes between runs; never let a browser serve a stale wasm.
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

    def log_message(self, fmt, *args):
        # keep the console readable: one line per real request, no per-file noise
        sys.stderr.write("%s\n" % (fmt % args))


def lan_address() -> str:
    """The address another machine should use — not 127.0.0.1, which only works locally."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))          # no packet is sent; this just picks the route
        addr = s.getsockname()[0]
        s.close()
        return addr
    except OSError:
        return "127.0.0.1"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    port = int(args[0]) if args else 8080

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for i, a in enumerate(sys.argv):
        if a == "--root" and i + 1 < len(sys.argv):
            root = sys.argv[i + 1]

    # The build may sit at the root (`--root site`, where index.html is directly inside) or under
    # a `game/` subdirectory. Checking only the second shape made every caller that passed the
    # build directory itself fail with "no web build".
    if os.path.isfile(os.path.join(root, "index.html")):
        pass
    elif os.path.isfile(os.path.join(root, "game", "index.html")):
        root = os.path.join(root, "game")
    else:
        print("serve: no web build under %s (no index.html)" % root, file=sys.stderr)
        print("       build it with: tools/build_all.sh", file=sys.stderr)
        return 1

    os.chdir(root)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", port), Handler) as httpd:
        host = lan_address()
        print("=== Neuro Property Trade — сервер игры ===")
        print("Страница:  http://%s:%d/" % (host, port))
        print("Игра:      http://%s:%d/game/index.html" % (host, port))
        print("Остановить: Ctrl+C")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nостановлено")
    return 0


if __name__ == "__main__":
    sys.exit(main())
