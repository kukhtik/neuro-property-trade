extends Node
## Remote seat driver — a player in a browser, reached over the game server.
##
## WHAT IT IS NOT: it does not decide anything. Unlike `ai_driver` (which picks a
## move) this driver is a TRANSPORT. It receives the seat's own projection from
## the host and forwards whatever the browser sends back to `push_intent`. The
## engine remains the only thing that decides whether a move is legal.
##
## WHY THIS SHAPE: the browser cannot be trusted with game state, and it must not
## need any. It gets `legal_actions` and a projection; it returns an intent. If
## the socket dies, the engine keeps running — the match does not depend on the
## client being alive (that is what makes a dropped connection harmless).
##
## The host side of the same socket is `server/game_server.gd`, which owns the
## two-channel split. This driver only ever speaks for its OWN seat.

const Proto := preload("res://server/protocol.gd")

var engine
var seat

## Where to connect. Set by whoever spawns the driver.
var url := "ws://127.0.0.1:9080"
## The seat token this driver may act as. Minted by the server.
var token := ""

var _peer: WebSocketPeer
var _connected := false
var _intent_seq := 0
var _last_projection: Dictionary = {}
## The most recent verdict the host sent, for diagnostics (never a decision).
var _last_verdict: Dictionary = {}
## Non-zero once the seat has been silent too long: the manager then auto-passes.
var idle_ms := 0

signal projection_received(pid: int, proj: Dictionary)


func setup(eng, s) -> void:
	engine = eng
	seat = s


## Hand the driver its connection details. Called before the first poll.
func configure(host_url: String, seat_token: String) -> void:
	url = host_url
	token = seat_token


func connect_to_host() -> bool:
	_peer = WebSocketPeer.new()
	var err := _peer.connect_to_url(url)
	if err != OK:
		push_warning("RemoteDriver: cannot connect to %s (%d)" % [url, err])
		return false
	set_process(true)
	return true


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_send_hello()
			while _peer.get_available_packet_count() > 0:
				_handle(Proto.decode(_peer.get_packet().get_string_from_utf8()))
		WebSocketPeer.STATE_CLOSED:
			_connected = false


func is_connected_to_host() -> bool:
	return _connected


# --- outbound -----------------------------------------------------------------

func _send_hello() -> void:
	_send(Proto.hello(token, "player"))


## Ask the host for the current state. The reconnect path: state never lives on
## the client, so recovering is just "ask again".
func request_state() -> void:
	if _connected:
		_send_hello()


## Submit an intent for THIS seat. Returns a local sequence id the verdict will
## echo back, so a caller can match the answer to the request.
func submit(action: String, params: Dictionary = {}) -> String:
	if not _connected:
		return ""
	_intent_seq += 1
	var id := "i%d" % _intent_seq
	_send(Proto.intent(id, action, params))
	return id


func _send(msg: Dictionary) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(Proto.encode(msg))


# --- inbound ------------------------------------------------------------------

func _handle(msg: Dictionary) -> void:
	if msg.is_empty():
		return
	match str(msg.get("t", "")):
		"projection":
			_last_projection = msg.get("data", {})
			projection_received.emit(int(seat.pid) if seat != null else -1,
				_last_projection)
		"event":
			# events are for presentation only; the engine already applied them
			pass
		"verdict", "reject":
			# keep the last answer so a caller can see WHY nothing happened; the
			# engine already applied or refused it
			_last_verdict = msg


## The last projection the host pushed. Empty until the first one arrives.
func projection() -> Dictionary:
	return _last_projection


## Legal actions for this seat, as the HOST reported them. The client shows
## buttons from this and never invents its own rules.
func legal_actions() -> Array:
	return _last_projection.get("legal", []) as Array


func disconnect_from_host() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_connected = false
