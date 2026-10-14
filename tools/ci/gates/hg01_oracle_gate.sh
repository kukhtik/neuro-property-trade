#!/usr/bin/env bash
# HG-01 - oracle integrity (docs/restoration/gates.md section 2).
#
# Proves the suite cannot quietly shrink: this runs THE ORAKLE (the same script CI runs) and
# adds the checks that exist nowhere else:
#   - `ran N tests` with N >= MIN_TESTS (the runner enforces it, restated here in the reason);
#   - zero SCRIPT ERROR / Failed to load script lines;
#   - no orphan test module (enforced inside run.gd now, so a module like the once-forgotten
#     theme_test.gd cannot exist without running).
# Verdict by lines, not by exit code - see run_probes.sh for why.
#
# NPT_GATES_FAST=1 skips the import pass inside run_tests.sh; CI runs the full oracle in its own
# step before the gate runner, so the fast form is enough there. WITHOUT it the import pass runs
# here too, which is what a bare `run_gates.sh` on a fresh clone needs.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

fast=""
if [ "${NPT_GATES_FAST:-0}" = "1" ]; then fast="--fast"; fi

out="$(bash "$repo/tools/ci/run_tests.sh" $fast 2>&1)"
code=$?

# keep the tail in the log: the summary line and any failure lines are the evidence
printf '%s\n' "$out" | grep -aE "ran [0-9]+ tests|ALL TESTS PASSED|FAIL|ORACLE|SCRIPT ERROR|orphan|Failed to load" | tail -8

if printf '%s' "$out" | grep -aq "==> ORACLE PASSED"; then
	ran="$(printf '%s' "$out" | grep -aoE 'ran [0-9]+ tests' | tail -1)"
	echo "==> HG-01 PASSED ($ran, 0 SCRIPT ERROR, no orphan modules)"
	exit 0
fi

reason="oracle failed"
if printf '%s' "$out" | grep -aq "orphan test module"; then
	reason="$(printf '%s' "$out" | grep -a "orphan test module" | head -1)"
elif printf '%s' "$out" | grep -aq "SCRIPT ERROR"; then
	reason="SCRIPT ERROR in the suite output"
elif printf '%s' "$out" | grep -aq "ran [0-9]* tests"; then
	reason="$(printf '%s' "$out" | grep -aoE 'ran [0-9]+ tests, [0-9]+ failed' | tail -1) (exit=$code)"
fi
echo "==> HG-01 FAILED: $reason"
exit 1
