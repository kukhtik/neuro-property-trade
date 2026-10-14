#!/usr/bin/env bash
# Build the shippable product into dist/:
#
#   dist/Neuro Property Trade.exe   the desktop game (host runs this)
#   dist/site/                      the web build + landing page (friends open this)
#   dist/README.txt                 how to play, in Russian, for someone who got the folder
#   dist/host.bat                   double-click: start the host match
#   dist/serve.bat                  double-click: serve the site to the network
#
# Everything here is verified by running it: an export that opens to a black window, or a web
# build that never boots, is worse than no build at all.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cd "$repo" || exit 1

godot="$(bash tools/ci/godot_bin.sh)"
if [ -z "$godot" ]; then
	echo "build_all: no Godot — run tools/ci/fetch_godot.sh first" >&2
	exit 1
fi

dist="$repo/dist"
echo "=== собираю в $dist ==="
rm -rf "$dist"
mkdir -p "$dist/site"

# --- 1. desktop ---------------------------------------------------------------
# Kit staging lives under build/kit/ — NOT in build/windows|build/web: those two paths used to
# hold the pre-swap archive watched by HG-11; the archive was retired on 2026-10-15 (see
# docs/restoration/README.md) and freshness now governs build/current only.
echo "[1/4] экспорт .exe"
mkdir -p "$repo/build/kit/windows"
# Godot needs a NATIVE path for the output; MSYS-style "/c/..." is rejected.
OUT="$(cd "$repo/build/kit/windows" && (pwd -W 2>/dev/null || pwd))"
"$godot" --headless --path game --import >/dev/null 2>&1
"$godot" --headless --path game --export-release "Windows Desktop" "$OUT/NeuroPropertyTrade.exe" 2>&1 | tail -2
if [ ! -f "$repo/build/kit/windows/NeuroPropertyTrade.exe" ]; then
	echo "build_all: the .exe was not produced" >&2
	exit 1
fi
cp "$repo/build/kit/windows/NeuroPropertyTrade.exe" "$dist/Neuro Property Trade.exe"

# --- 2. web -------------------------------------------------------------------
echo "[2/4] экспорт web"
mkdir -p "$repo/build/kit/web"
OUTW="$(cd "$repo/build/kit/web" && (pwd -W 2>/dev/null || pwd))"
"$godot" --headless --path game --export-release "Web" "$OUTW/index.html" 2>&1 | tail -2
bash tools/ci/verify_web_build.sh build/kit/web || { echo "build_all: the web bundle is not bootable" >&2; exit 1; }
cp -r "$repo/build/kit/web/." "$dist/site/"

# --- 3. launchers -------------------------------------------------------------
echo "[3/4] ярлыки"
# A .bat with CRLF, or Windows will not run it.
printf '@echo off\r\n' > "$dist/host.bat"
printf 'chcp 65001 >nul\r\n' >> "$dist/host.bat"
printf 'echo Запускаю партию. Покажу адрес и ссылки для друзей.\r\n' >> "$dist/host.bat"
printf 'echo.\r\n' >> "$dist/host.bat"
printf '"%%~dp0Neuro Property Trade.exe" -- --autostart --smoke-drive --smoke-seats=4 --remote-seats=3 --server-bind=0.0.0.0\r\n' >> "$dist/host.bat"
printf 'pause\r\n' >> "$dist/host.bat"

printf '@echo off\r\n' > "$dist/serve.bat"
printf 'chcp 65001 >nul\r\n' >> "$dist/serve.bat"
printf 'echo Раздаю игру по сети. Адрес показан ниже.\r\n' >> "$dist/serve.bat"
printf 'echo.\r\n' >> "$dist/serve.bat"
printf 'python "%%~dp0serve.py" 8080 --root "%%~dp0site"\r\n' >> "$dist/serve.bat"
printf 'pause\r\n' >> "$dist/serve.bat"

# --- 4. instructions ----------------------------------------------------------
echo "[4/4] инструкция"
cp "$repo/tools/serve.py" "$dist/serve.py"
cp "$repo/tools/host_match.py" "$dist/host_match.py"
cp "$repo/dist_readme.txt" "$dist/README.txt" 2>/dev/null || true

echo
echo "=== готово ==="
ls -la "$dist" | tail -8
echo
echo "exe: $(du -h "$dist/Neuro Property Trade.exe" 2>/dev/null | cut -f1)"
echo "site: $(du -sh "$dist/site" 2>/dev/null | cut -f1)"
