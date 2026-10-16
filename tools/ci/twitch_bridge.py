#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Twitch chat bridge for the CHAT seat (S2, docs/program.md P1.2). One process, stdlib only.

WHAT IT IS: the producer `seat_manager.push_chat` never had. Read the channel over IRC, turn a
viewer's message into a VOTE, keep the vote box honest (one vote per viewer per window, legal
actions only), and hand the result to the game as `{"t": "chat", "pid": N, "action": …, "params"}`.

WHAT IS PROVEN HERE (`--selftest`, runs with no network): the vote grammar, the anti-flood rule,
the vote arithmetic that decides the seat's move, and the wire frame it will send.
WHAT IS NOT PROVEN HERE: the live IRC socket. It cannot be exercised from this machine (no channel
token, and a real connection is not a check), so `--live` is marked untested in the plan instead of
being called done. The token is read from the environment and NEVER printed or logged.

Usage:
    python tools/ci/twitch_bridge.py --selftest
    python tools/ci/twitch_bridge.py --fake votes.txt --seat 2 --window 8
    python tools/ci/twitch_bridge.py --live --channel <name> --seat 2      # needs NPT_TWITCH_TOKEN
"""

import argparse
import collections
import json
import os
import re
import socket
import sys

IRC_HOST, IRC_PORT = "irc.chat.twitch.tv", 6667

# `!name` + optional integer argument. The game validates the action anyway; this only decides
# WHICH legal action a viewer is asking for, never whether it is legal.
VOTE = re.compile(r"^\s*!\s*([a-z_]+)\s*(-?\d+)?\s*$")
ACTIONS = ("roll", "buy", "pass", "bid", "build", "sell", "mortgage", "unmortgage",
           "pay", "card", "end_turn")


def parse_vote(text: str):
    """('bid', {'amount': 120}) / ('roll', {}) / None. An unknown `!word` is not a vote."""
    m = VOTE.match(text or "")
    if not m:
        return None
    action = m.group(1)
    if action not in ACTIONS:
        return None
    arg = m.group(2)
    if arg is None:
        return action, {}
    n = int(arg)
    if action == "bid":
        if n <= 0:
            return None                     # a non-positive bid is not a bid
        return action, {"amount": n}
    if action in ("build", "sell", "mortgage", "unmortgage"):
        return action, {"tile": n}
    return action, {"value": n}


class VoteBox:
    """The chat seat's inbox. One vote per viewer per WINDOW: a viewer who shouts ten times in one
    decision has ONE say, otherwise the loudest spammer decides the match."""

    def __init__(self, window: int = 8):
        self.window = window
        self._votes = []                    # [(viewer, action, params)]
        self._seen = {}

    def add(self, viewer: str, text: str, legal=None):
        vote = parse_vote(text)
        if vote is None:
            return None
        action, params = vote
        if legal is not None and action not in legal:
            return None                     # legal actions only: the engine would refuse anyway
        # anti-flood: the viewer's previous vote in THIS window is replaced, not added
        for i, (v, _a, _p) in enumerate(self._votes):
            if v == viewer:
                self._votes[i] = (viewer, action, params)
                self._seen[viewer] = self._seen.get(viewer, 0) + 1
                return (action, params, "replaced")
        self._votes.append((viewer, action, params))
        if len(self._votes) > self.window:
            self._votes.pop(0)
        return (action, params, "new")

    def winner(self):
        """Majority of the last `window` votes; ties go to the earliest vote of the leaders."""
        if not self._votes:
            return None
        counts = collections.Counter(a for _v, a, _p in self._votes)
        best = max(counts.values())
        for _v, action, params in self._votes:      # first-arrived among the leaders
            if counts[action] == best:
                return action, params
        return None

    def frame(self, pid: int):
        won = self.winner()
        if won is None:
            return None
        action, params = won
        return {"t": "chat", "pid": pid, "action": action, "params": params}

    def clear(self):
        self._votes.clear()
        self._seen.clear()


def selftest() -> int:
    fails, checks = [], 0

    def want(cond, why):
        nonlocal checks
        checks += 1
        if not cond:
            fails.append(why)

    want(parse_vote("!roll") == ("roll", {}), "`!roll` must parse")
    want(parse_vote(" !ROLL ") is None, "the grammar is case-sensitive by design (documented)")
    want(parse_vote("!bid 0") is None, "a non-positive bid must not be a vote")
    want(parse_vote("!bid 120") == ("bid", {"amount": 120}), "`!bid 120` must carry the sum")
    want(parse_vote("!buy") == ("buy", {}), "`!buy` must parse")
    want(parse_vote("!nonsense") is None, "an unknown command must not be a vote")
    want(parse_vote("hello chat") is None, "plain chat is not a vote")

    box = VoteBox(window=8)
    box.add("ann", "!roll")
    box.add("bob", "!roll")
    want(box.winner() == ("roll", {}), "two votes for the same action must win")

    box = VoteBox(window=8)
    box.add("ann", "!buy")
    for _ in range(9):
        box.add("spammer", "!roll")
    want(box.winner() == ("buy", {}),
         "one viewer shouting 9 times must not outvote one other viewer (anti-flood)")

    box = VoteBox(window=8)
    want(box.add("ann", "!roll", legal=["buy"]) is None, "a non-legal action must not enter the box")
    want(box.winner() is None, "an empty box must not invent a move")

    box = VoteBox(window=3)
    for i in range(5):
        box.add(f"v{i}", "!pass")
    want(box.winner() == ("pass", {}), "the window must stay playable after overflow")

    box = VoteBox()
    box.add("ann", "!bid 50")
    box.add("bob", "!bid 90")
    want(box.winner() == ("bid", {"amount": 50}),
         "on a tie the EARLIEST vote of the leaders wins (documented rule)")

    box = VoteBox()
    box.add("ann", "!roll")
    f = box.frame(2)
    want(f == {"t": "chat", "pid": 2, "action": "roll", "params": {}},
         "the wire frame must be a `chat` message for the seat's pid")

    print(f"==> BRIDGE SELFTEST {'PASSED' if not fails else 'FAILED'}: {checks} check(s), "
          f"{len(fails)} failure(s)")
    for f in fails:
        print("   FAIL " + f)
    return 0 if not fails else 1


def fake_run(path: str, seat: int, window: int, legal=None) -> int:
    """A file of `viewer: !command` lines stands in for the channel - the scenario's ingest."""
    box = VoteBox(window=window)
    accepted = 0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        viewer, text = line.split(":", 1)
        if box.add(viewer.strip(), text.strip(), legal):
            accepted += 1
    frame = box.frame(seat)
    print(f"ingest: {accepted} accepted vote(s) of {window} kept")
    print("frame: " + (json.dumps(frame) if frame else "none (no legal vote)"))
    return 0 if frame else 1


def live_run(channel: str, seat: int, window: int, host: str, port: int) -> int:
    """IRC reader. NOT exercised by the selftest and never called proven - see the docstring."""
    token = os.environ.get("NPT_TWITCH_TOKEN", "")
    if not token:
        print("FAIL: NPT_TWITCH_TOKEN is not set (the token is never read from the command line)")
        return 2
    nick = os.environ.get("NPT_TWITCH_NICK", channel)
    s = socket.create_connection((host, port), timeout=30)
    s.sendall(f"PASS {token}\r\nNICK {nick}\r\nJOIN #{channel}\r\n".encode())
    box = VoteBox(window=window)
    buf = b""
    while True:
        buf += s.recv(4096)
        while b"\r\n" in buf:
            raw, buf = buf.split(b"\r\n", 1)
            line = raw.decode("utf-8", "replace")
            if line.startswith("PING"):
                s.sendall(b"PONG :tmi.twitch.tv\r\n")
                continue
            m = re.match(r":(\w+)!\S+ PRIVMSG #\S+ :(.*)$", line)
            if not m:
                continue
            if box.add(m.group(1), m.group(2)):
                frame = box.frame(seat)
                if frame:
                    print(json.dumps(frame), flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--fake", default="")
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--channel", default="")
    ap.add_argument("--seat", type=int, default=0)
    ap.add_argument("--window", type=int, default=8)
    ap.add_argument("--host", default=IRC_HOST)
    ap.add_argument("--port", type=int, default=IRC_PORT)
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.fake:
        return fake_run(args.fake, args.seat, args.window)
    if args.live:
        if not args.channel:
            print("FAIL: --live needs --channel")
            return 2
        return live_run(args.channel, args.seat, args.window, args.host, args.port)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
