#!/usr/bin/env python3
"""An SDK seat driven by a real language model (pipeline stall hunt, not a gate).

WHAT THIS IS FOR: HG-08 proves an SDK seat CAN play by answering every `actions/force` from a
fixed priority list. That says nothing about what happens when the player on the other side
thinks for 8 seconds, answers with prose, answers with an action that is not offered, or goes
silent - and the owner asked exactly that: "проверь пайплайны - есть ли затыки у иишек".

So this speaks the same websocket protocol and asks a MODEL what to do:
  context          -> remembered as the running narrative
  actions/force    -> prompt = narrative + query + offered action names
                      the model answers with one name; anything else is a measurable failure
Every decision is logged with its latency and its source:
  LLM   <action>  <sec>s   the model picked an OFFERED action
  FALLBACK <action> <sec>s the model timed out / answered junk - the seat still plays
  SILENT                   nothing was offered (the game is between decisions)

Run:  python tools/ci/llm_seat.py --model opencode/deepseek-v4.1-flash-free --timeout 240
Prints `LLM_PORT=<port>` first (the shell reads it), then one line per decision, then a summary.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mock_neuro_ws as ws  # the protocol plumbing (handshake, frames) - one copy of the truth

ACTION_PRIORITY = ws.ACTION_PRIORITY
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

_stats = {"answered": 0, "llm": 0, "fallback": 0, "silent": 0, "latency": []}


def log(msg: str) -> None:
    print("seat: %s" % msg, flush=True)


def strip_ansi(text: str) -> str:
    return ANSI.sub("", text)


def parse_model_reply(raw: str) -> str:
    """opencode --format json emits one JSON event per line; the answer lives in text parts.
    Falls back to the raw output (ANSI stripped), because a provider hiccup must not look like
    'the model chose nothing'."""
    parts: list[str] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        part = ev.get("part") if isinstance(ev, dict) else None
        if isinstance(part, dict) and part.get("type") == "text" and part.get("text"):
            parts.append(str(part["text"]))
        elif isinstance(ev, dict) and ev.get("type") == "text" and ev.get("text"):
            parts.append(str(ev["text"]))
    if parts:
        return " ".join(parts)
    return strip_ansi(raw)


def ask_model(model: str, narrative: str, query: str, offered: list[str], timeout: float) -> str:
    exe = shutil.which("opencode") or "opencode"
    # ONE LINE, ON PURPOSE. `opencode run` takes the message as an ARRAY of positional arguments:
    # a multi-line prompt was split and the model received only the opening sentence ("Сообщение
    # пустое — не приложены ни ход партии, ни вопрос..."). So the prompt is flattened to a single
    # line before it becomes one argument.
    flat = " ".join(
        "%s: %s" % (label, text)
        for label, text in (("Ход партии", narrative[-1800:]), ("Вопрос", query or "-"),
                            ("Доступные действия", ", ".join(offered)))
    ).replace("\r", " ").replace("\n", " ")
    prompt = (
        "Ты игрок в настольной экономической игре. %s. Ответь РОВНО одним названием действия из "
        "списка Доступные действия, без пояснений и без кавычек." % flat
    )
    prompt = re.sub(r"\s+", " ", prompt)
    try:
        # STDOUT GOES TO A FILE, NOT A PIPE. `subprocess.run(timeout=...)` on Windows kills the
        # child but then waits for the PIPE: opencode spawns node grandchildren that inherit it and
        # keep it open, so a 45 s cap measured 78 s and the seat blocked the match for a minute and
        # a half. A file handle has no such reader, so the timeout is a real bound.
        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False,
                                         encoding="utf-8", errors="replace") as tmp:
            path = tmp.name
        with open(path, "w", encoding="utf-8", errors="replace") as out:
            subprocess.run([exe, "run", "-m", model, prompt, "--format", "json"],
                           stdout=out, stderr=subprocess.STDOUT, timeout=timeout)
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
        os.unlink(path)
    except subprocess.TimeoutExpired:
        return ""
    except OSError as exc:
        log("model process failed: %s" % exc)
        return ""
    return parse_model_reply(raw)


def choose(model: str, narrative: str, query: str, offered: list[str], timeout: float) -> tuple[str, str]:
    """-> (action, source) where source is 'llm' or 'fallback'."""
    t0 = time.time()
    reply = ask_model(model, narrative, query, offered, timeout) if model else ""
    secs = time.time() - t0
    low = reply.lower()
    for name in offered:
        if name and re.search(r"(?<![a-z_])%s(?![a-z_])" % re.escape(name.lower()), low):
            _stats["latency"].append(secs)
            log("LLM   %s  %.1fs" % (name, secs))
            return name, "llm"
    fallback = next((n for n in ACTION_PRIORITY if n in offered), offered[0] if offered else "")
    log("FALLBACK %s  %.1fs  (model said: %r)" % (fallback, secs, reply.strip()[:90]))
    return fallback, "fallback"


def serve_one(sock, model: str, timeout: float, max_actions: int, silent: bool = False) -> None:
    ws.handshake(sock)
    ws.send_json(sock, {
        "command": "startup", "game": "llm-seat",
        "data": {"session": {"characterId": "llm-seat", "displayName": model.split("/")[-1]}},
    })
    narrative = ""
    while _stats["answered"] < max_actions:
        opcode, payload = ws.read_frame(sock)
        if opcode == 0x8:
            log("client closed")
            return
        if opcode not in (0x1, 0x2):
            continue
        try:
            msg = json.loads(payload.decode("utf-8"))
        except ValueError:
            continue
        command = str(msg.get("command", ""))
        data = msg.get("data", {}) if isinstance(msg.get("data"), dict) else {}
        if command == "context":
            text = str(data.get("message", ""))
            narrative = (narrative + "\n" + text)[-6000:]
            continue
        if command != "actions/force":
            continue
        offered = data.get("action_names", data.get("actions", []))
        if isinstance(offered, list) and offered and isinstance(offered[0], dict):
            offered = [str(a.get("name", "")) for a in offered]
        offered = [str(a) for a in offered if str(a)]
        if not offered:
            _stats["silent"] += 1
            log("SILENT (force carried no action names)")
            continue
        query = str(data.get("query", ""))
        log("<- force %s" % json.dumps(offered, ensure_ascii=False)[:140])
        if silent:
            # A DEAD BRIDGE: the connection is up, the seat never answers. This is the shape of a
            # crashed adapter, a provider that stopped streaming, or a model that hangs - the case
            # that used to freeze a match forever.
            _stats["silent"] += 1
            log("SILENT (dead bridge - deliberately no answer)")
            continue
        name, source = choose(model, narrative, query, offered, timeout)
        if name == "":
            _stats["silent"] += 1
            continue
        _stats["answered"] += 1
        _stats[source] += 1
        params = "{}"
        if name == "respond_trade":
            params = json.dumps({"accept": False})
        elif name == "bid_auction":
            params = json.dumps({"amount": 1})
        ws.send_json(sock, {
            "command": "action", "game": "llm-seat",
            "data": {"id": "llm-%d" % _stats["answered"], "name": name, "data": params},
        })
    log("action budget reached (%d) - the seat stops answering" % max_actions)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="opencode/deepseek-v4.1-flash-free")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--timeout", type=float, default=240.0, help="seconds to accept a client")
    ap.add_argument("--think", type=float, default=60.0, help="per-decision model timeout")
    ap.add_argument("--max-actions", type=int, default=40)
    ap.add_argument("--silent", action="store_true",
                    help="accept the connection and never answer (a dead bridge)")
    args = ap.parse_args()

    import socket
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", args.port))
    server.listen(4)
    print("LLM_PORT=%d" % server.getsockname()[1], flush=True)
    log("listening, model=%s, client timeout %.0fs, think timeout %.0fs"
        % (args.model, args.timeout, args.think))
    server.settimeout(1.0)
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        try:
            client, addr = server.accept()
        except socket.timeout:
            continue
        log("client from %s:%d" % addr)
        try:
            serve_one(client, args.model, args.think, args.max_actions, args.silent)
        except (ConnectionError, OSError) as exc:
            log("connection ended: %s" % exc)
        finally:
            client.close()
        break
    lat = _stats["latency"]
    print("SEAT_SUMMARY model=%s answered=%d llm=%d fallback=%d silent=%d median=%.1fs max=%.1fs"
          % (args.model, _stats["answered"], _stats["llm"], _stats["fallback"], _stats["silent"],
             sorted(lat)[len(lat) // 2] if lat else 0.0, max(lat) if lat else 0.0), flush=True)
    server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
