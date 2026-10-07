class_name Protocol
extends RefCounted
## Pure message framing and token logic for GameServer. Deliberately socket-free:
## everything here is a pure function, so the wire contract can be tested without
## opening a port (and without two Godot instances).
##
## Frames are JSON objects with a short `t` (type) field. Short because they are
## sent on every delta and a match can emit hundreds.

## Message types, both directions. Kept here so client and server cannot drift.
const C2S := ["hello", "intent", "ping"]
const S2C := ["hello_ok", "projection", "event", "verdict", "reject", "pong"]


## Encode a message for the wire.
static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## Decode a frame. Returns {} for anything that is not a JSON object — a
## malformed frame must never crash the host.
static func decode(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.has("t"):
			return d
	return {}


## True when a frame is a valid client->server message.
static func is_valid_client_msg(msg: Dictionary) -> bool:
	return msg.has("t") and C2S.has(str(msg["t"]))


## A seat token. Deterministic given the engine's seed and the seat, so a
## restarted match with the same seed issues the same tokens (which is what makes
## a reconnect test reproducible).
##
## NOT a security boundary: the token identifies WHICH seat a socket may act as;
## it does not grant power the engine would not already allow. A forged token for
## seat N can only submit intents that seat N could submit anyway, and every one
## still goes through `legal_actions`.
static func new_token(pid: int, engine) -> String:
	var seed_part := "0"
	if engine != null and engine.settings != null:
		seed_part = str(engine.settings.rng_seed)
	var raw := "seat:%d:%s" % [pid, seed_part]
	return raw.sha256_text().substr(0, 16)


## The channel a token belongs to. `spectator` for anyone unseated.
static func channel_for(pid: int, token: String) -> String:
	if pid < 0 or token == "":
		return "spectator"
	return "seat/%s" % token


## Build a client intent frame. `id` echoes back in the verdict.
static func intent(id: String, action: String, params: Dictionary = {}) -> Dictionary:
	return {"t": "intent", "id": id, "action": action, "params": params}


## Build a hello frame.
static func hello(token: String, profile: String = "player") -> Dictionary:
	return {"t": "hello", "token": token, "profile": profile}
