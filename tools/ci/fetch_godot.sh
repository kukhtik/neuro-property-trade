#!/usr/bin/env bash
# Fetch the PINNED Godot editor build into .tools/godot/ (sha512-verified).
#
#   tools/ci/fetch_godot.sh [--force]
#
# The version comes from .tools/godot-version (single source of truth shared with
# CI, the oracle and docs/infra.md). The artifact is downloaded from the official
# godotengine/godot GitHub release and checked against that release's
# SHA512-SUMS.txt BEFORE anything is unpacked or executed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.tools/godot-version")"
DEST="$ROOT/.tools/godot"
FORCE="${1:-}"

case "$(uname -s)" in
  Linux)  ASSET="Godot_v${VERSION}-stable_linux.x86_64.zip";    BIN="Godot_v${VERSION}-stable_linux.x86_64" ;;
  Darwin) ASSET="Godot_v${VERSION}-stable_macos.universal.zip"; BIN="Godot.app/Contents/MacOS/Godot" ;;
  MINGW*|MSYS*|CYGWIN*) ASSET="Godot_v${VERSION}-stable_win64.exe.zip"; BIN="Godot_v${VERSION}-stable_win64_console.exe" ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 2 ;;
esac

BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"

if [ -x "$DEST/$BIN" ] && [ "$FORCE" != "--force" ]; then
  echo "Godot ${VERSION} already present: $DEST/$BIN"
  exit 0
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> downloading $ASSET"
curl -fsSL --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET"
curl -fsSL --retry 3 -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"

echo "==> verifying sha512"
EXPECTED="$(grep -F "$ASSET" "$TMP/SHA512-SUMS.txt" | awk '{print $1}' | head -1)"
if [ -z "$EXPECTED" ]; then
  echo "no checksum entry for $ASSET in SHA512-SUMS.txt" >&2
  exit 1
fi
ACTUAL="$(sha512sum "$TMP/$ASSET" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "CHECKSUM MISMATCH for $ASSET" >&2
  echo "  expected $EXPECTED" >&2
  echo "  actual   $ACTUAL" >&2
  exit 1
fi
echo "    ok: $ACTUAL"

echo "==> unpacking into .tools/godot"
rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q -o "$TMP/$ASSET" -d "$DEST"
chmod +x "$DEST"/* 2>/dev/null || true
chmod +x "$DEST/Godot.app/Contents/MacOS/Godot" 2>/dev/null || true

echo "==> done"
"$ROOT/tools/ci/godot_bin.sh"
"$("$ROOT/tools/ci/godot_bin.sh")" --version
