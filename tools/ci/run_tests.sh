#!/usr/bin/env bash
# THE ORACLE. Runs the headless rules-engine suite and gates the result.
#
#   tools/ci/run_tests.sh            # full gate
#   tools/ci/run_tests.sh --fast     # skip the import pass (warm .godot/)
#
# Gates (ALL must hold, exit 1 otherwise):
#   1. an import pass has populated .godot/ - a fresh clone has NO class cache,
#      so `class_name` globals (I18n, ...) fail to resolve and 4 tests fail;
#   2. `res://tests/run.gd` exits 0;
#   3. the runner printed "ALL TESTS PASSED";
#   4. the test count is >= MIN_TESTS - guards against a module silently failing
#      to load and the suite quietly shrinking;
#   5. zero "SCRIPT ERROR" / "Failed to load script" lines. Exit 0 alone is NOT
#      sufficient: run.gd skips a module it cannot load and still exits 0.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="$("$ROOT/tools/ci/godot_bin.sh")"
# The count is a tripwire, not a target: if a module stops compiling the runner reports success
# for the work it skipped, and only the total betrays it. Kept a little under the real number so
# adding or retiring a handful of tests does not require editing this line.
# History: 400 (pre-swap) -> 270 (v3 interface swap, ~130 UI tests archived) -> 289 (+6 when
# `theme_test` was found as an orphan and put back into `modules`; the runner now fails on any
# orphan test module, so this number can only move UP together with real tests) -> 292
# (+3: ui_contract_test = HG-10, the projection contract and its `pot` regression case) -> 356
# (+64: ui_core_test = the UI core itself — the event adapter, the journal lines, money, the
# intent mapping, the layout profiles, the launch roles and the view model. The swap archived
# ~130 UI tests; this module pays the debt BACK alongside the rebuilt interface instead of
# measuring a tree that no longer exists. Negative check: a threshold flipped in
# `layout_profile.gd` fails exactly `test_desktop_at_1280` with a readable reason, and reverting
# it restores the count.)
MIN_TESTS="${MIN_TESTS:-406}"
FAST="${1:-}"
LOG="${TMPDIR:-/tmp}/npt-tests-$$.log"

cd "$ROOT"

echo "==> godot: $GODOT"
"$GODOT" --version

if [ "$FAST" != "--fast" ]; then
  echo "==> import pass (populates .godot/ class cache; required on a fresh clone)"
  "$GODOT" --headless --path game --import >"${LOG%.log}-import.log" 2>&1 || true
  if grep -q "SCRIPT ERROR" "${LOG%.log}-import.log"; then
    echo "FAIL: import pass emitted SCRIPT ERROR:"
    grep -n "SCRIPT ERROR" "${LOG%.log}-import.log" | head
    exit 1
  fi
fi

echo "==> headless test suite"
"$GODOT" --headless --path game --script res://tests/run.gd 2>&1 | tee "$LOG"
STATUS="${PIPESTATUS[0]}"

fail=0
if [ "$STATUS" != "0" ]; then echo "FAIL: runner exit code $STATUS"; fail=1; fi

if ! grep -q "ALL TESTS PASSED" "$LOG"; then
  echo "FAIL: runner did not report ALL TESTS PASSED"; fail=1
fi

RAN="$(grep -oE 'ran [0-9]+ tests' "$LOG" | head -1 | grep -oE '[0-9]+' || echo 0)"
if [ "${RAN:-0}" -lt "$MIN_TESTS" ]; then
  echo "FAIL: ran ${RAN:-0} tests, expected >= $MIN_TESTS (did a module fail to load?)"; fail=1
fi

if grep -q "SCRIPT ERROR" "$LOG"; then
  echo "FAIL: SCRIPT ERROR in test output:"
  grep -n "SCRIPT ERROR" "$LOG" | head
  fail=1
fi
if grep -q "Failed to load script" "$LOG"; then
  echo "FAIL: a test module failed to load:"
  grep -n "Failed to load script" "$LOG" | head
  fail=1
fi

if [ "$fail" != "0" ]; then echo "==> ORACLE FAILED"; exit 1; fi
echo "==> ORACLE PASSED ($RAN tests, 0 SCRIPT ERROR)"
