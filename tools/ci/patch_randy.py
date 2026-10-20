#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Adjust the fetched upstream "Randy" server for use as a test fixture.

Two changes, both minimal, both needed by tools/ci/gates/randy01_gate.sh:

1. The ports become environment variables, so the gate can pick FREE ones instead of
   colliding with a stale instance. A collision makes our server die with EADDRINUSE
   while the log the gate then reads belongs to the stranger - a gate that measures
   somebody else's server is worse than no gate.

2. The log loses its ANSI colour. util.inspect colours the strings it prints, and
   "command: 'actions/register'" with a colour escape inside the quotes does not match
   the gate's pattern - the gate would count zero, and a gate that counts zero must
   fail rather than pass.

Usage: py -3.12 patch_randy.py <path-to-index.ts>
"""
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: patch_randy.py <index.ts>")
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8", newline="") as fh:
        text = fh.read()

    replacements = [
        ("app.listen(1337);", "app.listen(Number(process.env.HTTP_PORT || 1337));"),
        ("new WebSocketServer({port: 8000});",
         "new WebSocketServer({port: Number(process.env.PORT || 8000)});"),
        ("util.inspect(message, false, null, true)", "util.inspect(message, false, null, false)"),
        ("util.inspect(msg, false, null, true)", "util.inspect(msg, false, null, false)"),
    ]
    changed = 0
    for old, new in replacements:
        if old in text:
            text = text.replace(old, new, 1)
            changed += 1
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    print("patched %d spot(s) in %s" % (changed, path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
