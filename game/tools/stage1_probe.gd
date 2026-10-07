extends Node
## Stage-1 acceptance: does the server actually work over a real socket?
##
## The suite tests the pure protocol. This drives TWO REAL WebSocket clients
## against ONE server in a single run — the same shape the full smoke needs, just
## narrowed to the transport:
##
##   1. both clients connect and are greeted;
##   2. an UNSEATED client gets the spectator projection (no private, no legal);
##   3. a SEATED client gets its own projection (private + legal);
##   4. an intent from the seated client reaches the engine and the verdict comes
##      back with the engine's own answer (an illegal one is refused);
##   5. a state change reaches BOTH clients without them asking (push, not poll).
##
## Exit 0 = the transport is real.

const ServerScript := preload("res://server/game_server.gd")
const Proto := preload("res://server/protocol.gd")
const EngineScript := preload("res://core/engine.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const SeatManagerScript := preload("res://seats/seat_manager.gd")

var _fail := 0
var _server
var _manager
var _engine
var _token := ""
var _spectator: WebSocketPeer
var _seated: WebSocketPeer
var _spectator_inbox: Array = []
var _seated_inbox: Array = []


func _ready() -> void:
	print("=== Stage 1 acceptance: two real clients against one server ===")
	_build_game()
	if not _server.listen(0, "127.0.0.1"):
		_bad("server failed to bind")
		_finish()
		return
	var url := "ws://127.0.0.1:%d" % _server.port()
	print("    server on %s, seat token %s..." % [url, _token.substr(0, 6)])
	_spectator = _connect(url)
	_seated = _connect(url)
	await _handshake()
	await _check_channels()
	await _check_intent()
	await _check_push()
	_finish()


func _finish() -> void:
	print("")
	if _fail > 0:
		print("==> STAGE 1 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 1 PASSED — clients greeted, channels split, intents served, state pushed")
		get_tree().quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


# --- setup --------------------------------------------------------------------

func _build_game() -> void:
	var st = SettingsScript.new()
	st.rng_seed = 4242
	var seats: Array = SeatConfig.from_settings(st)
	var names := []
	for s in seats:
		names.append(s.name)
	_engine = EngineScript.new()
	_engine.setup(st, names)
	_manager = SeatManagerScript.new()
	add_child(_manager)
	_manager.setup(_engine, seats)
	_server = ServerScript.new()
	add_child(_server)
	_server.bind_game(_engine, _manager)
	_token = _server.mint_token(0)


func _connect(url: String) -> WebSocketPeer:
	var p := WebSocketPeer.new()
	p.connect_to_url(url)
	return p


func _pump(peer: WebSocketPeer, inbox: Array) -> void:
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var d := Proto.decode(peer.get_packet().get_string_from_utf8())
		if not d.is_empty():
			inbox.append(d)


## Wait until a peer is OPEN, or give up.
func _await_open(peer: WebSocketPeer, inbox: Array, label: String) -> bool:
	for i in 240:
		_pump(peer, inbox)
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		await get_tree().process_frame
	_bad("%s never opened" % label)
	return false


## Wait for a message of a given type, pumping both peers.
func _await_type(peer: WebSocketPeer, inbox: Array, t: String, timeout_frames := 240):
	for i in timeout_frames:
		_pump(peer, inbox)
		for m in inbox:
			if str(m.get("t", "")) == t:
				return m
		await get_tree().process_frame
	return null


func _handshake() -> void:
	print("[1] both clients connect and are greeted")
	var a := await _await_open(_spectator, _spectator_inbox, "spectator")
	var b := await _await_open(_seated, _seated_inbox, "seated")
	if not a or not b:
		return
	# the spectator identifies with no token, the other with the seat token
	_spectator.send_text(Proto.encode(Proto.hello("", "stream")))
	_seated.send_text(Proto.encode(Proto.hello(_token, "player")))
	var ga = await _await_type(_spectator, _spectator_inbox, "hello_ok")
	var gb = await _await_type(_seated, _seated_inbox, "hello_ok")
	if ga == null or gb == null:
		_bad("a client was not greeted")
		return
	if str(ga.get("channel", "")) != "spectator":
		_bad("an unseated client should be on 'spectator', got '%s'" % ga.get("channel"))
		return
	if str(gb.get("channel", "")).begins_with("seat/") == false:
		_bad("a seated client needs its own channel, got '%s'" % gb.get("channel"))
		return
	if int(gb.get("pid", -1)) != 0:
		_bad("the seated client was bound to pid %s" % str(gb.get("pid")))
		return
	_ok("spectator on 'spectator', token holder on 'seat/<token>' as pid 0")


# --- checks -------------------------------------------------------------------

func _check_channels() -> void:
	print("[2] each client receives the projection it is ENTITLED to")
	var ps = await _await_type(_spectator, _spectator_inbox, "projection")
	var pd = await _await_type(_seated, _seated_inbox, "projection")
	if ps == null or pd == null:
		_bad("a client received no projection")
		return
	var sp: Dictionary = ps.get("data", {})
	var dp: Dictionary = pd.get("data", {})
	for k in ["private", "legal"]:
		if sp.has(k):
			_bad("the SPECTATOR projection leaked '%s' over the wire" % k)
			return
	_ok("the spectator projection over the wire has no 'private' and no 'legal'")
	if not dp.has("private") or not dp.has("legal"):
		_bad("the seated projection is missing its private section or legal actions")
		return
	_ok("the seated projection carries 'private' and 'legal'")
	# the hidden information specifically
	if JSON.stringify(sp).contains("get_out_of_jail"):
		_bad("get-out-of-jail cards reached the spectator channel")
		return
	_ok("get-out-of-jail cards never cross the spectator channel")


func _check_intent() -> void:
	print("[3] an intent reaches the engine and the verdict returns")
	# an ILLEGAL intent first: the engine must refuse it, not the socket layer
	_seated_inbox.clear()
	_seated.send_text(Proto.encode(Proto.intent("bad1", "build_house", {"tile": 0})))
	var v = await _await_type(_seated, _seated_inbox, "verdict", 240)
	if v == null:
		_bad("no verdict came back for the illegal intent")
		return
	if bool(v.get("ok", true)):
		_bad("the engine accepted an illegal build_house — fail-closed is broken")
		return
	_ok("an illegal intent is refused by the ENGINE ('%s')" % str(v.get("reason", "")))

	# a legal one: rolling is legal at the start of a turn
	_seated_inbox.clear()
	var before: int = _engine.log.size()
	_seated.send_text(Proto.encode(Proto.intent("ok1", "roll", {})))
	var v2 = await _await_type(_seated, _seated_inbox, "verdict", 240)
	if v2 == null:
		_bad("no verdict for the legal intent")
		return
	if not bool(v2.get("ok", false)):
		_bad("a legal roll was refused: %s" % str(v2.get("reason", "")))
		return
	if _engine.log.size() <= before:
		_bad("the verdict said ok but the engine logged no event")
		return
	_ok("a legal roll is served and the engine logged %d new event(s)"
		% (_engine.log.size() - before))


func _check_push() -> void:
	print("[4] a state change is PUSHED to both channels, unprompted")
	_spectator_inbox.clear()
	_seated_inbox.clear()
	# `push_intent` always re-emits the projection, but we assert on a change the
	# ENGINE actually made — a refused intent proves nothing about push
	var before: int = _engine.log.size()
	# ask the ENGINE what is legal rather than assuming a move — the phase moves
	# on after a roll, so hardcoding "roll" is a test that breaks itself
	var legal: Array = _engine.legal_actions(0)
	if legal.is_empty():
		_bad("seat 0 has no legal action to prove the push with")
		return
	var action: String = str(legal[0])
	var params: Dictionary = {}
	if _engine.phase == "PURCHASE_WAIT":
		# decline opens an auction; buying is the simpler state change
		action = "buy" if legal.has("buy") else action
	var res: Dictionary = _manager.push_intent(0, action, params)
	if not bool(res.get("ok", false)):
		_bad("the push check could not make a legal move '%s': %s"
			% [action, str(res.get("reason", ""))])
		return
	if _engine.log.size() <= before:
		_bad("the state did not change, so the push cannot be proven")
		return
	var pushed_spec = await _await_type(_spectator, _spectator_inbox, "projection", 180)
	var pushed_seat = await _await_type(_seated, _seated_inbox, "projection", 180)
	if pushed_spec == null:
		_bad("the spectator channel was not pushed the new state")
		return
	if pushed_seat == null:
		_bad("the seated channel was not pushed the new state")
		return
	# and the two channels must NOT be identical: the seated one carries more
	var sp: Dictionary = pushed_spec.get("data", {})
	var dp: Dictionary = pushed_seat.get("data", {})
	if sp.has("private") or dp.get("private", null) == null:
		_bad("the push broke the channel split")
		return
	_ok("both channels were pushed the new state, each at its own level")
