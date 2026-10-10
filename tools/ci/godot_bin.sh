#!/usr/bin/env bash
# Print the path of the Godot binary this repo tests against.
#
# Resolution order:
#   1. $GODOT_BIN          (explicit override; CI images / other hosts)
#   2. .tools/godot/*      (the pinned local binary, see tools/ci/fetch_godot.sh)
#   3. godot on PATH       (last resort; version is NOT verified)
#
# The pin lives in .tools/godot-version so every runner uses one engine build:
# GDScript semantics - and therefore replay fingerprints - are only guaranteed
# within a single Godot build.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -n "${GODOT_BIN:-}" ]; then
  printf '%s\n' "$GODOT_BIN"
  exit 0
fi

# shellcheck disable=SC2206
CANDIDATES=(
  "$ROOT"/.tools/godot/Godot_v*-stable_linux.x86_64
  "$ROOT"/.tools/godot/Godot_v*-stable_win64_console.exe
  "$ROOT"/.tools/godot/Godot_v*-stable_win64.exe
  "$ROOT"/.tools/godot/Godot_v*-stable_macos.universal
)

for exe in "${CANDIDATES[@]}"; do
  if [ -x "$exe" ]; then
    printf '%s\n' "$exe"
    exit 0
  fi
done

if command -v godot >/dev/null 2>&1; then
  command -v godot
  exit 0
fi

echo "no Godot binary found: run tools/ci/fetch_godot.sh (or set GODOT_BIN)" >&2
exit 2
