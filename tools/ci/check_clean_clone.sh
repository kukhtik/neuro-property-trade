#!/usr/bin/env bash
# Infrastructure self-test: does a PRISTINE clone build and pass the oracle?
#
#   tools/ci/check_clean_clone.sh
#
# Clones HEAD into a temp dir (so the working tree's .tools/ and game/.godot/ are
# NOT available), fetches the pinned engine there and runs the oracle. Green
# means a contributor with nothing but git+bash+curl+unzip can reproduce the
# suite - i.e. the "fresh clone is broken" class of bug cannot come back.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> cloning HEAD into $WORK/npt"
git clone -q --depth 1 "file://$ROOT" "$WORK/npt" || { echo "FAIL: clone failed"; exit 1; }
cd "$WORK/npt"

echo "==> build artifacts must NOT leak into the clone"
if [ -e game/.godot ]; then echo "FAIL: game/.godot/ leaked into the clone"; exit 1; fi
if [ -e .tools ]; then
  stray="$(ls -A .tools | grep -v '^godot-version$' || true)"
  if [ -n "$stray" ]; then echo "FAIL: .tools/ has non-tracked content: $stray"; exit 1; fi
fi

VERSION="$(cat .tools/godot-version)"
echo "==> pinned version: $VERSION"
LOCAL_BIN="$ROOT/.tools/godot/Godot_v${VERSION}-stable_win64_console.exe"
if [ -x "$LOCAL_BIN" ]; then
  echo "==> reusing the locally verified engine (skips an 86 MB download)"
  cp -r "$ROOT/.tools/godot" "$WORK/npt/.tools/godot"
else
  tools/ci/fetch_godot.sh
fi

tools/ci/run_tests.sh
STATUS=$?
if [ "$STATUS" = "0" ]; then echo "==> CLEAN-CLONE CHECK PASSED"; else echo "==> CLEAN-CLONE CHECK FAILED"; fi
exit "$STATUS"
