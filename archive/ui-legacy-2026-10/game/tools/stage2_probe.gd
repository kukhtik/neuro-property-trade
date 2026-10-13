extends Node
## Stage-2 acceptance: a REMOTE seat plays a real match over a real socket.
##
## Stage 1 proved the server works between two clients. This proves the DRIVER
## works, which is a different claim:
##
##   1. a match with a REMOTE seat builds and the seat resolves to the driver;
##   2. the driver connects, is bound to ITS seat, and receives that seat's
##      projection over the wire;
##   3. an intent the browser sends is executed for THAT seat and no other;
##   4. the seat manager's auto-advance does NOT move the remote seat (it waits
##      for the player, exactly like LOCAL);
##   5. killing the socket does not break the match.
##
## Exit 0 = REMOTE is a working transport.

const ServerScript := preload("res://server/game_server.gd")
const Proto := preload("res://server/protocol.gd")
const EngineScript := preload("res://core/engine.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const SeatManagerScript := preload("res://seats/seat_manager.gd")
const Remote := preload("res://seats/drivers/remote_driver.gd")

var _fail := 0
var _server
var _manager
var _engine
var _remote  # the driver under test
var _peers: Array = []   # {peer, inbox, token}


func _ready() -> void:
	print("=== Stage 2 acceptance: a REMOTE seat plays over the wire ===")
	await _run()
	_finish()


func _finish() -> void:
	print("")
	if _fail > 0:
		print("==> STAGE 2 FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> STAGE 2 PASSED — REMOTE seats resolve, act, wait, and survive a drop")
		get_tree().quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _run() -> void:
	print("[1] a match with a REMOTE seat resolves the driver")
	var st = SettingsScript.new()
	st.rng_seed = 909
	st.seat_count = 3
	# a fixed order so the test is reproducible: the default is a seeded shuffle
	st.starting_order = "manual"
	st.seat_assignments = [
		{"driver": "LOCAL", "name": "Host"},
		{"driver": "REMOTE", "name": "Browser"},
		{"driver": "AI", "name": "Bot"},
	]
	var seats: Array = SeatConfig.from_settings(st)
	var remote_seat = null
	for s in seats:
		if str(s.input_driver) == "REMOTE":
			remote_seat = s
			break
	if remote_seat == null:
		_bad("no seat resolved to REMOTE")
		return
	_ok("a seat resolved to REMOTE ('%s', pid %d)" % [str(remote_seat.driver_label), int(remote_seat.pid)])

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
	if not _server.listen(0, "127.0.0.1"):
		_bad("server failed to bind")
		return
	_server.bind_game(_engine, _manager)

	# the manager spawned a driver for the REMOTE seat; find it
	_remote = _manager.get("_drivers").get(_remote_pid())
	if _remote == null:
		_bad("the manager spawned no driver for the REMOTE seat")
		return
	_ok("the seat manager spawned a driver for pid %d" % _remote_pid())

	print("[2] the driver connects and is bound to its own seat")
	var token: String = _server.mint_token(_remote_pid())
	_remote.configure("ws://127.0.0.1:%d" % _server.port(), token)
	if not _remote.connect_to_host():
		_bad("the driver could not open its socket")
		return
	var proj := await _await_projection(_remote, 300)
	if proj.is_empty():
		_bad("the driver received no projection from the host")
		return
	_ok("the driver received its own projection (%d keys)" % proj.size())
	if not proj.has("legal"):
		_bad("a seated projection must carry legal actions")
		return
	_ok("the projection carries this seat's legal actions: %s" % str(proj["legal"]))

	print("[3] an intent from the browser is executed for THAT seat")
	# Reach a decision point for the remote seat FIRST. An empty legal list means
	# the engine is mid-auction or waiting elsewhere, which would make the check
	# below pass without testing anything.
	await _force_remote_decision()
	var before: int = _engine.log.size()
	var legal_now: Array = _engine.legal_actions(_remote_pid())
	if legal_now.is_empty():
		_bad("the remote seat never reached a decision point — nothing was tested")
		return
	var action: String = str(legal_now[0])
	var id: String = _remote.submit(action, _params_for(action))
	if id == "":
		_bad("the driver refused to send an intent while connected")
		return
	var moved := await _await_log_growth(before, 300)
	if not moved:
		_bad("the intent '%s' was sent but the engine logged nothing (verdict=%s)"
			% [action, str(_remote.get("_last_verdict"))])
		return
	# and it must have been THAT seat that moved, not somebody else
	var last: Dictionary = _engine.log.entries()[-1]
	var who = (last.get("data", {}) as Dictionary).get("player", -1)
	if who is int and int(who) >= 0 and int(who) != _remote_pid():
		_bad("the intent was applied to pid %s, not the remote seat %d" % [str(who), _remote_pid()])
		return
	_ok("intent '%s' reached the engine for the remote seat (%d new events)"
		% [action, _engine.log.size() - before])

	print("[4] the auto-advance does NOT move a REMOTE seat")
	# unlike AI/CHAT, a remote seat must wait for its human. Push any pending
	# auction to its end first, then let other seats play up to its turn.
	await _settle_auction()
	await _force_remote_decision()
	legal_now = _engine.legal_actions(_remote_pid())
	if legal_now.is_empty():
		_bad("the remote seat has no decision point, so waiting was not tested")
		return
	else:
		var turns_before: int = _engine.turn_player
		var phase_before: String = _engine.phase
		# several manager ticks with no input from the browser
		for i in 12:
			_manager._process(0.5)
			await get_tree().process_frame
		if _engine.phase != phase_before or _engine.turn_player != turns_before:
			_bad("the manager advanced a REMOTE seat without input")
			return
		_ok("after 12 ticks the REMOTE seat still waits (phase %s kept)" % phase_before)

	print("[5] killing the socket does not break the match")
	_remote.disconnect_from_host()
	for i in 5:
		await get_tree().process_frame
	if _remote.is_connected_to_host():
		_bad("the driver still reports connected after a close")
		return
	# The turn is the remote seat's, so no other seat CAN act — that is correct
	# game state, not a failure. A disconnected seat is treated as away (which is
	# what the manager's timeout does in production), then another seat must be
	# able to play while the socket stays down.
	# drive enough virtual time to cross the turn timer (30s by default)
	for i in 90:
		_manager._process(float(_engine.settings.turn_timer))
		await get_tree().process_frame
		if _engine.turn_player != _remote_pid():
			break
	if _engine.turn_player == _remote_pid():
		_bad("the match could not move past the disconnected seat")
		return
	var progressed := false
	for pid in _engine.players.size():
		if pid == _remote_pid():
			continue
		var la: Array = _engine.legal_actions(pid)
		if la.is_empty():
			continue
		var n: int = _engine.log.size()
		_manager.push_intent(pid, str(la[0]), _params_for(str(la[0])))
		if _engine.log.size() > n:
			progressed = true
			break
	if not progressed:
		_bad("another seat could not act even with the turn free")
		return
	_ok("the match moved on and another seat played with the socket down")


# --- helpers ------------------------------------------------------------------

## The parameters a client must supply for an action. Read from the engine, not
## guessed — the same way a real browser builds them from its projection.
func _params_for(action: String) -> Dictionary:
	match action:
		"bid":
			return {"amount": int(_engine._pending.get("high", 0)) + 1}
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var mine: Array = _engine.player(_remote_pid()).owned_tiles()
			if mine.is_empty():
				return {}
			return {"tile": int(mine[0])}
		"respond_trade":
			return {"accept": false}
		_:
			return {}


## The pid of the REMOTE seat, found by label (never by index).
func _remote_pid() -> int:
	for s in _manager.seats:
		if str(s.input_driver) == "REMOTE":
			return int(s.pid)
	return -1

func _pump_driver(d) -> Dictionary:
	# drive the driver's own _process so its socket advances
	d._process(0.016)
	return d.projection()


func _await_projection(d, frames: int) -> Dictionary:
	for i in frames:
		d._process(0.016)
		if not d.projection().is_empty():
			return d.projection()
		await get_tree().process_frame
	return {}


func _await_log_growth(before: int, frames: int) -> bool:
	for i in frames:
		if _engine.log.size() > before:
			return true
		await get_tree().process_frame
	return false


## Drive any auction to completion by passing/bidding for the other seats, so
## the engine returns to a normal turn and somebody can reach a decision point.
func _settle_auction() -> void:
	for i in 120:
		if _engine.phase != "AUCTION":
			return
		var acted := false
		for pid in _engine.players.size():
			var la: Array = _engine.legal_actions(pid)
			if la.is_empty():
				continue
			# pass is always available to a participant and always legal
			var pick: String = "pass" if la.has("pass") else str(la[0])
			_manager.push_intent(pid, pick, _params_for(pick))
			acted = true
			break
		await get_tree().process_frame
		if not acted:
			return


## Try to put the remote seat at a decision point by letting other seats move.
func _force_remote_decision() -> void:
	for attempt in 60:
		var pid: int = _remote_pid()
		if not _engine.legal_actions(pid).is_empty():
			return
		var holder: int = _manager.find_decision_holder(_engine, _engine.players.size())
		if holder < 0:
			return
		var la: Array = _engine.legal_actions(holder)
		if la.is_empty():
			return
		_manager.push_intent(holder, str(la[0]), {})
		await get_tree().process_frame
