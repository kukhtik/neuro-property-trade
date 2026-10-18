#!/usr/bin/env bash
# Free text lane: opencode's free tier through opencode's OWN client.
#
# WHY THIS EXISTS (measured 2026-10-19):
#   * Hermes cannot reach the free tier: the keyless `opencode-free` provider was REMOVED
#     ("OpenCode discontinued anonymous free-tier access outside its own client (relay 403s
#     FreeTierError)"), and `opencode-go/beam-free` answers HTTP 403 "not available in your country".
#   * The opencode CLI itself DOES reach the free tier for TEXT: `opencode run --model
#     opencode/deepseek-v4.1-flash-free "…"` answers normally.
#   * It does NOT do TOOL CALLS: any task that needs to write a file or run a command dies with
#     'UnknownError: Unexpected server error' (three tries, three different refs). So this lane is
#     for PROSE ONLY - prompts, briefs, drafts, rewrites. For work that touches files, run the
#     subagents on `opencode-go` + `deepseek-v4.1-flash` (delegation.model) or use `task` here.
#
# Usage:  free_text.sh <instruction> <out-file> [attach-file ...]
# Example: free_text.sh "Draft the design prompt for round 2" out.md docs/specs/ui-redesign-round2.md
set -u
instr="${1:?usage: free_text.sh <instruction> <out-file> [attach ...]}"
out="${2:?usage: free_text.sh <instruction> <out-file> [attach ...]}"
shift 2 || true
model="${FREE_MODEL:-opencode/deepseek-v4.1-flash-free}"
args=(run --model "$model" "$instr")
for f in "$@"; do args+=(-f "$f"); done
mkdir -p "$(dirname "$out")"
timeout "${FREE_TIMEOUT:-600}" opencode "${args[@]}" >"$out.raw" 2>&1
rc=$?
# opencode prints a small banner before the answer and colours its output; strip both, keep the text.
sed -e 's/\x1b\[[0-9;]*m//g' "$out.raw" | grep -av '^>' | grep -av '^[[:space:]]*$' >"$out"
if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
	echo "==> FREE-TEXT FAILED: rc=$rc (see $out.raw)"
	exit 1
fi
echo "==> FREE-TEXT DONE $out ($(wc -c <"$out") bytes, model $model)"
