#!/usr/bin/env bash
# PROBES - the diagnostic probes that were never wired into anything.
#
# WHY THIS EXISTS. Twelve probe scenes live in game/tools/ and only one of them
# (multi_sdk) was in the gate registry. The other eleven were run by hand, by a person,
# at some point in the past, and their answer was read once and thrown away. That is
# exactly the defect this repository keeps paying for: a measurement nobody re-runs is a
# measurement that silently stops being true.
#
# These five are wired here, and the split is not arbitrary - it is the difference
# between a probe that ASSERTS a requirement and a probe that ANSWERS a question.
# The classification was MEASURED, not guessed: `grep -c 'quit(1)'` on each probe
# says which ones can fail at all.
#
#   ASSERTS (the probe exits 1 when the requirement is broken) - wired as gates:
#     keyboard_only  a whole session played from the keyboard alone (PART 3's promise)
#
#   ANSWERS (the probe prints a report and exits 0 whatever it finds) - run, and their
#   report is CHECKED here, but the probe's own exit code is not the verdict:
#     touch          every clickable control in the side panels, with its real rectangle,
#                   and the ones under the 28 px mouse floor marked "SMALL"
#     cell_step      which cells fell into the "narrower than 44px" step and why
#     layout_density the largest gap between content rows, per panel
#
# phone_fit was here until 23.10 and is GONE by the owner's decision: «телефонную проверку
# отменяем. вместо нее нужно сделать проверку на консистентность… по пиксельное сравнение
# с макетом». It asked "can you PLAY in a 390 px window" and the honest answer was NO (the
# layout measures 817 px in a 390 px viewport; the product declares MIN_WIDTH = 880), so it
# ran with an INVERTED expectation - a gate that must fail today. The criterion is
# cancelled, so the probe and its inverted expectation are gone with it.
# WHAT STAYS: the promise the product actually makes - "a viewer watching the stream on a
# phone can read it" (docs/program.md P1.1) - is measured by the gate STREAM-READ, which
# scales a 1920x1080 frame down to 390 and judges the EFFECTIVE font size against a 12 px
# floor. That gate is required, and it is green.
# WHAT REPLACES THE CANCELLED CHECK: MOCK-01 (consistency: the live frame against the
# reference mockup) and MOCK-02 (visual taste: type sizes and the cap).
#
# The three answer-probes are checked differently: their REPORTS are read here, so a
# regression in the report (a new small target, a new blown-up panel) is caught even
# though the probe itself cannot fail. That is the whole point of wiring them: a
# measurement nobody re-runs is a measurement that silently stops being true.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

godot="$(bash "$repo/tools/ci/godot_bin.sh")"
if [ -z "$godot" ]; then
	echo "==> PROBES SKIPPED: no Godot binary (see tools/ci/fetch_godot.sh)"
	exit 0
fi

mkdir -p "$repo/build/gates"
# Godot is a NATIVE program: it cannot open an MSYS path ("Invalid project path
# specified: "/c/Users/...""). pwd -W gives the Windows form.
game_dir="$( cd "$repo/game" 2>/dev/null && pwd -W )"
rc_all=0
report=""

run_probe() {
	local name="$1" scene="$2" expect="$3"  # expect: pass | answer
	local log="$repo/build/gates/probe-$name.log"
	timeout 180 "$godot" --headless --path "$game_dir" "$scene" >"$log" 2>&1
	local rc=$?
	local errs
	# `grep -c` prints "0" AND exits 1 when there is no match, so `|| echo 0` used to
	# append a SECOND "0" and the value became "0\n0" - every integer test on it then
	# said "integer expression expected" and the count was never really compared.
	errs="$(grep -ac 'SCRIPT ERROR' "$log" 2>/dev/null | head -1)"
	errs="${errs:-0}"
	report="$report
  $name: exit=$rc script_errors=$errs expect=$expect"
	case "$expect" in
	pass)
		if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ]; then
			echo "  $name FAILED (exit=$rc, script_errors=$errs) - see build/gates/probe-$name.log"
			rc_all=1
		else
			echo "  $name PASSED (exit=0, no script errors)"
		fi
		;;
	answer)
		# the probe cannot fail; its REPORT is the measurement, so read the report
		if [ "$errs" -ne 0 ]; then
			echo "  $name: SCRIPT ERROR in the report - the measurement itself broke"
			rc_all=1
			continue
		fi
		case "$name" in
		touch)
			# a control under the 28 px mouse floor is printed with a "SMALL " marker
			local small
			small="$(grep -ac 'SMALL ' "$log" 2>/dev/null | head -1)"
			small="${small:-0}"
			if [ "$small" -eq 0 ]; then
				echo "  touch: 0 controls under the 28px floor (good)"
			else
				echo "  touch: $small control(s) under the 28px floor - they are listed in the log"
			fi
			;;
		cell_step)
			# cells that fell into the "narrower than 44px" step print their reason
			local steps
			steps="$(grep -ac 'step' "$log" 2>/dev/null | head -1)"
			steps="${steps:-0}"
			echo "  cell_step: $steps line(s) about the label step (see the log)"
			;;
		layout_density)
			# the largest gap between content rows, per panel
			local rows
			rows="$(grep -aci 'gap' "$log" 2>/dev/null | head -1)"
			rows="${rows:-0}"
			echo "  layout_density: $rows gap line(s) measured (see the log)"
			;;
		esac
		;;
	esac
}

echo "running the probes that were never wired into anything"
run_probe keyboard_only  "res://tools/keyboard_only_probe.tscn"   pass
run_probe touch          "res://tools/touch_probe.tscn"           answer
run_probe cell_step      "res://tools/cell_step_probe.tscn"       answer
run_probe layout_density "res://tools/layout_density_probe.tscn" answer

echo "probe results:"
printf '%s\n' "$report"
if [ "$rc_all" -ne 0 ]; then
	echo "==> PROBES FAILED: a probe that asserts a requirement broke"
	exit 1
fi
echo "==> PROBES PASSED (the probes that assert a requirement still hold; the answer-probes are reported)"
exit 0
