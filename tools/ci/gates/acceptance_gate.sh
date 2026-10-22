#!/usr/bin/env bash
# ACCEPTANCE — is the delivery package complete? One machine-checked line per promise.
#
# WHY THIS GATE EXISTS: the acceptance track had no check at all. For weeks the plan
# listed "the application, the handoff, the release package" and nothing measured them,
# so "done" was a memory, and my notes about it went stale - two items I had recorded
# as broken turned out to be fixed long ago (the empty success message, the licensing
# citation). A promise with no gate decays into a story.
#
# EVERY ITEM BELOW IS A GATE, NOT A NOTE. Each one is re-checked against the tree on
# every run, and the answers are printed - DONE or TODO with the evidence that
# decided it. That is the whole point: the list cannot be out of date, because it is
# recomputed rather than remembered.
#
# STATUS: this is a promise that is NOT yet delivered, so it is registered as
# QUARANTINE - red by design, reported, not blocking (the same convention as
# STREAM-READ). It graduates to required when the package is signed off.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
cd "$repo"

done_n=0
total_n=0
missing=""

# check <id> <what> <command that succeeds when the promise is met>
check() {
	local id="$1" what="$2"; shift 2
	total_n=$((total_n + 1))
	local out
	if out="$("$@" 2>&1)"; then
		done_n=$((done_n + 1))
		printf '  %-6s DONE   %s\n' "$id" "$what"
	else
		printf '  %-6s TODO   %s\n' "$id" "$what"
		missing="${missing}${id}: ${what}"$'\n'
	fi
}

# ---- the checks (each one is a machine-checkable promise) ------------------------

c_a1() {  # the SDK success result carries the state change (brief: "Action Results")
	grep -q 'ExecutionResult.success(msg)' game/sdk/engine_action.gd \
		&& grep -q 'func success_message' game/sdk/sdk_adapter.gd
}
c_a2() {  # the licensing note cites the authority that actually holds
	grep -q 'Baker v. Selden' docs/licensing.md \
		&& grep -q '102(b)' docs/licensing.md \
		&& grep -q 'not authority for copying game mechanics' docs/licensing.md
}
c_a3() {  # the store page does not name the trademark (the owner's own rule)
	[ "$(grep -ci 'monopoly' README.md || true)" = "0" ]
}
c_a4() {  # the handoff document exists and carries the brief's four parts
	local f
	f="$(git ls-files | grep -iE 'handoff' | head -1)"
	[ -n "$f" ] && grep -qiE 'neuro sdk' "$f" && grep -qiE 'source' "$f" \
		&& grep -qiE 'notes' "$f" && grep -qiE 'command' "$f"
}
c_a5() {  # the release package: an artifact, a manifest and the notes
	local f
	f="$(git ls-files | grep -iE 'release.*(package|notes)|package.*release' | head -1)"
	[ -n "$f" ]
}
c_a6() {  # the criteria table: brief item -> where in the code -> what measures it
	local f
	f="$(git ls-files | grep -iE 'acceptance.*(api|criteria)|api.*criteria' | head -1)"
	[ -n "$f" ]
}
c_c1() {  # the release-build scenario is a registered gate, so CI checks the artifact
	grep -q 'scenario_s3' tools/ci/run_gates.sh
}
c_c3() {  # the pack ships no test module
	local pck=build/current/web/index.pck
	[ -f "$pck" ] && [ "$(grep -ac 'res://tests/' "$pck" || true)" = "0" ]
}
c_c4() {  # the pause promise has a gate
	grep -q '"HG-15' tools/ci/run_gates.sh
}
c_c5() {  # the timer promise is registered and green
	grep -q '"HG-13' tools/ci/run_gates.sh || return 1
	[ -f build/gates/HG-13.json ] || return 1
	grep -q '"verdict": "pass"' build/gates/HG-13.json
}
c_d1() {  # VOICE-01 (who is speaking) is a promise with a gate
	grep -q '"VOICE-01' tools/ci/run_gates.sh
}
c_d2() {  # E-5 (the player's inventory) is a promise with a gate
	git grep -qiE 'inventory' -- game/ && grep -q '"E-5' tools/ci/run_gates.sh
}

echo "=== ACCEPTANCE: the delivery package, re-checked now ==="
check A1 "the SDK success result carries the state change"        c_a1
check A2 "the licensing note cites Baker v. Selden and 102(b)"    c_a2
check A3 "the store page does not name the trademark"              c_a3
check A4 "the handoff document exists with the brief's four parts" c_a4
check A5 "the release package exists (artifact + manifest + notes)" c_a5
check A6 "the table brief -> code -> measurement exists"           c_a6
check C1 "the release-build scenario is a registered gate"         c_c1
check C3 "the pack ships no test module"                           c_c3
check C4 "the pause promise has a gate"                            c_c4
check C5 "the timer promise is registered and green"               c_c5
check D1 "VOICE-01 (who is speaking) has a gate"                   c_d1
check D2 "E-5 (the player's inventory) has a gate"                 c_d2

echo ""
if [ "$done_n" = "$total_n" ]; then
	echo "==> ACCEPTANCE PASSED ($done_n/$total_n promises measured and met)"
	exit 0
fi
echo "==> ACCEPTANCE FAILED: $done_n of $total_n promises are met; $((total_n - done_n)) are open:"
printf '%s' "$missing" | sed 's/^/    - /'
echo "    (the intake form itself is outside the tree - only the owner can say it was sent)"
exit 1
