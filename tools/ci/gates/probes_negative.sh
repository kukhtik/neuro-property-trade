#!/usr/bin/env bash
# Negative test for the PROBES gate: a broken probe must turn the gate RED.
#
# The gate is worthless if it cannot fail. This injects a defect into a probe, runs the
# gate, checks that it reports the failure, and restores the file. The output is kept in
# build/gates/probes-negative.log so the evidence survives.
#
# THE PATH TRAP: a NATIVE python cannot open an MSYS path ("/c/Users/..."). The first
# version of this script passed the repo root straight through and the injection silently
# DID NOTHING - the file was never touched, the gate passed, and the test proved nothing.
# `native()` converts the path first, and the script FAILS LOUDLY if the injection did
# not land, so a broken negative test cannot look like a passing one.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
# native() converts a DIRECTORY (it cd's into it). Asking it about a FILE would fail the
# cd and fall back to the MSYS path, which a native python cannot open - the very trap
# this script exists to avoid. So the DIRECTORY is converted and the file name appended.
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }

out="$repo/build/gates/probes-negative.log"
probe="$repo/game/tools/keyboard_only_probe.gd"
backup="$(mktemp)"

mkdir -p "$repo/build/gates"
cp "$probe" "$backup"

python - "$(native "$repo/game/tools")/$(basename "$probe")" <<'PYEOF' || { echo "the defect was NOT injected - the test proves nothing"; exit 1; }
import re
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8", newline="").read()
# The probe has THREE exits: quit(1) on the failure path, quit(0) on the success path, and
# quit(1) again in the else branch. The success exit must be the one that is broken, or
# the probe still passes.
outs = [m.start() for m in re.finditer(r"get_tree\(\)\.quit\(0\)", t)]
assert len(outs) == 1, "expected exactly one success exit, found %d" % len(outs)
i = outs[0]
t = t[:i] + "get_tree().quit(1)  # NEGATIVE TEST: forced failure" + t[i + len("get_tree().quit(0)"):]
assert "NEGATIVE TEST" in t
open(p, "w", encoding="utf-8", newline="").write(t)
print("defect injected: the probe's SUCCESS exit now exits 1")
PYEOF

# the injection must have landed - otherwise the test below proves nothing
if ! grep -aq "NEGATIVE TEST" "$probe"; then
	echo "==> PROBES NEGATIVE FAILED: the defect did not land in the probe - the test would prove nothing"
	cp "$backup" "$probe"
	rm -f "$backup"
	exit 1
fi

echo "=== the gate, with a broken probe ===" | tee "$out"
bash "$repo/tools/ci/gates/probes_gate.sh" 2>&1 | grep -E 'keyboard_only|PROBES (PASSED|FAILED)' | tee -a "$out"

cp "$backup" "$probe"
rm -f "$backup"

echo "=== restored: the gate, with the probe intact ===" | tee -a "$out"
bash "$repo/tools/ci/gates/probes_gate.sh" 2>&1 | grep -E 'keyboard_only|PROBES (PASSED|FAILED)' | tee -a "$out"
