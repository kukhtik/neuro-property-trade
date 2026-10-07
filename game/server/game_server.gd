class_name GameServer
extends Node
## The authoritative network host for REMOTE seats (stage 1 of the full smoke).
##
## WHY IT EXISTS: the repo had no transport at all, so "players join from a
## browser" could not be verified — only pretended. This is the minimum server
## that makes the browser step real instead of a third local window.
##
## SHAPE — one host, TWO channels per player:
##
##   spectator   broadcast to everyone watching; carries the spectator
##               projection, which has no `private` and no `legal` section
##   seat/<tok>  personal to the owner of a seat; carries that seat's own
##               projection, including its private section and legal actions
##
## Two channels rather than one is STRUCTURAL spectator safety: private data has
## no shared channel it could leak into, so the guarantee does not depend on a
## filter being correct. (The engine already refuses to put private data in
## `for_spectator`; this makes it impossible to route it there by accident.)
##
## The client sends INTENTS ONLY. The server validates through the seat manager's
## `push_intent` (engine-authoritative, fail-closed) and broadcasts the RESULT.
## State lives in the engine alone, so a dropped connection cannot desync the
## match — a reconnect is answered with a full projection.
##
## Pure parts (message framing, token minting, channel routing) are separated
## into `protocol.gd` so they are testable without a socket.

const Protocol := preload("res://server/protocol.gd")
const ProjectionScript := preload("res://sdk/projection.gd")

signal served(intent_id: String, ok: bool, reason: String)

## Default port. 0 lets the OS pick a free one (used by the smoke so parallel
## runs never collide).
const DEFAULT_PORT := 9080

## How long a client may go silent before it is considered gone.
const IDLE_TIMEOUT_MS := 15000

var _tcp := TCPServer.new()
var _peers: Array = []          # of {id, peer, token, channel, last_seen}
var _next_peer_id := 1
var _port := 0

var engine = null
var manager = null              # SeatManager: the ONLY way an intent reaches the engine
var _tokens := {}               # seat_token -> pid

## The id used when a socket does not yet carry a token (it must `hello` first,
## or it is served the spectator channel).
const CHANNEL_SPECTATOR := "spectator"


func _ready() -> void:
	set_process(true)


## Bind and start listening. `port` 0 picks a free port; the real one is read
## back through `port()`.
func listen(port: int = DEFAULT_PORT, bind_address: String = "*") -> bool:
	var err := _tcp.listen(port, bind_address)
	if err != OK:
		push_error("GameServer: cannot listen on %d (%d)" % [port, err])
		return false
	_port = _tcp.get_local_port()
	return true


func port() -> int:
	return _port


## Wire the authoritative side. Called once after a match is built.
func bind_game(eng, mgr) -> void:
	engine = eng
	manager = mgr
	# ANY state change is pushed, whatever caused it — an admin edit or an AI
	# driver must reach the clients exactly like a remote intent does
	if manager != null and manager.has_signal("state_changed") 			and not manager.state_changed.is_connected(_on_state_changed):
		manager.state_changed.connect(_on_state_changed)
	if manager != null and manager.has_signal("events_emitted") 			and not manager.events_emitted.is_connected(_on_events_emitted):
		manager.events_emitted.connect(_on_events_emitted)


## Mint a seat token so a browser can claim a seat. One token per seat; the
## token IS the identity (there are no passwords — owning the seat is the right).
func mint_token(pid: int) -> String:
	var tok := Protocol.new_token(pid, engine)
	_tokens[tok] = pid
	return tok


func _process(_delta: float) -> void:
	if not _tcp.is_listening():
		return
	_accept_new()
	_poll_peers()


func _accept_new() -> void:
	while _tcp.is_connection_available():
		var peer := WebSocketPeer.new()
		var conn := _tcp.take_connection()
		if conn == null:
			return
		peer.accept_stream(conn)
		_peers.append({
			"id": _next_peer_id,
			"peer": peer,
			"token": "",
			"channel": CHANNEL_SPECTATOR,
			"last_seen": Time.get_ticks_msec(),
		})
		_next_peer_id += 1


func _poll_peers() -> void:
	var now := Time.get_ticks_msec()
	var alive: Array = []
	for entry in _peers:
		var peer: WebSocketPeer = entry["peer"]
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			continue
		if state == WebSocketPeer.STATE_OPEN:
			entry["last_seen"] = now
			while peer.get_available_packet_count() > 0:
				_handle_packet(entry, peer.get_packet().get_string_from_utf8())
		elif now - int(entry["last_seen"]) > IDLE_TIMEOUT_MS:
			peer.close()
			continue
		alive.append(entry)
	_peers = alive


# --- message handling ---------------------------------------------------------

func _handle_packet(entry: Dictionary, raw: String) -> void:
	var msg: Dictionary = Protocol.decode(raw)
	if msg.is_empty():
		return
	match str(msg.get("t", "")):
		"hello":
			_on_hello(entry, msg)
		"intent":
			_on_intent(entry, msg)
		"ping":
			_send(entry, {"t": "pong"})


## A client identifies itself. With a valid token it is bound to that seat's
## personal channel and immediately receives its own projection; without one it
## just watches.
func _on_hello(entry: Dictionary, msg: Dictionary) -> void:
	var tok: String = str(msg.get("token", ""))
	var pid: int = int(_tokens.get(tok, -1))
	if tok != "" and pid < 0:
		_send(entry, {"t": "reject", "reason": "bad_token"})
		return
	entry["token"] = tok
	entry["channel"] = CHANNEL_SPECTATOR if pid < 0 else "seat/%s" % tok
	_send(entry, {
		"t": "hello_ok",
		"profile": str(msg.get("profile", "player")),
		"pid": pid,
		"channel": entry["channel"],
	})
	# a fresh subscriber gets the FULL projection, then deltas — this is also the
	# reconnect path, which is why state never lives on the client
	_send_projection(entry)


## An intent from a seat owner. The engine decides; we only relay the verdict.
func _on_intent(entry: Dictionary, msg: Dictionary) -> void:
	var pid: int = int(_tokens.get(str(entry.get("token", "")), -1))
	var intent_id: String = str(msg.get("id", ""))
	if pid < 0:
		_send(entry, {"t": "reject", "id": intent_id, "reason": "not_seated"})
		served.emit(intent_id, false, "not_seated")
		return
	if manager == null:
		_send(entry, {"t": "reject", "id": intent_id, "reason": "engine_not_ready"})
		served.emit(intent_id, false, "engine_not_ready")
		return
	var res: Dictionary = manager.push_intent(pid, str(msg.get("action", "")),
		msg.get("params", {}))
	var ok: bool = bool(res.get("ok", false))
	_send(entry, {
		"t": "verdict", "id": intent_id, "ok": ok,
		"reason": str(res.get("reason", "")),
	})
	served.emit(intent_id, ok, str(res.get("reason", "")))
	# the manager's state_changed signal already pushed the new state


func _send_projection(entry: Dictionary) -> void:
	if engine == null:
		return
	_send(entry, {
		"t": "projection",
		"data": _projection_for(entry),
	})


## The projection a given socket is entitled to. A seated client gets its OWN
## (with private + legal); anyone else gets the spectator view.
func _projection_for(entry: Dictionary) -> Dictionary:
	var pid: int = int(_tokens.get(str(entry.get("token", "")), -1))
	if pid >= 0:
		return ProjectionScript.new().for_player(engine, pid)
	return ProjectionScript.new().for_spectator(engine)


# --- broadcasting -------------------------------------------------------------

## Called after any state change: push a fresh projection to every peer, at the
## level each one is entitled to.
func _broadcast_state() -> void:
	for entry in _peers:
		var peer: WebSocketPeer = entry["peer"]
		if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		_send_projection(entry)


## Relay one engine event to everyone. Events are spectator-safe by contract, so
## the same payload goes to both channels.
func broadcast_event(ev: Dictionary) -> void:
	for entry in _peers:
		var peer: WebSocketPeer = entry["peer"]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send(entry, {"t": "event", "data": ev})


## The manager says the state moved: push it to every peer at its own level.
func _on_state_changed(_spec: Dictionary) -> void:
	_broadcast_state()


## The manager says events happened: relay them. A spectator-safe event payload
## is the same for both channels.
func _on_events_emitted(events: Array) -> void:
	for ev in events:
		broadcast_event(ev)


func _send(entry: Dictionary, msg: Dictionary) -> void:
	var peer: WebSocketPeer = entry["peer"]
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(Protocol.encode(msg))


func peer_count() -> int:
	return _peers.size()


func seated_count() -> int:
	var n := 0
	for e in _peers:
		if str(e.get("channel", "")).begins_with("seat/"):
			n += 1
	return n


func close_all() -> void:
	for entry in _peers:
		var peer: WebSocketPeer = entry["peer"]
		peer.close()
	_peers.clear()
	_tcp.stop()
