#!/usr/bin/env bash
# Run EVERY behavioral probe in game/tools, not just the ones the main CI job knows about.
#
# WHY THIS EXISTS: probes were written per stage and never wired anywhere. By the time anyone
# ran them again, five of sixteen were RED — `p2` read nine TileView fields that a refactor had
# renamed away, `p4` searched for a button label that had changed, `i18n_probe` found the engine's
# raw phase enums rendered in the board centre, and `game_view._jpanel` (declared, never assigned)
# was throwing a SCRIPT ERROR inside a probe that otherwise reported PASS.
#
# A probe that is not run is not a check; it is a comment that compiles.
#
# Exit 0 only when every probe passes AND no probe emitted a SCRIPT ERROR.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
godot="$(bash "$here/godot_bin.sh")"

if [ -z "$godot" ]; then
	echo "run_probes: no Godot binary (see tools/ci/fetch_godot.sh)" >&2
	exit 1
fi

# The probes that are expected to run green. A probe added here must pass.
PROBES=(
	p0_probe p1_probe p2_probe p3_probe p4_probe p5_probe p6_p3_probe
	stage1_probe stage2_probe stage3_smoke stage4_smoke
	ui_audit_probe board_sizes_visual dynamic_board_probe i18n_probe skin_probe
)

failed=0
passed=0
for p in "${PROBES[@]}"; do
	scene="$repo/game/tools/$p.tscn"
	if [ ! -f "$scene" ]; then
		echo "MISSING: $p (no scene)"
		failed=$((failed + 1))
		continue
	fi
	# `--path` must be RELATIVE: under MSYS the shell's absolute paths look like `/c/Users/...`
	# and the native Godot binary cannot open them, so every probe would silently produce nothing.
	out="$(cd "$repo" && timeout 240 "$godot" --headless --path game "res://tools/$p.tscn" 2>&1)"
	code=$?

	# A SCRIPT ERROR is a failure even when the probe prints PASSED: that is exactly how a dead
	# `_jpanel` field sat inside a green probe.
	errs=$(printf '%s' "$out" | grep -ac "SCRIPT ERROR" || true)
	# VERDICTS ARE NOT UNIFORM: probes print `==> STAGE 1 PASSED — ...`, `P2 PROBE: ALL PASSED`,
	# `I18N_PROBE: ALL PASSED (3 checks)`, `BOARD SIZES PASSED`. Matching one wording made five
	# passing probes look broken. What matters: PASSED appears, FAILED does not, exit is 0.
	verdict=$(printf '%s' "$out" | grep -aoE "(STAGE [0-9] PASSED|BOARD SIZES PASSED|PROBE: ALL PASSED|ALL PASSED|PASSED)" | tail -1)
	bad=$(printf '%s' "$out" | grep -acE "FAILED|FAIL:" || true)

	# A NON-ZERO EXIT IS NOT A VERDICT. Godot 4.7 on Windows segfaults during cleanup often
	# enough to be useless as a signal: `p0_probe` printed PASSED and exited 139 on one run and 0
	# on the next. The probe's own verdict is the evidence; the exit code is noise.
	if [ "$code" -ne 0 ] && [ -n "$verdict" ] && [ "$bad" -eq 0 ] && [ "$errs" -eq 0 ]; then
		printf 'warn: %-20s %s (godot exited %s during cleanup)
' "$p" "$verdict" "$code"
		passed=$((passed + 1))
		continue
	fi

	if [ "$code" -ne 0 ] || [ "$errs" -ne 0 ] || [ -z "$verdict" ] || [ "$bad" -ne 0 ]; then
		printf 'FAIL: %-20s exit=%s verdict=%s script_errors=%s fail_lines=%s\n' "$p" "$code" "${verdict:-none}" "$errs" "$bad"
		printf '%s\n' "$out" | grep -aE "FAIL:|SCRIPT ERROR|Parse Error" | head -5
		failed=$((failed + 1))
	else
		printf 'ok:   %-20s %s\n' "$p" "$verdict"
		passed=$((passed + 1))
	fi
done

echo "---"
echo "probes: $passed passed, $failed failed"
if [ "$failed" -ne 0 ]; then
	echo "==> PROBES FAILED"
	exit 1
fi
echo "==> PROBES PASSED ($passed)"
exit 0
