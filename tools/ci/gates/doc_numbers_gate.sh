#!/usr/bin/env bash
# DOC-NUMBERS - the docs must quote the numbers the product actually has.
#
# WHY THIS EXISTS. `docs/infra.md` said "227 tests" and "MIN_TESTS (default 200)" while the
# oracle was running 421. The count moved 227 -> 270 -> 289 -> 292 -> 356 -> 383 -> 388 ->
# 395 -> 406 -> 411 -> 416 -> 421, and every doc that quoted a number was edited BY HAND,
# so every one of them was wrong the moment the next test landed. A doc that lies about
# the number of tests is worse than a doc that says nothing: a reader checking "does it
# still hold" trusts it.
#
# WHAT IT CHECKS
#   1. the test count in the docs equals the count the oracle reports;
#   2. the MIN_TESTS floor equals the number of tests that actually ran;
#   3. the gate count in the docs equals the number of gates in the registry.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

PY=""
for cand in python python3 "py -3"; do
	if command -v "$cand" >/dev/null 2>&1 && $cand -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "==> DOC-NUMBERS SKIPPED: no python interpreter for tools/ci/doc_numbers.py"
	exit 0
fi

out="$(cd "$repo" && $PY tools/ci/doc_numbers.py 2>&1)"
rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
if [ "$rc" -ne 0 ]; then
	echo "==> DOC-NUMBERS FAILED: the docs quote numbers the product does not have (run: py -3.12 tools/ci/doc_numbers.py --write)"
	exit 1
fi
echo "==> DOC-NUMBERS PASSED (the docs quote the numbers the product actually has)"
exit 0
