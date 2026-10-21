#!/usr/bin/env bash
# MERGE-REGISTRY - take the gate registrations the subagents wrote as separate
# `.registry` files and put them into the gate registry.
#
# WHY THIS EXISTS. The subagents work in PARALLEL and share ONE checkout. If each
# of them edited `tools/ci/run_gates.sh`, they would overwrite each other - the
# classic lost-update, and the loser would not know it lost anything. So the rule
# is: a subagent never touches the registry; it writes a `.registry` file with one
# line, and the PARENT merges them.
#
# The merge is idempotent: a line that is already in the registry is skipped, and
# a registration for a gate that does not exist on disk is a FAILURE (a gate that
# cannot run must not be in the registry - it would be a green that proves nothing).
#
# Usage: bash tools/ci/merge_registry.sh [--check]
#   --check  report what WOULD be merged and fail if anything is broken, without
#            touching the registry.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
registry="$repo/tools/ci/run_gates.sh"
gatedir="$repo/tools/ci/gates"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

fails=0
declare -a adds=()

for rf in "$gatedir"/*.registry; do
	[ -e "$rf" ] || continue
	name="$(basename "$rf" .registry)"
	while IFS= read -r line; do
		# skip blanks and comments
		case "$line" in
			""|\#*) continue ;;
		esac
		# the line must be ID|class|status|kind|target
		parts="$(printf '%s' "$line" | tr '|' ' ' | wc -w)"
		if [ "$parts" -ne 5 ]; then
			echo "==> MERGE-REGISTRY FAILED: $rf has a malformed line (want ID|class|status|kind|target): $line"
			fails=$((fails + 1))
			continue
		fi
		target="$(printf '%s' "$line" | cut -d'|' -f5)"
		# the gate must exist - a registration for a missing file is a green that
		# proves nothing, and it would fail later inside the runner anyway
		case "$target" in
			/*) path="$target" ;;
			*) path="$repo/$target" ;;
		esac
		if [ ! -e "$path" ]; then
			echo "==> MERGE-REGISTRY FAILED: $rf registers a gate that does not exist: $target"
			fails=$((fails + 1))
			continue
		fi
		# already in the registry? then it is merged already
		if grep -aqF "\"$line\"" "$registry"; then
			echo "    already in the registry: $line"
			continue
		fi
		# the id must not be taken by a DIFFERENT line
		id="$(printf '%s' "$line" | cut -d'|' -f1)"
		if grep -aqE "^\s*\"$id\|" "$registry"; then
			echo "==> MERGE-REGISTRY FAILED: the id '$id' is already in the registry with a different line"
			fails=$((fails + 1))
			continue
		fi
		adds+=("$line")
	done < "$rf"
done

if [ "${#adds[@]}" -eq 0 ]; then
	echo "==> MERGE-REGISTRY: nothing to merge"
	exit $((fails > 0 ? 1 : 0))
fi

echo "the registry would gain ${#adds[@]} line(s):"
for a in "${adds[@]}"; do
	echo "    $a"
done

if [ "$check_only" -eq 1 ]; then
	echo "==> MERGE-REGISTRY (--check): nothing was written"
	exit $((fails > 0 ? 1 : 0))
fi

if [ "$fails" -gt 0 ]; then
	echo "==> MERGE-REGISTRY FAILED: $fails problem(s) above - the registry was NOT touched"
	exit 1
fi

# insert them right after the last registration line, so the registry stays a
# readable list rather than a diff
tmp="$registry.tmp.$$"
awk -v additions="$(printf '%s\n' "${adds[@]}")" '
BEGIN { n = split(additions, a, "\n"); inserted = 0 }
{
	print
	if (!inserted && $0 ~ /^\s*"[A-Z0-9-]+\|[a-z]+\|required\|/) { last = NR }
}
END {
	# the additions go after the last registration line we saw
}
' "$registry" > "$tmp"

# simpler and safer: append the new lines right after the LAST registration line
last_line="$(grep -nE '^\s*"[A-Z0-9-]+\|[a-z]+\|(required|quarantine)\|' "$registry" | tail -1 | cut -d: -f1)"
if [ -z "$last_line" ]; then
	echo "==> MERGE-REGISTRY FAILED: the registry has no registration lines to anchor to"
	rm -f "$tmp"
	exit 1
fi
{
	head -n "$last_line" "$registry"
	for a in "${adds[@]}"; do
		printf '\t"%s"\n' "$a"
	done
	tail -n +$((last_line + 1)) "$registry"
} > "$tmp"

if ! bash -n "$tmp"; then
	echo "==> MERGE-REGISTRY FAILED: the merged registry does not parse - the original was NOT touched"
	rm -f "$tmp"
	exit 1
fi

mv "$tmp" "$registry"
echo "==> MERGE-REGISTRY: ${#adds[@]} line(s) merged into $registry"
