"""Does a REAL browser play a seat? The end-to-end question of stage 4/7.

Flow:
  1. start a Godot HOST process with a REMOTE seat; it prints its ws:// address and
     the seat token into its role log;
  2. serve the WebGL export over HTTP (COOP/COEP, which the wasm runtime needs);
  3. open it in headless Chromium with ?seat=<token>&host=<ws url>;
  4. read the browser console for the client's own JOIN line and for the host's
     greeting;
  5. assert an intent the browser sends actually reaches the host's engine.

This is the step that was never verified: earlier work proved the socket layer with a
native client (stages 1-4) and proved the export BOOTS, but never that the browser
joins a match.
"""
import http.server
import os
import pathlib
import re
import socketserver
import subprocess
import sys
import threading
import time

from playwright.sync_api import sync_playwright

PROJ = pathlib.Path(__file__).resolve().parents[2]
GAME = PROJ / "game"
# resolve every path the NATIVE Godot binary will receive: an MSYS-style path is not
# translated for a native process, so it would fail to write its log and the probe would
# sit waiting for a file that never appears.
WEB = pathlib.Path(os.environ.get("NPT_WEB", PROJ / "build" / "web")).resolve()
LOGDIR = pathlib.Path(os.environ.get("NPT_LOGS", PROJ / "build" / "browser_seat")).resolve()
GODOT = PROJ / ".tools" / "godot" / "Godot_v4.7.2-stable_win64.exe"
HTTP_PORT = 8777


def find_godot():
    if GODOT.exists():
        return str(GODOT)
    return "godot"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def end_headers(self):
        # Godot's wasm runtime wants cross-origin isolation
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *a):
        pass


def serve():
    with socketserver.TCPServer(("127.0.0.1", HTTP_PORT), Handler) as httpd:
        httpd.serve_forever()


def main():
    LOGDIR.mkdir(parents=True, exist_ok=True)
    print("web=%s" % WEB)
    print("logs=%s" % LOGDIR)
    if not (WEB / "index.html").exists():
        print("FAIL: no WebGL export at %s (set NPT_WEB)" % WEB)
        return 1
    for f in LOGDIR.glob("*.log"):
        f.unlink()

    port = 19100
    host = subprocess.Popen([
        find_godot(), "--path", str(GAME), "--headless",
        "--", "--admin", f"--server-port={port}", "--autostart", "--smoke-seats=3",
        "--smoke-drive", "--proxy-remote=0", f"--log-dir={LOGDIR.as_posix()}",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    log = LOGDIR / "admin.log"
    token = ""
    deadline = time.time() + 40
    while time.time() < deadline:
        if log.exists():
            text = log.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"SERVER seat=\d+ token=(\w+)", text)
            if m and f"SERVER ready ws://127.0.0.1:{port}" in text:
                token = m.group(1)
                break
        time.sleep(0.5)
    if not token:
        print("FAIL: the host never announced a seat token")
        host.kill()
        return 1
    print("host up on %d, seat token %s..." % (port, token[:6]))

    threading.Thread(target=serve, daemon=True).start()
    time.sleep(1.0)

    url = ("http://127.0.0.1:%d/index.html?seat=%s&host=ws://127.0.0.1:%d"
           % (HTTP_PORT, token, port))
    print("opening", url)

    ok = False
    with sync_playwright() as p:
        browser = p.chromium.launch(args=[
            "--use-gl=angle", "--use-angle=swiftshader",
            "--enable-unsafe-swiftshader", "--no-sandbox",
        ])
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        logs = []
        page.on("console", lambda m: logs.append(m.text))
        page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        # give the wasm bundle time to boot, join, and PLAY a few turns
        page.wait_for_timeout(60000)
        page.screenshot(path=str(LOGDIR / "browser_seat.png"))
        browser.close()

    joined = [l for l in logs if "JOIN" in l or "JOINED" in l]
    played = [l for l in logs if "PLAYED" in l or "VERDICT" in l]
    print("--- browser console (join-related) ---")
    for l in joined[:6]:
        print("   ", l)
    print("--- browser console (play-related) ---")
    for l in played[:10]:
        print("   ", l)
    if not played:
        print("    (the client never reported playing a turn)")
    print("--- ALL browser console lines ---")
    for l in logs[-40:]:
        print("   ", l)
    if not joined:
        print("--- last console lines ---")
        for l in logs[-12:]:
            print("   ", l)

    # the host mirrors its state; a seated client makes it progress
    hlog = (LOGDIR / "admin.log").read_text(encoding="utf-8", errors="replace")
    print("--- host log tail ---")
    for line in hlog.splitlines()[-6:]:
        print("   ", line)

    projs = [l for l in logs if l.startswith("PROJ")]
    joined_ok = any("JOINED" in l for l in logs)
    played = [l for l in logs if "PLAYED" in l]
    verdicts = [l for l in logs if "VERDICT" in l]
    accepted = [l for l in verdicts if "ok=true" in l]
    print("")
    print("joined      = %s" % joined_ok)
    print("projections = %d" % len(projs))
    print("intents sent= %d" % len(played))
    print("accepted    = %d of %d verdicts" % (len(accepted), len(verdicts)))
    ok = joined_ok and len(accepted) > 0
    host.kill()
    print("")
    print("RESULT:", "BROWSER JOINED" if ok else "browser did not join")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
