extends Node
## Multi-seat runtime proof for Phase 3. Wires the seat manager with seats
## [SDK(neuro), AI, AI, LOCAL]. The SDK seat talks to Randy (ws://localhost:8000)
## via the existing adapter; AI seats self-drive; the LOCAL seat is auto-driven
## by a fake-human timer pushing intents through the manager (as a UI would).
## Reaches END_GAME or a turn cap without stalling => exit 0.
##
## Usage:
##   NEURO_SDK_WS_URL=ws://localhost:8000 godot --headless --path game res://tools/seats_soak.tscn
## (run `godot --headless --import .` once first so the SDK class cache exists)

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const SdkAdapter := preload("res://sdk/sdk_adapter.gd")

const MAX_TURNS := 12
const STALL_SECONDS := 20.0
const TURN_TIMER := 3

var _engine
var _manager
var _started := false
var _done := false
var _turn_count := 0
var _last_turn := -1
var _stall_key := ""
var _stall_elapsed := 0.0
var _fake_human_elapsed := 0.0
var _sdk_pid := -1
var _local_pid := -1

func _ready() -> void:
	print("=== seats soak: starting ===")
	var s = Settings.new()
	s.rng_seed = 12345
	s.turn_timer = TURN_TIMER
	s.auction_timer = TURN_TIMER
	s.auctions_on_refusal = false
	s.seat_assignments = [
		{"driver": "sdk:neuro", "name": "Neuro"},
		{"driver": "AI", "name": "Ada"},
		{"driver": "AI", "name": "Bo"},
		{"driver": "LOCAL", "name": "Ced"},
	]
	var seats: Array = SeatConfig.from_settings(s)
	# with rng_seed set, from_settings shuffles seat order, so locate drivers by
	# resolved input_driver, NOT by array position.
	for i in seats.size():
		var seat = seats[i]
		if _sdk_pid == -1 and seat.input_driver == "SDK":
			_sdk_pid = seat.pid
		if _local_pid == -1 and seat.input_driver == "LOCAL":
			_local_pid = seat.pid
	_engine = EngineScript.new()
	_engine.setup(s, _seat_names(seats))
	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, seats)
	if _sdk_pid != -1:
		var adapter = SdkAdapter.new()
		adapter.name = "SdkAdapter"
		add_child(adapter)
		adapter.setup(_engine, _sdk_pid)
	_started = true
	print("=== seats soak: engine ready, manager wired; sdk_pid=%d local_pid=%d ===" % [_sdk_pid, _local_pid])

func _seat_names(seats: Array) -> Array:
	var names := []
	for s in seats:
		names.append(s.name)
	return names

func _process(delta: float) -> void:
	if not _started or _done:
		return
	# Fake human drives the LOCAL seat every 0.5s while it holds the decision.
	_fake_human_elapsed += delta
	if _fake_human_elapsed >= 0.5 and _local_pid != -1:
		_fake_human_elapsed = 0.0
		_drive_local_seat(_local_pid)
	# Stall + turn-cap detection (mirrors soak.gd).
	var key: String = "%s|%d|%d" % [_engine.phase, _engine.turn_player, _engine._pending.get("bidder", -1)]
	if key == _stall_key:
		_stall_elapsed += delta
		if _stall_elapsed >= STALL_SECONDS:
			print("=== seats soak: STALLED at %s === pending: %s" % [key, str(_engine._pending)])
			var legal_all: Array = []
			for p in range(_engine.player_count()):
				legal_all.append(_engine.legal_actions(p))
			print("=== legal per seat: %s ===" % str(legal_all))
			_finish(false)
	else:
		_stall_key = key
		_stall_elapsed = 0.0
	if _engine.turn_player == 0 and _last_turn != 0:
		_turn_count += 1
		_last_turn = 0
		if _turn_count >= MAX_TURNS:
			print("=== seats soak: reached turn cap %d ===" % MAX_TURNS)
			_finish(true)
	elif _engine.turn_player != 0:
		_last_turn = _engine.turn_player
	if _engine.phase == "END_GAME":
		print("=== seats soak: game over ===")
		_finish(true)

func _drive_local_seat(pid: int) -> void:
	var legal: Array = _engine.legal_actions(pid)
	if legal.is_empty():
		return
	var action: String = legal[0]
	var params := {}
	match action:
		"bid":
			var high: int = int(_engine._pending.get("high", 0))
			if _engine.player(pid).money <= high:
				action = "pass"
			else:
				params["amount"] = high + 1
		"respond_trade":
			params["accept"] = false
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var tiles: Array = _engine.player(pid).owned_tiles()
			if tiles.size() == 0:
				return
			params["tile"] = int(tiles[0])
	_manager.push_intent(pid, action, params)

func _finish(passed: bool) -> void:
	_done = true
	print("=== seats soak: %s ===" % ("PASSED" if passed else "FAILED"))
	get_tree().quit(0 if passed else 1)
