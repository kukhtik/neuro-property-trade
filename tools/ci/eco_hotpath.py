#!/usr/bin/env python3
"""ECO-02 - the hot path must not allocate, search the tree, or churn the scene.

Why this exists: the owner asked (23.10) for the frugality of 2000-era games, where
nothing is created in a frame. The cheap, honest first measurement of that is STATIC:
inside `_process`, `_draw` and `_physics_process` there must be no allocations, no tree
lookups, no string building and no scene churn.

Why a RATCHET and not "zero": the product today has some of these, and a gate that says
"zero" would be red from the first day and get disabled. A ratchet fails when the count
GROWS above the recorded baseline, and lets it shrink. The baseline is a file, so the
number is reviewable in a diff.

Parsing: GDScript blocks are taken by INDENTATION (a block ends when the indentation
decreases), not by a regex over the whole file. The taste gate's regex missed 59 calls
because it looked for "not preceded by a comma"; a real block parser does not have that
class of blind spot. Comments and strings are stripped before the scan.

Verdict is read from the tool's exit code AND its last line, never from silence.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
GAME = REPO / "game"
BASELINE = REPO / "tools" / "ci" / "eco_hotpath_baseline.txt"

HOT_FUNCS = ("_process", "_draw", "_physics_process")

# (pattern, what it costs). Each entry must be something a 2000-era game did NOT do
# in a frame.
BANS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\bnew\s*\("), "allocation: a new object in the frame"),
    (re.compile(r"\bstr\s*\("), "allocation: a string built in the frame"),
    (re.compile(r"%\s*[\[(]"), "allocation: string formatting in the frame"),
    (re.compile(r"\bget_node(_or_null)?\s*\("), "tree lookup in the frame"),
    (re.compile(r"\bfind_child\w*\s*\("), "tree search in the frame"),
    (re.compile(r"\badd_child\w*\s*\("), "scene churn in the frame"),
    (re.compile(r"\bremove_child\w*\s*\("), "scene churn in the frame"),
    (re.compile(r"\bqueue_free\s*\("), "scene churn in the frame"),
    (re.compile(r"\.connect\s*\("), "reconnecting signals in the frame"),
    (re.compile(r"\.disconnect\s*\("), "reconnecting signals in the frame"),
    (re.compile(r"\bget_children\s*\("), "tree walk in the frame"),
)

# A literal array/dict is only a smell when it is built in the frame; `[]` used for
# slicing or as an empty argument is rare, so we look for an assignment or an append.
ARRAY_ALLOC = re.compile(r"(=\s*\[|=\s*\{|\.append\s*\(|\.push_back\s*\(|= \[\]|= \{\})")


def strip_noise(line: str) -> str:
    """Remove comments and string literals so a mention inside text does not count."""
    out = []
    in_str = False
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                in_str = False
            i += 1
            continue
        if ch in "\"'":
            in_str = True
            quote = ch
            i += 1
            continue
        if ch == "#":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def hot_blocks(text: str) -> list[tuple[str, int]]:
    """Return (function name, line number) for each hot function, and the block body."""
    lines = text.splitlines()
    blocks: list[tuple[str, int, list[tuple[int, str]]]] = []
    i = 0
    while i < len(lines):
        m = re.match(r"^(\t*)func\s+(\w+)\s*\(", lines[i])
        if not m:
            i += 1
            continue
        indent, name = m.group(1), m.group(2)
        body: list[tuple[int, str]] = []
        j = i + 1
        while j < len(lines):
            raw = lines[j]
            if raw.strip() == "":
                body.append((j + 1, raw))
                j += 1
                continue
            cur = re.match(r"^(\t*)", raw).group(1)
            if len(cur) <= len(indent):
                break
            body.append((j + 1, raw))
            j += 1
        if name in HOT_FUNCS:
            blocks.append((name, i + 1, body))
        i = j
    return [(n, ln, b) for (n, ln, b) in blocks]


def scan() -> list[dict[str, object]]:
    """Scan the PRODUCT's hot path.

    CI tooling (game/tools, game/tests) is deliberately NOT scanned: those scripts run
    in a headless probe, never in a frame of the game, and they are not even shipped
    (the export excludes them). Measuring them would drown the product's number in
    noise - and a number that is mostly noise is a number nobody acts on.
    """
    hits: list[dict[str, object]] = []
    for path in sorted(GAME.rglob("*.gd")):
        rel = path.relative_to(REPO).as_posix()
        if rel.startswith("game/tools/") or rel.startswith("game/tests/"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for fname, _flineno, body in hot_blocks(text):
            for lineno, raw in body:
                code = strip_noise(raw)
                if not code.strip():
                    continue
                for pattern, why in BANS:
                    if pattern.search(code):
                        hits.append(
                            {
                                "file": rel,
                                "func": fname,
                                "line": lineno,
                                "why": why,
                                "code": raw.strip()[:160],
                            }
                        )
                if ARRAY_ALLOC.search(code):
                    hits.append(
                        {
                            "file": rel,
                            "func": fname,
                            "line": lineno,
                            "why": "allocation: a collection is built in the frame",
                            "code": raw.strip()[:160],
                        }
                    )
    return hits


def baseline_count() -> int:
    """The ratchet limit: the FIRST non-comment, non-empty line, parsed as an integer.

    Comments are skipped on purpose: the file explains itself, and a number mentioned in
    a comment ("3 -> 0") must never be read as the limit - that is exactly how a ratchet
    silently stops ratcheting.
    """
    if not BASELINE.exists():
        return -1
    for raw in BASELINE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.fullmatch(r"(\d+)", line)
        return int(m.group(1)) if m else -1
    return -1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--negative", action="store_true", help="inject a violation and expect a red verdict")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    hits = scan()
    limit = baseline_count()

    if args.negative:
        # The negative must FAIL THE GATE. So it is not enough to print a violation: the
        # gate's own number must move. We measure the same thing with one extra line.
        hits.append(
            {
                "file": "game/ui/_negative_probe.gd",
                "func": "_process",
                "line": 1,
                "why": "negative: allocation in the frame",
                "code": "var _x = Foo.new()",
            }
        )

    by_file: dict[str, int] = {}
    for h in hits:
        by_file[str(h["file"])] = by_file.get(str(h["file"]), 0) + 1

    if args.json:
        print(json.dumps({"hits": len(hits), "limit": limit, "by_file": by_file}, ensure_ascii=False))
        return 0

    print(f"ECO-02 hot path scan: {len(hits)} violation(s); ratchet limit {limit}")
    for f, n in sorted(by_file.items(), key=lambda kv: -kv[1])[:15]:
        print(f"  {n:3d}  {f}")
    for h in hits[:12]:
        print(f"    {h['file']}:{h['line']} [{h['func']}] {h['why']} :: {h['code']}")

    if limit < 0:
        print("==> ECO-02 FAILED: no baseline file; create tools/ci/eco_hotpath_baseline.txt")
        return 1
    if len(hits) > limit:
        print(
            f"==> ECO-02 FAILED: {len(hits)} violation(s) in the hot path, "
            f"the ratchet allows {limit}. New garbage in the frame is not allowed; "
            f"if a violation was removed, lower the baseline."
        )
        return 1
    print(f"==> ECO-02 PASSED ({len(hits)} hot-path violation(s), ratchet limit {limit})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
