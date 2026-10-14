#!/usr/bin/env bash
# THE GATE RUNNER (docs/restoration/gates.md section 1).
#
# Why this exists: tests covered the ENGINE and the interface lived on a smoke that measured
# stale artifacts. The product shipped broken with a green CI: a dead browser join, console
# buttons that could not work, docks that vanish in the compact profile, live brace-keys on
# screen. The restoration program turns each of those into a GATE here: a check with a human
# verdict line, a machine-readable result and a report that cannot be green without saying
# WHAT it looked at.
#
#   tools/ci/run_gates.sh              # every gate (--all)
#   tools/ci/run_gates.sh --hg         # hard gates only (functionality)
#   tools/ci/run_gates.sh --sg         # soft gates only (appearance/usability)
#   tools/ci/run_gates.sh --report-only  # rebuild build/gates/report.html from the last run
#
# DISCIPLINE (same as run_probes.sh, and it is earned the hard way):
#   - the verdict is read FROM THE LINES (==> HG-XX PASSED / ==> HG-XX FAILED: reason);
#     the Godot exit code is noise (it segfaults during cleanup on Windows);
#   - a SCRIPT ERROR line fails a gate even when it printed PASSED;
#   - a gate that prints NO verdict line is broken and counts as failed;
#   - quarantine gates run and are REPORTED, but their red does not fail this runner.
#     A gate is promoted to required (and to CI blocking) only after green runs in this
#     session; while P0 is unfixed every new gate starts in quarantine.
#
# Every run writes: build/gates/<id>.log (full output), build/gates/<id>.json (result),
# build/gates/report.html (the human report).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
outdir="$repo/build/gates"
mkdir -p "$outdir"
# NATIVE paths for native binaries (python, git): they cannot open MSYS `/c/...` paths - the
# same trap that makes `git -C /c/...` and the godot binary fail silently.
native() { ( cd "$1" 2>/dev/null && pwd -W ) 2>/dev/null || printf '%s' "$1"; }
repo_win="$(native "$repo")"
out_win="$(native "$outdir")"

mode="all"
report_only=0
for arg in "$@"; do
	case "$arg" in
		--hg) mode="hg" ;;
		--sg) mode="sg" ;;
		--all) mode="all" ;;
		--report-only) report_only=1 ;;
		*) echo "usage: run_gates.sh [--hg|--sg|--all|--report-only]" >&2; exit 2 ;;
	esac
done

# The registry. id | class (hg/sg) | status (required/quarantine) | kind (scene/script) | target
#   scene  -> game/tools/gates/<target>.tscn, run headless against the real app;
#   script -> tools/ci/gates/<target>, a shell check (oracle, frame contract, freshness).
GATES=(
	"HG-01|hg|required|script|tools/ci/gates/hg01_oracle_gate.sh"
	"HG-09|hg|required|scene|hg09_i18n_gate"
	"HG-11|hg|required|script|tools/ci/gates/hg11_freshness_gate.sh"
	"HG-02|hg|quarantine|scene|hg02_console_actions_gate"
	"HG-12|hg|quarantine|scene|hg12_admin_smoke_gate"
	"HG-06|hg|quarantine|script|tools/ci/gates/hg06_browser_join_gate.sh"
	"HG-05|hg|quarantine|scene|hg05_identity_gate"
	"SG-01|sg|quarantine|scene|sg01_compact_gate"
)

# a working python for the report/JSON: `python` first (Windows local), then `python3` (CI).
PY=""
for cand in python python3; do
	if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" >/dev/null 2>&1; then
		PY="$cand"
		break
	fi
done
if [ -z "$PY" ]; then
	echo "run_gates: no python interpreter - the report cannot be written" >&2
	exit 1
fi

godot=""
if [ "$report_only" -eq 0 ]; then
	godot="$(bash "$here/godot_bin.sh")"
	if [ -z "$godot" ]; then
		echo "run_gates: no Godot binary (see tools/ci/fetch_godot.sh)" >&2
		exit 1
	fi
fi

selected=()
for row in "${GATES[@]}"; do
	klass="$(printf '%s' "$row" | cut -d'|' -f2)"
	if [ "$mode" = "all" ] || [ "$mode" = "$klass" ]; then
		selected+=("$row")
	fi
done

run_gate() {
	local id="$1" klass="$2" status="$3" kind="$4" target="$5"
	local log="$outdir/$id.log"
	local started code
	started="$(date +%s)"
	code=0
	if [ "$kind" = "scene" ]; then
		if [ ! -f "$repo/game/tools/gates/$target.tscn" ]; then
			echo "gate scene missing: game/tools/gates/$target.tscn" >"$log"
			code=127
		else
			( cd "$repo" && timeout 300 "$godot" --headless --path game "res://tools/gates/$target.tscn" ) >"$log" 2>&1
			code=$?
		fi
	else
		if [ ! -f "$repo/$target" ]; then
			echo "gate script missing: $target" >"$log"
			code=127
		else
			( cd "$repo" && timeout 900 bash "$target" ) >"$log" 2>&1
			code=$?
		fi
	fi
	# normalise CRLF so the verdict grep cannot miss a line it would match on Linux
	tr -d '\r' <"$log" >"$log.norm" && mv "$log.norm" "$log"
	local seconds=$(( $(date +%s) - started ))

	local pass_line fail_line errs verdict reason
	pass_line="$(grep -a "==> $id PASSED" "$log" | tail -1 || true)"
	fail_line="$(grep -a "==> $id FAILED" "$log" | tail -1 || true)"
	# `SCRIPT ERROR:` with the colon is Godot's real error line. Matching the bare phrase also
	# caught the INFORMATIVE line "0 SCRIPT ERROR" from the oracle's own verdict, which failed
	# a perfectly green HG-01.
	errs="$(grep -acE "SCRIPT ERROR:" "$log" || true)"
	skip_line="$(grep -a "==> $id SKIPPED" "$log" | tail -1 || true)"
	if [ -n "$fail_line" ]; then
		verdict="fail"
		reason="$(printf '%s' "$fail_line" | sed "s/.*==> $id FAILED:[[:space:]]*//")"
	elif [ "${errs:-0}" -ne 0 ]; then
		verdict="fail"
		reason="SCRIPT ERROR in the gate output"
	elif [ -n "$pass_line" ]; then
		verdict="pass"
		reason=""
	elif [ -n "$skip_line" ]; then
		# an environment that cannot run the gate says so out loud: counted and reported,
		# never a pass (a gate that did not run has proven nothing) and never a block.
		verdict="skip"
		reason="$(printf '%s' "$skip_line" | sed "s/.*==> $id SKIPPED:[[:space:]]*//")"
	else
		verdict="fail"
		reason="no verdict line (==> $id PASSED/FAILED) - the gate did not run; godot exit=$code"
	fi

	NPT_GATE_ID="$id" NPT_GATE_KLASS="$klass" NPT_GATE_STATUS="$status" \
	NPT_GATE_VERDICT="$verdict" NPT_GATE_REASON="$reason" NPT_GATE_LOG="$(native "$log")" \
	NPT_GATE_SECONDS="$seconds" NPT_GATE_REPO="$repo_win" NPT_GATE_JSON="$out_win/$id.json" "$PY" - <<'PYEOF'
import json, os, time
repo = os.environ["NPT_GATE_REPO"]
log = os.environ["NPT_GATE_LOG"]
try:
    # relative to build/gates/ - the report sits in the same directory, so its links work
    rel = os.path.relpath(log, os.path.dirname(os.environ["NPT_GATE_JSON"])).replace("\\", "/")
except ValueError:
    rel = log
d = {
    "id": os.environ["NPT_GATE_ID"],
    "class": os.environ["NPT_GATE_KLASS"],
    "status": os.environ["NPT_GATE_STATUS"],
    "verdict": os.environ["NPT_GATE_VERDICT"],
    "reason": os.environ["NPT_GATE_REASON"],
    "seconds": int(os.environ["NPT_GATE_SECONDS"]),
    "log": rel,
    "ran_at": time.strftime("%Y-%m-%d %H:%M:%S"),
}
with open(os.environ["NPT_GATE_JSON"], "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=1, ensure_ascii=False)
PYEOF

	if [ "$verdict" = "pass" ]; then
		printf 'ok:   %-6s [%s] %s\n' "$id" "$status" "$(printf '%s' "$pass_line" | sed 's/^==> //')"
	elif [ "$verdict" = "skip" ]; then
		printf 'skip: %-6s [%s] %s\n' "$id" "$status" "$reason"
	elif [ "$status" = "required" ]; then
		printf 'FAIL: %-6s [required] %s\n' "$id" "$reason"
	else
		printf 'red:  %-6s [quarantine] %s\n' "$id" "$reason"
	fi
}

write_report() {
	local reg="" row
	for row in "${selected[@]}"; do
		reg="$reg$row
"
	done
	NPT_GATES_REGISTRY="$reg" NPT_GATES_DIR="$out_win" \
	NPT_GATES_HEAD="$(git -C "$repo_win" rev-parse --short HEAD 2>/dev/null || echo '?')" "$PY" - <<'PYEOF'
import json, os, pathlib, time
outdir = pathlib.Path(os.environ["NPT_GATES_DIR"])
req_pass = req_fail = q_pass = q_fail = notrun = 0
table = []
for line in os.environ["NPT_GATES_REGISTRY"].splitlines():
    if not line.strip():
        continue
    gid, klass, status, kind, target = line.split("|")
    jf = outdir / (gid + ".json")
    if jf.exists():
        d = json.loads(jf.read_text(encoding="utf-8"))
        verdict, reason = d.get("verdict", "?"), d.get("reason", "")
        log = d.get("log", "")
        secs = d.get("seconds", 0)
    else:
        verdict, reason, log, secs = "not-run", "no result in build/gates/ (run the runner)", "", 0
    if verdict == "pass":
        if status == "required":
            req_pass += 1
        else:
            q_pass += 1
    elif verdict == "not-run":
        notrun += 1
    else:
        if status == "required":
            req_fail += 1
        else:
            q_fail += 1
    color = {"pass": "#2ea043", "fail": "#d73a49"}.get(verdict, "#8a8f98")
    table.append(
        "<tr><td><b>%s</b></td><td>%s</td><td>%s</td>"
        "<td style='color:%s'><b>%s</b></td><td>%s</td><td>%ss</td><td><a href='%s'>log</a></td></tr>"
        % (gid, klass, status, color, verdict, (reason or "-")[:300], secs, log or "#")
    )
html = """<!doctype html><html><head><meta charset="utf-8">
<title>NPT gate report</title>
<style>
 body{background:#14161a;color:#e6e6e6;font:14px/1.5 system-ui,Segoe UI,sans-serif;margin:24px}
 h1{font-size:20px} table{border-collapse:collapse;margin-top:12px}
 td,th{border:1px solid #30343b;padding:6px 10px;text-align:left;vertical-align:top}
 th{background:#1d2026} .sum{margin-top:10px;color:#9aa0a6} code{color:#c9a84c}
</style></head><body>
<h1>NPT gates - %(head)s</h1>
<div class="sum">generated %(when)s &nbsp;&middot;&nbsp; required: %(rp)s green / %(rf)s red
&nbsp;&middot;&nbsp; quarantine: %(qp)s green / %(qf)s red / %(nr)s not run<br>
quarantine gates are REPORTED but do not fail the runner; a required gate that is red blocks.</div>
<table><tr><th>gate</th><th>class</th><th>status</th><th>verdict</th><th>reason</th><th>time</th><th>log</th></tr>
%(rows)s</table>
<p class="sum">Discipline: verdict by lines, a SCRIPT ERROR fails a gate, a missing verdict
counts as failed. Machine results are the JSON files next to this report; the logs are raw.</p>
</body></html>""" % {
    "head": os.environ.get("NPT_GATES_HEAD", "?"),
    "when": time.strftime("%Y-%m-%d %H:%M:%S"),
    "rp": req_pass, "rf": req_fail, "qp": q_pass, "qf": q_fail, "nr": notrun,
    "rows": "\n".join(table),
}
(outdir / "report.html").write_text(html, encoding="utf-8")
print("gates: required %d/%d green - quarantine %d green, %d red, %d not run"
      % (req_pass, req_pass + req_fail, q_pass, q_fail, notrun))
print("report: %s" % (outdir / "report.html"))
PYEOF
}

if [ "$report_only" -eq 0 ]; then
	echo "==> gate runner ($mode) - repo $repo"
	for row in "${selected[@]}"; do
		run_gate "$(printf '%s' "$row" | cut -d'|' -f1)" \
			"$(printf '%s' "$row" | cut -d'|' -f2)" \
			"$(printf '%s' "$row" | cut -d'|' -f3)" \
			"$(printf '%s' "$row" | cut -d'|' -f4)" \
			"$(printf '%s' "$row" | cut -d'|' -f5)"
	done
fi

# the report is required either way: "no report" is a failure of the run itself
write_report | tail -2

req_red=0
for jf in "$outdir"/*.json; do
	[ -f "$jf" ] || continue
	status="$(grep -o '"status": "[^"]*"' "$jf" | head -1 | sed 's/.*: "//;s/"$//')"
	verdict="$(grep -o '"verdict": "[^"]*"' "$jf" | head -1 | sed 's/.*: "//;s/"$//')"
	if [ "$status" = "required" ] && [ "$verdict" != "pass" ]; then
		req_red=$((req_red + 1))
	fi
done
if [ "$req_red" -ne 0 ]; then
	echo "==> GATES FAILED ($req_red required gate(s) red)"
	exit 1
fi
echo "==> GATES PASSED (every required gate is green; quarantine reds are reported above)"
exit 0
