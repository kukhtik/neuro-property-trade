#!/usr/bin/env python3
"""Mock Neuro SDK websocket server for HG-08 (docs/restoration/gates.md).

Speaks just enough of the vendored addon's protocol to prove an SDK seat can PLAY:
  server -> client on connect:  {"command":"startup","data":{"session":{"characterId":...}}}
  client -> server:             {"command":"startup"...} / "actions/register" / "context" /
                                "actions/force" (with the offered action names) / "action/result"
  on every force the mock answers ONE offered action (priority: roll_dice, pass_on_purchase,
  buy_property, use_jail_card, pay_jail_fine, ...), so the seat never stalls.

Everything it sees is printed line by line - the shell gate keeps that log as evidence
("mock: force [...] -> action roll_dice id=7").

Runs until the client goes away or --timeout seconds pass. Stdlib only (socket + hashlib +
base64): no pip, no extra deps, works in CI.
"""
import base64
import hashlib
import json
import socket
import struct
import sys
import threading
import time

ACTION_PRIORITY = [
    "roll_dice", "pass_on_purchase", "buy_property", "use_jail_card", "pay_jail_fine",
    "sell_house", "mortgage_property", "unmortgage_property", "build_house",
    "respond_trade", "propose_trade", "bid_auction",
]
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def log(msg):
    print("mock: %s" % msg, flush=True)


def read_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def read_frame(sock):
    hdr = read_exact(sock, 2)
    fin_op = hdr[0]
    opcode = fin_op & 0x0F
    masked = hdr[1] & 0x80
    length = hdr[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", read_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack(">Q", read_exact(sock, 8))[0]
    mask = read_exact(sock, 4) if masked else b"\x00\x00\x00\x00"
    payload = read_exact(sock, length) if length else b""
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def send_frame(sock, payload):
    data = payload.encode("utf-8")
    header = bytearray([0x81])
    length = len(data)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header += struct.pack(">H", length)
    else:
        header.append(127)
        header += struct.pack(">Q", length)
    sock.sendall(bytes(header) + data)


def send_json(sock, obj):
    log("-> %s" % json.dumps(obj, ensure_ascii=False)[:160])
    send_frame(sock, json.dumps(obj))


def handshake(sock):
    req = b""
    while b"\r\n\r\n" not in req:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("closed during handshake")
        req += chunk
    key = ""
    for line in req.decode("latin1").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    sock.sendall((
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n" % accept
    ).encode())
    log("handshake ok")


def pick_action(actions):
    for name in ACTION_PRIORITY:
        if name in actions:
            return name
    return actions[0] if actions else ""


def serve_one(sock, action_counter):
    """One client connection: the whole exchange. Returns when it ends."""
    handshake(sock)
    # INVITE LATENCY (HG-08): the game registers the offered actions, then sends the force. The gap
    # between the two IS the invitation delay the seat feels: it used to be exactly `turn_timer`
    # (the vendored ActionWindow waited out its force timeout before inviting anybody).
    first_cmd_t = None
    first_force_t = None
    send_json(sock, {
        "command": "startup",
        "game": "mock",
        "data": {"session": {"characterId": "mock-neuro", "displayName": "Mock Neuro"}},
    })
    while True:
        opcode, payload = read_frame(sock)
        if opcode == 0x8:  # close
            log("client closed")
            return
        if opcode not in (0x1, 0x2):
            continue
        try:
            msg = json.loads(payload.decode("utf-8"))
        except ValueError:
            log("<- unparsable frame (%d bytes)" % len(payload))
            continue
        command = str(msg.get("command", ""))
        data = msg.get("data", {}) if isinstance(msg.get("data"), dict) else {}
        if first_cmd_t is None and command != "startup":
            first_cmd_t = time.time()
        if command == "actions/force":
            if first_force_t is None:
                first_force_t = time.time()
                if first_cmd_t is not None:
                    log("INVITE_LATENCY=%.3f (%s -> first actions/force)"
                        % (first_force_t - first_cmd_t, command))
            # the wire key is `action_names` (ActionsForce._get_data); `actions` is only the
            # REGISTER message's key - reading the wrong one made the first version answer
            # nothing and the seat stayed awaiting forever.
            offered = data.get("action_names", data.get("actions", []))
            if isinstance(offered, list) and offered and isinstance(offered[0], dict):
                offered = [str(a.get("name", "")) for a in offered]
            name = pick_action([str(a) for a in offered])
            log("<- force %s (query: %s) -> action %s" % (json.dumps(offered, ensure_ascii=False)[:120],
                                                          str(data.get("query", ""))[:60], name))
            if name == "":
                continue
            action_counter[0] += 1
            params = "{}"
            if name == "respond_trade":
                params = json.dumps({"accept": False})
            elif name == "bid_auction":
                params = json.dumps({"amount": 1})   # a floor bid; refusal is fine, retries follow
            send_json(sock, {
                "command": "action",
                "game": "mock",
                "data": {"id": "mock-%d" % action_counter[0], "name": name, "data": params},
            })
        elif command == "action/result":
            log("<- result %s" % json.dumps(data, ensure_ascii=False)[:120])
        else:
            log("<- %s %s" % (command, json.dumps(data, ensure_ascii=False)[:120]))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(4)
    real_port = server.getsockname()[1]
    print("MOCK_PORT=%d" % real_port, flush=True)
    log("listening on 127.0.0.1:%d (timeout %.0fs)" % (real_port, timeout))
    deadline = time.time() + timeout
    counter = [0]
    server.settimeout(1.0)
    while time.time() < deadline:
        try:
            client, addr = server.accept()
        except socket.timeout:
            continue
        log("client from %s:%d" % addr)
        try:
            serve_one(client, counter)
        except (ConnectionError, OSError) as exc:
            log("connection ended: %s" % exc)
        finally:
            client.close()
            log("actions answered total: %d" % counter[0])
        if counter[0] > 0:
            break   # one answered client is all the gate needs
    log("done (%d actions answered)" % counter[0])
    server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
