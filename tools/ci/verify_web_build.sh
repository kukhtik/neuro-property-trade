#!/usr/bin/env bash
# Verify a Godot Web export directory is a bootable bundle.
#
#   tools/ci/verify_web_build.sh build/web
#
# Checks the artifact contract (index.html + .wasm + .pck + the JS loader) and
# that the wasm really is a WebAssembly module. This is a BUILD gate, not a
# gameplay gate: the in-browser playthrough is judged separately (frame capture
# under SwiftShader/llvmpipe is a known-unreliable environment - docs/plan.md).
set -euo pipefail

DIR="${1:?usage: verify_web_build.sh <export-dir>}"
fail=0

for f in index.html index.wasm index.pck; do
  if [ ! -f "$DIR/$f" ]; then echo "FAIL: missing $DIR/$f"; fail=1; fi
done
if ! ls "$DIR"/index.js >/dev/null 2>&1; then echo "FAIL: missing $DIR/index.js"; fail=1; fi

size_of() { stat -c%s "$1" 2>/dev/null || wc -c < "$1"; }

if [ -f "$DIR/index.wasm" ]; then
  magic="$(head -c 4 "$DIR/index.wasm" | od -An -tx1 | tr -d ' \n')"
  if [ "$magic" != "0061736d" ]; then
    echo "FAIL: index.wasm magic is $magic (want 0061736d)"; fail=1
  fi
  size="$(size_of "$DIR/index.wasm")"
  if [ "$size" -lt 1000000 ]; then echo "FAIL: index.wasm suspiciously small ($size bytes)"; fail=1; fi
fi

if [ -f "$DIR/index.pck" ]; then
  size="$(size_of "$DIR/index.pck")"
  if [ "$size" -lt 10000 ]; then echo "FAIL: index.pck suspiciously small ($size bytes)"; fail=1; fi
fi

if [ "$fail" != "0" ]; then exit 1; fi
echo "==> web bundle OK ($(du -sh "$DIR" | cut -f1))"
