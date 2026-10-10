#!/usr/bin/env bash
# Install the PINNED Godot export templates (needed for the Web build).
#
#   tools/ci/fetch_templates.sh
#
# Templates land in the engine's user data dir:
#   Linux/CI : ~/.local/share/godot/export_templates/<version>.stable/
#   Windows  : %APPDATA%/Godot/export_templates/<version>.stable/
#   macOS    : ~/Library/Application Support/Godot/export_templates/<version>.stable/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.tools/godot-version")"
TPZ="Godot_v${VERSION}-stable_export_templates.tpz"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) TEMPLATES="${APPDATA:-$HOME/AppData/Roaming}/Godot/export_templates" ;;
  Darwin) TEMPLATES="$HOME/Library/Application Support/Godot/export_templates" ;;
  *) TEMPLATES="$HOME/.local/share/godot/export_templates" ;;
esac
DEST="$TEMPLATES/${VERSION}.stable"

if [ -f "$DEST/web_release.zip" ]; then
  echo "templates ${VERSION}.stable already installed: $DEST"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "==> downloading $TPZ (large, ~1.2 GB)"
curl -fsSL --retry 3 -o "$TMP/templates.tpz" "$BASE/$TPZ"
curl -fsSL --retry 3 -o "$TMP/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"

echo "==> verifying sha512"
EXPECTED="$(grep -F "$TPZ" "$TMP/SHA512-SUMS.txt" | awk '{print $1}' | head -1)"
ACTUAL="$(sha512sum "$TMP/templates.tpz" | awk '{print $1}')"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "CHECKSUM MISMATCH for $TPZ" >&2
  exit 1
fi
echo "    ok: $ACTUAL"

echo "==> installing into $DEST"
mkdir -p "$DEST"
unzip -q -o "$TMP/templates.tpz" -d "$TMP/x"
cp -r "$TMP/x/templates/." "$DEST/"
ls "$DEST" | head -20
echo "==> done"
