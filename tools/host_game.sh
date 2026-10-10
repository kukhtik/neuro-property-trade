#!/usr/bin/env bash
# Host a networked match of Neuro Property Trade: print a join address and one seat token
# per remote player, and keep serving until you stop it.
#
# WHY A SCRIPT: the host needs three things that are easy to get wrong by hand, and each wrong
# combination produced a silent no-connection in testing:
#   * `--server-bind=0.0.0.0` — without it the host listens on 127.0.0.1 and NO other machine
#     can reach it, no matter what address you hand out;
#   * the printed address must be a real LAN address, not the bind instruction (`0.0.0.0` is
#     not something a client can connect TO);
#   * each remote seat needs its OWN token, and they are minted per match, so they cannot be
#     prepared in advance.
#
# Usage:
#   tools/host_game.sh [remote_players] [port]
#     remote_players  how many friends join from other machines (default 2)
#     port            TCP port to listen on (default 9080)
#
# Examples:
#   tools/host_game.sh              # 2 friends, port 9080
#   tools/host_game.sh 3 9100       # 3 friends, port 9100
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
godot="$(bash "$here/ci/godot_bin.sh")"

if [ -z "$godot" ]; then
	echo "host_game: no Godot binary — run tools/ci/fetch_godot.sh first" >&2
	exit 1
fi

friends="${1:-2}"
port="${2:-9080}"

if ! [[ "$friends" =~ ^[0-9]+$ ]] || [ "$friends" -lt 1 ]; then
	echo "host_game: remote_players must be a positive number (got '$friends')" >&2
	exit 2
fi
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
	echo "host_game: port must be 1024-65535 (got '$port')" >&2
	exit 2
fi

seats=$((friends + 1))
logdir="$repo/build/host_game"
rm -rf "$logdir"
mkdir -p "$logdir"

cat <<EOF
=== Нейро Property Trade: хост партии ===
Удалённых мест: $friends   Порт: $port   Всего мест: $seats (вы + $friends)

Сейчас напечатаю адрес и токены. Каждому другу отправьте ЕГО токен и адрес.
Остановить партию: Ctrl+C
EOF

# Run in the background so the tokens can be printed as soon as the server is up, then follow the
# log. `--server-bind=0.0.0.0` is what makes the port reachable from other machines.
# `--path` must be RELATIVE: under MSYS `"$repo/game"` reads as `/c/Users/...` and the native
# Godot binary aborts with "Invalid project path specified" — the exact trap recorded in the
# dev skill, walked into again here.
cd "$repo" || exit 1
"$godot" --path game -- --autostart --smoke-drive \
	--smoke-seats="$seats" --remote-seats="$friends" --server-bind=0.0.0.0 --server-port="$port" \
	--log-dir="$(cd "$logdir" && (pwd -W 2>/dev/null || pwd))" &
host_pid=$!

cleanup() { kill "$host_pid" 2>/dev/null; }
trap cleanup EXIT INT TERM

# Wait for the server line instead of guessing a sleep length.
for _ in $(seq 1 60); do
	if grep -qa "SERVER ready" "$logdir"/*.log 2>/dev/null; then
		break
	fi
	sleep 0.5
done

addr="$(grep -ahoE "ws://[0-9.]+:[0-9]+" "$logdir"/*.log 2>/dev/null | head -1)"
tokens="$(grep -ahoE "SERVER seat=[0-9]+ token=[a-f0-9]+" "$logdir"/*.log 2>/dev/null | sort -u)"

echo
if [ -z "$addr" ]; then
	echo "НЕ ДОЖДАЛСЯ сервера. Лог: $logdir" >&2
	exit 1
fi

echo "АДРЕС ДЛЯ ВСЕХ:  $addr"
echo
echo "ТОКЕНЫ (по одному на друга — не перепутайте):"
i=0
while IFS= read -r line; do
	[ -z "$line" ] && continue
	tok="${line##*token=}"
	seat="${line#SERVER seat=}"
	seat="${seat%% *}"
	i=$((i + 1))
	echo "  Друг $i  ->  --seat=$tok --host=$addr"
done <<< "$tokens"

if [ "$i" -eq 0 ]; then
	echo "Токенов нет — что-то не так. Лог: $logdir" >&2
	exit 1
fi

cat <<EOF

ЧТО ОТПРАВИТЬ ДРУГУ (он запускает игру из папки с игрой):
  godot --path game -- --seat=<его_токен> --host=$addr

ИЛИ в браузере (если веб-сборка раздаётся по HTTP с заголовками COOP/COEP):
  http://<адрес_раздачи>/index.html?seat=<его_токен>&host=$addr

Подробности и разбор проблем: docs/how-to-play.md
Партия уже идёт — вы играете место 1.
EOF

wait "$host_pid"
