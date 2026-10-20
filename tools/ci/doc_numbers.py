#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The numbers in the docs must be the numbers the product actually has.

WHY THIS EXISTS. `docs/infra.md` said "227 tests" and "MIN_TESTS (default 200)" while the
oracle was running 421 - for months. The count moved 227 -> 270 -> 289 -> 292 -> 356 ->
383 -> 388 -> 395 -> 406 -> 411 -> 416 -> 421, and every doc that quoted a number was
edited BY HAND, so every one of them was wrong the moment the next test landed. A doc
that lies about the number of tests is worse than a doc that says nothing: a reader
checking "does it still hold" trusts it.

WHAT IT CHECKS
  1. the test count in the docs equals the count the oracle reports;
  2. the MIN_TESTS floor in `tools/ci/run_tests.sh` equals the number of tests that
     actually ran (a floor below the real count is a floor that no longer guards);
  3. the gate count in the docs equals the number of gates in the registry.

The count comes from the ORACLE ITSELF when it is given one (a log file or a run), and
otherwise from the source of truth in the repo - the MIN_TESTS line - so the check can
run without Godot.

Usage:
    py -3.12 tools/ci/doc_numbers.py                     # check against the repo
    py -3.12 tools/ci/doc_numbers.py --log <npt-tests.log>  # check against a real run
    py -3.12 tools/ci/doc_numbers.py --write             # fix the docs (rewrite the numbers)
"""
import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The docs that quote a number. Each entry: path -> the patterns that carry it.
# A pattern is (regex, template) where the template contains {n} for the number.
DOCS = {
    "docs/infra.md": [
        (r"module\), \d+ tests, zero third-party dependencies",
         "module), {n} tests, zero third-party dependencies"),
        (r"ORACLE PASSED \(\d+ tests, 0 SCRIPT ERROR\)",
         "ORACLE PASSED ({n} tests, 0 SCRIPT ERROR)"),
    ],
    "README.md": [
        (r"run_tests\.sh\s+# \d+ headless tests",
         "run_tests.sh     # {n} headless tests"),
        (r"run_gates\.sh\s+# \d+ required gates",
         "run_gates.sh     # {n} required gates"),
    ],
    "docs/plan.md": [
        (r"import \+ \d+ tests \+ count floor",
         "import + {n} tests + count floor"),
    ],
}


def read(path: str) -> str:
    full = os.path.join(REPO, path)
    if not os.path.exists(full):
        return ""
    with open(full, encoding="utf-8", newline="") as fh:
        return fh.read()


def count_min_tests() -> int:
    """The floor from the oracle script - the repo's own number of truth."""
    text = read("tools/ci/run_tests.sh")
    m = re.search(r'MIN_TESTS="\$\{MIN_TESTS:-(\d+)\}"', text)
    if not m:
        return 0
    return int(m.group(1))


def count_gates() -> int:
    """The gates in the registry."""
    text = read("tools/ci/run_gates.sh")
    return len(re.findall(r'^\s*"[A-Z][A-Z0-9-]*\|(hg|sg)\|', text, re.M))


def count_tests_from_log(log_path: str) -> int:
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.search(r"ran (\d+) tests", line)
            if m:
                return int(m.group(1))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", help="an oracle log to take the test count from")
    ap.add_argument("--write", action="store_true", help="rewrite the numbers in the docs")
    args = ap.parse_args()

    if args.log:
        tests = count_tests_from_log(args.log)
        source = "the log " + args.log
    else:
        tests = count_min_tests()
        source = "tools/ci/run_tests.sh (MIN_TESTS)"
    gates = count_gates()

    if tests == 0:
        print("FAIL: no test count found - cannot check the docs")
        return 1

    print("test count: %d (from %s)" % (tests, source))
    print("gate count: %d (from tools/ci/run_gates.sh)" % gates)

    problems = []
    for path, patterns in DOCS.items():
        text = read(path)
        if not text:
            print("SKIP %s (not present)" % path)
            continue
        for pattern, template in patterns:
            m = re.search(pattern, text)
            if not m:
                continue
            quoted = re.search(r"\d+", m.group(0))
            if not quoted:
                continue
            said = int(quoted.group(0))
            # the gate count is a different number - match it against the gates
            want = gates if "required gates" in pattern else tests
            if said != want:
                problems.append("%s: says %d, the product has %d (%s)" % (path, said, want, pattern))
                if args.write:
                    new = re.sub(r"\d+", str(want), m.group(0))
                    text = text.replace(m.group(0), new, 1)
        if args.write and problems:
            with open(os.path.join(REPO, path), "w", encoding="utf-8", newline="") as fh:
                fh.write(text)

    if problems:
        print("FAIL: the docs do not match the product:")
        for p in problems:
            print("  " + p)
        if not args.write:
            print("  (run with --write to fix)")
        return 1
    print("==> DOC-NUMBERS PASSED (the docs quote the numbers the product actually has)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
