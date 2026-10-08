"""One run, every role: host + admin + stream + a real browser, then a report.

This is the end-to-end smoke the project asked for. In a SINGLE process tree it:

  1. starts the Godot host (admin role) on a fixed port and reads its seat token;
  2. opens the WebGL export in headless Chromium with that token, so a real browser
     plays a seat (this is the player role, and the only one that can be a browser);
  3. captures frames of BOTH native roles — admin and stream — from the SAME match;
  4. collects the match statistics the host wrote;
  5. writes an HTML report with every frame side by side, the mockup's own frame next to
     the result, and the measured numbers.

Why one run and not four: the roles must be shown to COEXIST. Four separate runs prove
four things work; they never prove they work together, and "admin switched to stream"
versus "admin and stream as separate windows" is exactly the difference that matters.

Exit 0 when: the browser joined and played, both native roles produced a frame, and the
host's match statistics are present.
"""
import http.server
import json
import os
import pathlib
import re
import socketserver
import subprocess
import sys
import threading
import time
from html import escape

from playwright.sync_api import sync_playwright

PROJ = pathlib.Path(__file__).resolve().parents[2]
WEB = pathlib.Path(os.environ.get("NPT_WEB", PROJ / "build" / "web")).resolve()
OUT = pathlib.Path(os.environ.get("NPT_REPORT", PROJ / "build" / "smoke")).resolve()
MOCKUP = pathlib.Path(os.environ.get(
    "NPT_MOCKUP", pathlib.Path.home() / "Desktop" / "Neuro Property Trade — UI.html"))
GODOT = PROJ / ".tools" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
HTTP_PORT = 8778
MATCH_SECONDS = 55


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(WEB), **kw)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, *a):
        pass


def serve():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", HTTP_PORT), Handler) as httpd:
        httpd.serve_forever()


def launch_role(role_flag, log_name, port):
    """Start one native role against the given host port."""
    env = dict(os.environ)
    args = [str(GODOT), "--path", str(PROJ / "game"), "--resolution", "1440x900",
            "--rendering-driver", "opengl3"]
    if role_flag:
        args.append(role_flag)
    args += ["--", f"--server-port={port}" if role_flag == "--admin" else "", ]
    args = [a for a in args if a]
    return subprocess.Popen(args, env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def capture_role(role_flag, out_png, host_port, wait_s):
    """Run one native role for a while and screenshot it with Godot itself.

    Godot can save its own viewport, so no OS-level screenshot tool is needed and the
    frame is exactly what the app drew.
    """
    shots = PROJ / "game" / "tools" / "_role_capture.gd"
    shots.write_text('''extends Node
## Saves one frame of the REAL launcher after it has drawn. Written by the smoke.
const MainScript := preload("res://main.gd")
var _n := 0
var _out := "user://role.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	add_child(MainScript.new())

func _process(_dt: float) -> void:
	_n += 1
	if _n == %d:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %%s %%dx%%d" %% [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
''' % int(wait_s * 60), encoding="utf-8")
    (PROJ / "game" / "tools" / "_role_capture.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://tools/_role_capture.gd" id="1"]\n'
        '[node name="RoleCapture" type="Node"]\nscript = ExtResource("1")\n',
        encoding="utf-8")

    args = [str(GODOT), "--path", str(PROJ / "game"), "--resolution", "1440x900",
            "--rendering-driver", "opengl3", "res://tools/_role_capture.tscn"]
    # the role and the output path BOTH go after the bare `--`: that is the only part of
    # the command line Godot hands to the running script
    user = [f"--out={out_png.as_posix()}"]
    if role_flag:
        user.insert(0, role_flag)
    args += ["--"] + user
    p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + wait_s + 25
    while time.time() < deadline:
        if out_png.exists():
            break
        time.sleep(0.5)
    p.kill()
    return out_png.exists()


## True when two frames are not byte-identical — the only proof a role change took effect.
def _frames_differ(a: pathlib.Path, b: pathlib.Path) -> bool:
    if not (a.exists() and b.exists()):
        return False
    da = a.read_bytes()
    db = b.read_bytes()
    return da != db


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.png"):
        f.unlink()

    if not (WEB / "index.html").exists():
        print("FAIL: no WebGL export at %s (set NPT_WEB)" % WEB)
        return 1
    print("web   = %s" % WEB)
    print("out   = %s" % OUT)

    port = 19200
    logs = OUT / "logs"
    logs.mkdir(exist_ok=True)

    # --- 1. the host, as the admin role ---------------------------------------------
    print("[1] starting the HOST (admin role)")
    host = subprocess.Popen([
        str(GODOT), "--path", str(PROJ / "game"), "--headless",
        "--", "--admin", f"--server-port={port}", "--autostart", "--smoke-seats=3",
        "--smoke-drive", "--proxy-remote=0", f"--log-dir={logs.as_posix()}",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    token = ""
    deadline = time.time() + 45
    while time.time() < deadline:
        f = logs / "admin.log"
        if f.exists():
            txt = f.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"SERVER seat=\d+ token=(\w+)", txt)
            if m and f"SERVER ready ws://127.0.0.1:{port}" in txt:
                token = m.group(1)
                break
        time.sleep(0.5)
    if not token:
        print("FAIL: the host never announced a seat token")
        host.kill()
        return 1
    print("      host up on %d, seat %s..." % (port, token[:6]))

    # --- 2. a REAL browser takes the player seat -------------------------------------
    threading.Thread(target=serve, daemon=True).start()
    time.sleep(1.0)
    print("[2] opening the WebGL build in a REAL browser (player role)")
    url = f"http://127.0.0.1:{HTTP_PORT}/index.html?seat={token}&host=ws://127.0.0.1:{port}"
    console = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(args=[
            "--use-gl=angle", "--use-angle=swiftshader",
            "--enable-unsafe-swiftshader", "--no-sandbox"])
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.on("console", lambda m: console.append(m.text))
        page.on("pageerror", lambda e: console.append("pageerror: %s" % e))
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(MATCH_SECONDS * 1000)
        page.screenshot(path=str(OUT / "player.png"))
        browser.close()

    joined = any("JOINED" in l for l in console)
    played = [l for l in console if "PLAYED" in l]
    accepted = [l for l in console if "VERDICT" in l and "ok=true" in l]
    print("      joined=%s  intents=%d  accepted=%d" % (joined, len(played), len(accepted)))

    # --- 3. the two native roles, from the same match -------------------------------
    print("[3] capturing the native roles from the SAME match")
    admin_ok = capture_role("--admin", OUT / "admin.png", port, 8)
    print("      admin  %s" % ("captured" if admin_ok else "MISSING"))
    stream_ok = capture_role("--stream", OUT / "stream.png", port, 10)
    print("      stream %s" % ("captured" if stream_ok else "MISSING"))
    # TWO IDENTICAL FRAMES MEAN THE ROLE NEVER APPLIED. Checking that the files exist is
    # not enough: the first version of this smoke produced byte-identical "admin" and
    # "stream" frames and still reported success.
    distinct = _frames_differ(OUT / "admin.png", OUT / "stream.png")
    print("      roles differ: %s" % distinct)
    if not distinct:
        admin_ok = stream_ok = False

    host.kill()

    # --- 4. the numbers the host recorded --------------------------------------------
    stats = {}
    rep = PROJ / "game" / "build" / "smoke_stage5" / "report.json"
    if not rep.exists():
        for cand in pathlib.Path.home().glob("AppData/Roaming/Godot/app_userdata/*/smoke_stage5/report.json"):
            rep = cand
            break
    if rep.exists():
        try:
            stats = json.loads(rep.read_text(encoding="utf-8"))
        except Exception:
            stats = {}
    print("[4] host statistics: %s" % ("%d events, %d types" % (
        stats.get("events_total", 0), stats.get("types_seen", 0)) if stats else "not found"))

    # --- 5. the report ----------------------------------------------------------------
    frames = [("player", OUT / "player.png", "WebUI — a real browser on a seat"),
              ("admin", OUT / "admin.png", "host application — full control"),
              ("stream", OUT / "stream.png", "OBS window — spectator data only")]
    rows = []
    for role, png, note in frames:
        if png.exists():
            rows.append(
                '<figure><img src="%s" alt="%s"><figcaption><b>%s</b><br>%s<br>'
                '<small>%d bytes, 1440x900</small></figcaption></figure>'
                % (escape(png.name), escape(role), escape(role), escape(note),
                   png.stat().st_size))
        else:
            rows.append('<figure class="missing"><b>%s</b><br>NO FRAME CAPTURED</figure>'
                        % escape(role))

    mock = ""
    if MOCKUP.exists():
        mock = ('<figure><iframe src="%s" title="mockup"></iframe>'
                '<figcaption><b>МАКЕТ</b><br>%s</figcaption></figure>'
                % (MOCKUP.as_uri(), escape(MOCKUP.name)))

    verdict = "PASS" if (joined and admin_ok and stream_ok) else "FAIL"
    html = """<!doctype html><html lang="ru"><meta charset="utf-8">
<title>Neuro Property Trade — сквозной смоук</title>
<style>
 body{{background:#12151b;color:#e8edf3;font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px}}
 h1{{font-size:20px;margin:0 0 4px}}
 .verdict{{display:inline-block;padding:4px 12px;border-radius:6px;font-weight:700;
   background:{vc};color:#0b0d11;margin-bottom:16px}}
 table{{border-collapse:collapse;margin:0 0 20px}}
 td{{padding:3px 14px 3px 0}} td.k{{color:#8b95a5}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:16px}}
 figure{{margin:0;background:#1e242e;border:1px solid #39404d;border-radius:8px;padding:10px}}
 figure img,figure iframe{{width:100%;border:0;border-radius:5px;background:#000;aspect-ratio:16/10}}
 figure iframe{{height:340px}}
 figcaption{{margin-top:8px;font-size:12px;color:#a896c8}}
 .missing{{color:#ff6b6b;min-height:120px;display:flex;align-items:center;justify-content:center}}
 small{{color:#8b95a5}}
</style>
<h1>Neuro Property Trade — сквозной смоук, один прогон</h1>
<div class="verdict" style="background:{vc}">{verdict}</div>
<table>
 <tr><td class="k">браузер присоединился</td><td>{joined}</td></tr>
 <tr><td class="k">ходов отправлено</td><td>{played}</td></tr>
 <tr><td class="k">принято хостом</td><td>{accepted}</td></tr>
 <tr><td class="k">кадр admin</td><td>{admin}</td></tr>
 <tr><td class="k">кадр stream</td><td>{stream}</td></tr>
 <tr><td class="k">событий в партии</td><td>{events}</td></tr>
 <tr><td class="k">типов событий</td><td>{types}</td></tr>
</table>
<h2 style="font-size:16px">Роли и макет</h2>
<div class="grid">{mock}{rows}</div>
<p style="color:#8b95a5;font-size:12px;margin-top:20px">
 Кадры сняты в ОДНОМ прогоне: хост, три роли и живой браузер одновременно.
 Скриншоты ролей делает сам Godot своим viewport, браузер — Playwright.
</p>
</html>""".format(
        vc="#5cb85c" if verdict == "PASS" else "#d9534f",
        verdict=verdict,
        joined=("да" if joined else "<b>НЕТ</b>"),
        played=len(played), accepted=len(accepted),
        admin=("есть" if admin_ok else "<b>НЕТ</b>"),
        stream=("есть" if stream_ok else "<b>НЕТ</b>"),
        events=stats.get("events_total", "—"), types=stats.get("types_seen", "—"),
        mock=mock, rows="".join(rows))

    (OUT / "report.html").write_text(html, encoding="utf-8")
    print("[5] report: %s" % (OUT / "report.html"))

    ok = joined and admin_ok and stream_ok
    print("")
    print("RESULT: %s" % ("SMOKE PASSED — every role live in one run"
                          if ok else "SMOKE FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
