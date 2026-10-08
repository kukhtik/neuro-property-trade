# Browser end-to-end: a real Chrome joins and plays a seat

`tools/ci/browser_seat_e2e.py` — the one step that proves the whole network story:
a REAL browser, running the WebGL export, joins a live match and its moves are
executed by the host's engine.

## Run

```sh
# needs: a WebGL export, Playwright+Chromium
tools/ci/godot_bin.sh --headless --path game --export-debug Web build/web/index.html
NPT_WEB=$PWD/build/web NPT_LOGS=$PWD/build/browser_seat \
  python tools/ci/browser_seat_e2e.py
```

Exit 0 when the browser joined AND at least one intent was ACCEPTED by the host.

## What it does

1. starts a Godot host with a REMOTE seat (`--proxy-remote=0`, so the seat is left to
   the wire) and reads its `ws://` address + seat token out of the role log;
2. serves `build/web` over HTTP with COOP/COEP (the wasm runtime needs cross-origin
   isolation);
3. opens `index.html?seat=<token>&host=ws://...` in headless Chromium;
4. counts, from the BROWSER CONSOLE: projections received, intents sent, and verdicts
   returned `ok=true`.

Measured: `joined=True, projections=3, intents=5, accepted=4/5`.

## Failures this probe found

**The client was mute and could not be seen to play.** `RemoteSession` emitted
`joined` / `state_received` / `verdict_received` and NOTHING was connected to any of
them — a browser joined and then did nothing. The signals existed, the handlers did
not. (Same class of defect as four earlier ones in this project: code present, not
wired.)

**Every diagnostic went to a file the browser cannot have.** The client logged through
`_mirror_log`, which writes to `--log-dir`; a page gets no such flag, so its log went
nowhere and the client looked dead. Once `print()` was used instead, the console showed
it had been playing all along. When a diagnostic shows nothing, first check the
diagnostic can be seen.

**Paths for a native process are not translated.** `NPT_LOGS=$PWD/build/...` (MSYS
style) reached Godot untranslated, the log was never written, and the probe sat waiting
for a file that could not appear. Pass `C:/...`-style paths to native tools.

## Limitation

This proves the CLIENT plays. The browser's own frame is still the cold layout (the
board is not drawn in it), which is tracked separately.
