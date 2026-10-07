extends Node
## Orchestrates multi-seat play. On each poll, finds the seat that holds the
## decision point (non-empty legal_actions), routes to its driver, and enforces
## per-seat timeout -> auto-pass (spec §3). All intents flow through
## engine.submit_intent (fail-closed). Emits spectator-safe signals for a UI
## overlay. The pure helper find_decision_holder is headless-testable.

signal state_changed(spectator_proj: Dictionary)
signal events_emitted(events: Array)
signal game_over(winner_name: String)

const POLL_INTERVAL := 0.4

var engine
var seats: Array = []        # of Seat (RefCounted)
var _drivers := {}           # pid -> Node driver instance
var _last_decision_key := ""
var _tick_elapsed := 0.0
var _last_process_delta := 0.0
## When true, LOCAL/ADMIN seats are played by the internal AI. Off by default: a
## human seat must wait for its human. The smoke turns it on because no human is
## present. REMOTE seats are NEVER auto-played — a browser player is a human.
var _autoplay_local := false

# --- pure helper (headless-testable) ---
static func find_decision_holder(engine, player_count: int) -> int:
	for pid in player_count:
		if not engine.legal_actions(pid).is_empty():
			return pid
	return -1

func setup(eng, seat_list: Array) -> void:
	engine = eng
	seats = seat_list
	for s in seats:
		var d: String = s.input_driver
		if d == "AI":
			_spawn_driver(s.pid, "res://seats/drivers/ai_driver.gd")
		elif d == "CHAT":
			_spawn_driver(s.pid, "res://seats/drivers/chat_driver.gd")
		elif d == "REMOTE":
			# spawned so the socket exists and can be driven; the host then calls
			# configure() with the real url + token
			_spawn_driver(s.pid, "res://seats/drivers/remote_driver.gd")
		# LOCAL / SDK / ADMIN need no auto-driver: LOCAL waits (push_intent),
		# SDK self-drives via its adapter, ADMIN uses explicit intents.

func _spawn_driver(pid: int, path: String) -> void:
	var Script = load(path)
	var node = Script.new()
	node.name = "Driver%d" % pid
	add_child(node)
	node.setup(engine, _seat(pid))
	_drivers[pid] = node

## Let the host play its own LOCAL seats (automated runs). REMOTE seats are
## never affected: a browser player must always wait for its human.
func set_autoplay_local(on: bool) -> void:
	_autoplay_local = on


func _seat(pid: int):
	for s in seats:
		if s.pid == pid:
			return s
	return null

func _process(delta: float) -> void:
	if engine == null:
		return
	_tick_elapsed += delta
	if _tick_elapsed < POLL_INTERVAL:
		return
	_tick_elapsed = 0.0
	_last_process_delta = delta * POLL_INTERVAL
	_tick()

func _tick() -> void:
	if engine.phase == "END_GAME":
		game_over.emit(engine.player(0).name if engine.player_count() == 1 else "")
		return
	var holder: int = find_decision_holder(engine, engine.player_count())
	if holder == -1:
		return
	var key: String = "%s|%d|%s" % [engine.phase, holder, str(engine._pending)]
	if key != _last_decision_key:
		_last_decision_key = key
		for s in seats:
			s.decision_waiting = 0.0
	var seat = _seat(holder)
	if seat == null:
		return
	seat.decision_waiting += _last_process_delta
	var drv = _drivers.get(holder)
	match seat.input_driver:
		"AI", "CHAT":
			if drv != null:
				drv.act()
			# AI/CHAT drivers act immediately; timeout is a safety net for them too
			_maybe_timeout(seat)
		"LOCAL", "ADMIN":
			if _autoplay_local:
				# an automated run has no human at this seat; play it with the AI
				# so the match can progress (the smoke uses this)
				var p_min = load("res://seats/minimal_action.gd").pick(engine, holder)
				if not p_min.is_empty():
					var r_min: Dictionary = engine.submit_intent(holder, p_min.action, p_min.params)
					if r_min.get("events", []).size() > 0:
						events_emitted.emit(r_min["events"])
				return
			_maybe_timeout(seat)
		"REMOTE":
			# REMOTE waits for a human like LOCAL, and times out like LOCAL. It
			# MUST be here: falling through to `_` would leave the match hung
			# whenever a browser player closed the tab.
			_maybe_timeout(seat)
		# "SDK" seats are NOT auto-passed here — the SDK adapter self-drives its
		# own force/result cycle and imposing a manager timeout would race it
		# (manager forces roll while Randy/Neuro is still answering the force).
		# A future SDK-side timeout (one short retry then auto-pass, per spec) is
		# handled inside the adapter, not the seat manager.
		_:
			pass
	emit_spectator()

func _maybe_timeout(seat) -> void:
	if engine.settings.timeout_action == "mark-away":
		seat.away = true
		return
	var window := float(engine.settings.turn_timer)
	if engine.phase == "AUCTION":
		window = float(engine.settings.auction_timer)
	if window <= 0.0:
		return
	if seat.decision_waiting < window:
		return
	var p = load("res://seats/minimal_action.gd").pick(engine, seat.pid)
	seat.away = true
	if p.is_empty():
		return
	var res: Dictionary = engine.submit_intent(seat.pid, p.action, p.params)
	if res.get("events", []).size() > 0:
		events_emitted.emit(res["events"])
	emit_spectator()

## Single human/admin/SDK entry — forwards to the engine, fail-closed.
func push_intent(pid: int, action: String, params: Dictionary) -> Dictionary:
	if engine == null:
		return {"ok": false, "reason": "engine not ready", "legal": [], "events": []}
	var res: Dictionary = engine.submit_intent(pid, action, params)
	emit_spectator()
	if res.get("events", []).size() > 0:
		events_emitted.emit(res["events"])
	return res

## Chat seat entry: enqueue a viewer command/vote.
func push_chat(pid: int, action: String, params: Dictionary) -> void:
	var drv = _drivers.get(pid)
	if drv != null and drv.has_method("enqueue"):
		drv.enqueue(action, params)

## Admin overrides go through the authoritative engine (spec §4 invariant).
## Phase-3 stub: routes to the current decision holder. A full admin_override
## entry point is built in Phase 4.
func push_admin_intent(action: String, params: Dictionary) -> Dictionary:
	var holder: int = find_decision_holder(engine, engine.player_count())
	if holder == -1:
		return {"ok": false, "reason": "no active decision", "legal": [], "events": []}
	var res: Dictionary = push_intent(holder, action, params)
	if res.get("events", []).size() > 0:
		events_emitted.emit(res["events"])
	return res

func emit_spectator() -> void:
	if engine == null:
		return
	var ProjScript = load("res://sdk/projection.gd")
	var proj = ProjScript.new()
	var spec = proj.for_spectator(engine)
	# P3: add timer fields for timer ring
	var holder: int = find_decision_holder(engine, engine.player_count())
	if holder >= 0:
		var seat = _seat(holder)
		if seat != null:
			var window: float = float(engine.settings.turn_timer)
			if engine.phase == "AUCTION":
				window = float(engine.settings.auction_timer)
			spec["timer_window"] = window
			spec["timer_elapsed"] = seat.decision_waiting
			spec["timer_active"] = window > 0.0
	state_changed.emit(spec)
