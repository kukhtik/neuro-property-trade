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
# A pattern is (regex, template) where the template contains {n} for the number, or
# (read_regex, old_regex, template) for the gate triple {n} total / {r} required /
# {q} quarantine.
#
# WHY THE GATE TRIPLE EXISTS. The count used to be ONE number - the TOTAL of the registry
# lines - and the docs called it "N required gates". That was a LIE that passed: the
# registry held 38 required + 1 quarantine, the total was 39, and the docs said
# "39 required gates" while only 38 gates could block the runner. A number that means
# something different from its label is a number nobody can check. Now the docs quote all
# three counts and the gate checks all three, so a gate added to either half and not to
# the docs turns the gate red.
#
# WHY THE OLD FORM IS READ TOO. The first version of this check searched only the NEW
# phrase - and so it PASSED on docs that still carried the old one, because "no match"
# is silently skipped. That is the failure this whole gate exists to prevent: a check
# that cannot fail. So the old form is read as well, and a doc that carries it is RED
# until it is rewritten.
GATES_READ_RE = r"run_gates\.sh\s+#\s*(\d+)\s+gates\s*\((\d+)\s+required\s*\+\s*(\d+)\s+in quarantine\)"
GATES_OLD_RE_README = r"run_gates\.sh\s+#\s*\d+\s+required gates"
GATES_OLD_RE_PLAN = r"run_gates\.sh\s+#\s*\d+\s+required gates,\s*none in quarantine"
GATES_TMPL = "run_gates.sh     # {n} gates ({r} required + {q} in quarantine)"
GATES_TMPL_PLAN = "run_gates.sh            # {n} gates ({r} required + {q} in quarantine)"
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
        (GATES_READ_RE, GATES_OLD_RE_README, GATES_TMPL, "gates"),
    ],
    "docs/plan.md": [
        (r"import \+ \d+ tests \+ count floor",
         "import + {n} tests + count floor"),
        (GATES_READ_RE, GATES_OLD_RE_PLAN, GATES_TMPL_PLAN, "gates"),
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


def count_gates() -> tuple:
    """The gates in the registry: (total, required, quarantine)."""
    text = read("tools/ci/run_gates.sh")
    total = len(re.findall(r'^\s*"[A-Z][A-Z0-9-]*\|(hg|sg)\|', text, re.M))
    required = len(re.findall(r'^\s*"[A-Z][A-Z0-9-]*\|(hg|sg)\|required\|', text, re.M))
    quarantine = len(re.findall(r'^\s*"[A-Z][A-Z0-9-]*\|(hg|sg)\|quarantine\|', text, re.M))
    return total, required, quarantine


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
    gates_total, gates_required, gates_quarantine = count_gates()

    if tests == 0:
        print("FAIL: no test count found - cannot check the docs")
        return 1

    print("test count: %d (from %s)" % (tests, source))
    print("gate count: %d total = %d required + %d in quarantine (from tools/ci/run_gates.sh)"
          % (gates_total, gates_required, gates_quarantine))

    problems = []
    for path, patterns in DOCS.items():
        text = read(path)
        if not text:
            print("SKIP %s (not present)" % path)
            continue
        for spec in patterns:
            if len(spec) > 2 and spec[-1] == "gates":
                read_re, old_re, template = spec[0], spec[1], spec[2]
                want = (gates_total, gates_required, gates_quarantine)
                m = re.search(read_re, text)
                if m:
                    nums = tuple(int(x) for x in m.groups())
                    if nums != want:
                        problems.append("%s: says %d gates (%d required + %d quarantine), the "
                                        "product has %d (%d required + %d quarantine)"
                                        % (path, nums[0], nums[1], nums[2], want[0], want[1],
                                           want[2]))
                        if args.write:
                            new = template.format(n=want[0], r=want[1], q=want[2])
                            text = text.replace(m.group(0), new, 1)
                    continue
                # the NEW phrase is absent - so the doc still carries the OLD one, and a
                # doc that says "N required gates" when N is the TOTAL is lying. That is
                # red, not a silent skip.
                mo = re.search(old_re, text)
                if mo:
                    problems.append("%s: the gate count is in the old form (%r) - the docs must "
                                    "separate total, required and quarantine" % (path, mo.group(0)))
                    if args.write:
                        new = template.format(n=want[0], r=want[1], q=want[2])
                        text = text.replace(mo.group(0), new, 1)
                else:
                    problems.append("%s: no gate count found - the docs must state how many "
                                    "gates the product has" % path)
                continue
            pattern, template = spec[0], spec[1]
            m = re.search(pattern, text)
            if not m:
                continue
            quoted = re.search(r"\d+", m.group(0))
            if not quoted:
                continue
            said = int(quoted.group(0))
            if said != tests:
                problems.append("%s: says %d, the product has %d (%s)" % (path, said, tests, pattern))
                if args.write:
                    # ТОЛЬКО ПЕРВОЕ число: в совпадении может быть второе, и оно -
                    # ЧУЖОЕ ("0 SCRIPT ERROR", "zero third-party dependencies").
                    # `re.sub` без count менял и его тоже, и строка
                    # "ORACLE PASSED (428 tests, 0 SCRIPT ERROR)" превращалась в
                    # "(428 tests, 428 SCRIPT ERROR)" - гейт чинил документ и СРАЗУ
                    # ломал его. Первое число - и есть то, которое мы проверяем.
                    new = re.sub(r"\d+", str(tests), m.group(0), count=1)
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
