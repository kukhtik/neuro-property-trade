class_name RemoteSession
extends Node
## A CLIENT that plays a seat owned by somebody else's engine.
##
## This is the browser's whole game logic: hold a socket, render what the host
## sends, forward what the player clicks. It owns no engine and no rules, so it
## cannot desync and cannot cheat — the host validates every intent and the
## verdict comes back on the same wire.
##
## It deliberately does NOT reuse the host's GameView internals: the host side
## owns an engine, and a client must not have one to reach for.

const Proto := preload("res://server/protocol.gd")

signal joined(pid: int)
signal state_received(proj: Dictionary)
signal verdict_received(id: String, ok: bool, reason: String)
signal connection_lost

var url := ""
var token := ""
var pid := -1
var _peer: WebSocketPeer
var _open := false
var _rx := 0
var _hello_sent := false
var _seq := 0
## The last state the host pushed. A client's only source of truth.
var _projection: Dictionary = {}


func join(host_url: String, seat_token: String) -> void:
	url = host_url
	token = seat_token
	_peer = WebSocketPeer.new()
	var err := _peer.connect_to_url(url)
	if err != OK:
		push_error("RemoteSession: cannot reach %s (%d)" % [url, err])
		connection_lost.emit()
		return
	set_process(true)


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _open:
				_open = true
				_send(Proto.hello(token, "player"))
				_hello_sent = true
			while _peer.get_available_packet_count() > 0:
				_handle(Proto.decode(_peer.get_packet().get_string_from_utf8()))
		WebSocketPeer.STATE_CLOSED:
			if _open:
				_open = false
				connection_lost.emit()


func is_joined() -> bool:
	return _open and pid >= 0


func projection() -> Dictionary:
	return _projection


## What this seat may do — as the HOST reported it. The client never computes
## this, because computing it would mean owning the rules.
func legal_actions() -> Array:
	return _projection.get("legal", []) as Array


## Send an action. Returns the intent id the verdict will echo, or "" if the
## socket is down — in which case nothing happened and nothing is queued.
func act(action: String, params: Dictionary = {}) -> String:
	if not is_joined():
		return ""
	_seq += 1
	var id := "c%d" % _seq
	_send(Proto.intent(id, action, params))
	return id


func _send(msg: Dictionary) -> void:
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(Proto.encode(msg))


func _handle(msg: Dictionary) -> void:
	if msg.is_empty():
		return
	match str(msg.get("t", "")):
		"hello_ok":
			pid = int(msg.get("pid", -1))
			joined.emit(pid)
		"projection":
			_projection = msg.get("data", {})
			_rx += 1
			# a client that receives nothing looks identical to one that is broken, so
			# the first few frames are announced; after that it stays quiet
			if _rx <= 3:
				print("PROJ #%d legal=%d" % [_rx, (_projection.get("legal", []) as Array).size()])
			state_received.emit(_projection)
		"verdict", "reject":
			verdict_received.emit(str(msg.get("id", "")), bool(msg.get("ok", false)),
				str(msg.get("reason", "")))
