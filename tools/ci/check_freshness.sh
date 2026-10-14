#!/usr/bin/env bash
# HG-11(b) - are the canonical artifacts newer than the code they claim to contain?
#
# THE RULE (docs/restoration/README.md, hard rule 5): an artifact and a frame are rebuilt in the
# same run that reports on them. The audit's proof that this did not hold: `build/windows/
# *.exe` (15:22) and `build/web/` (15:33) were OLDER than the interface swap commit (18:52)
# and still carried the archived UI - while reports kept pointing at them.
#
# Freshness window: the last commit that touched SHIPPING code. `game/tools` (probe tooling)
# and `game/tests` (the suite) do not ship inside the export, so they do not age an artifact.
#
# An artifact may be deliberately old - but only by being LISTED with a reason in
# tools/ci/freshness_allowlist.txt. "Stale and unlisted" is red.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
allow="$repo/tools/ci/freshness_allowlist.txt"

# `git -C` is a NATIVE binary: it cannot open an MSYS `/c/...` path (the same trap as godot),
# so the repo is handed to it in `C:/...` form.
repo_win="$(cd "$repo" && pwd -W 2>/dev/null || printf '%s' "$repo")"
code_ts="$(git -C "$repo_win" log -1 --format=%ct -- game ":(exclude)game/tools" ":(exclude)game/tests" 2>/dev/null || true)"
code_sha="$(git -C "$repo_win" log -1 --format=%h -- game ":(exclude)game/tools" ":(exclude)game/tests" 2>/dev/null || true)"
if [ -z "$code_ts" ]; then
	echo "==> FRESHNESS FAILED: cannot read the last shipping-code commit (is this a git checkout?)"
	exit 1
fi
echo "==> freshness window: shipping code as of $code_sha ($(date -d "@$code_ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "@$code_ts"))"

stale=0
checked=0
fresh=0
archived=0
shopt -s nullglob
paths=("$repo"/build/windows/*.exe "$repo"/build/web/index.html)
for f in "${paths[@]}"; do
	[ -f "$f" ] || continue
	checked=$((checked + 1))
	rel="${f#"$repo"/}"
	mtime="$(stat -c %Y "$f")"
	size="$(stat -c %s "$f")"
	# allowlisted?
	reason=""
	if [ -f "$allow" ]; then
		while IFS='|' read -r glob rsn; do
			case "$glob" in \#*|"") continue ;; esac
			# shellcheck disable=SC2254
			case "$rel" in $glob) reason="$rsn" ;; esac
		done <"$allow"
	fi
	if [ -n "$reason" ]; then
		archived=$((archived + 1))
		echo "ARCHIVED $rel ($size bytes, mtime $(date -d "@$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$mtime"))"
		echo "         reason: $reason"
	elif [ "$mtime" -ge "$code_ts" ]; then
		fresh=$((fresh + 1))
		echo "FRESH    $rel ($size bytes, mtime $(date -d "@$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$mtime"))"
	else
		stale=$((stale + 1))
		echo "STALE    $rel is OLDER than the last shipping-code commit ($code_sha) and is not on the allowlist"
	fi
done
if [ "$checked" -eq 0 ]; then
	echo "==> FRESHNESS note: no canonical artifacts in build/ - nothing to check (fresh runs export their own beside)"
	echo "==> FRESHNESS ok (0 artifacts)"
	exit 0
fi
if [ "$stale" -ne 0 ]; then
	echo "==> FRESHNESS FAILED: $stale artifact(s) are older than the code they sit next to"
	exit 1
fi
echo "==> FRESHNESS ok ($checked artifact(s): $fresh fresh, $archived archived with a reason)"
exit 0
