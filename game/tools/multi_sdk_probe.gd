extends Node
## MULTI-SDK, measured: TWO SDK seats in ONE process, each on its own websocket.
##
## Before this, `seat_config.resolve_driver` downgraded every sdk: seat after the first to AI - the
## vendored SDK wrote every instance's queue to the autoload's socket and kept ONE global action
## registry, so a second connection would have answered through the first.
##
## The probe builds a 4-seat match with two SDK seats (endpoints from NPT_SDK_A / NPT_SDK_B) and
## asks for the two facts that only work if the connections are really separate:
##   - each SDK seat's own connection is connected;
##   - each SDK seat has intents ACCEPTED by the engine (the mock answers every force), and the
##     match advances.
##
## Verdict: ==> MULTI-SDK PASSED (2 connections, pid0=<n> pid1=<m> intents, round <r>)
## Run: bash tools/ci/multi_sdk_gate.sh

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")

const WATCH_SECS := 180.0

var _launcher = null
var _frame := 0
var _state := "boot"
var _deadline := 0
var _fails: Array = []
var _adapters: Dictionary = {}     # pid -> adapter


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	get_tree().root.size = Vector2i(1280, 800)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			if _frame < 6:
				return
			_build_match()
			_state = "wait"
			_deadline = Time.get_ticks_msec() + int(WATCH_SECS * 1000.0)
		"wait":
			_watch()


func _build_match() -> void:
	var a := OS.get_environment("NPT_SDK_A")
	var b := OS.get_environment("NPT_SDK_B")
	if a == "" or b == "":
		print("MULTI-SDK no endpoints (NPT_SDK_A/NPT_SDK_B) - nothing to prove")
		_fails.append("NPT_SDK_A/NPT_SDK_B are not set")
		_report()
		return
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 777
	st.round_limit = 6
	st.turn_timer = 0         # the vendored window delays its FORCE by the window value, so a clock
	                          # would just make every probe slower; the mocks answer instantly
	st.seat_assignments = [
		{"driver": "sdk:neuro", "name": "Seat A", "sdk_endpoint": a},
		{"driver": "sdk:evil", "name": "Seat B", "sdk_endpoint": b},
		{"driver": "AI", "name": "Bot 3"},
		{"driver": "AI", "name": "Bot 4"},
	]
	var seats: Array = SeatConfigScript.from_settings(st)
	var sdk := 0
	for s in seats:
		if str(s.input_driver) == "SDK":
			sdk += 1
	print("MULTI-SDK seats: %d SDK of %d (drivers: %s)" % [sdk, seats.size(),
		", ".join(seats.map(func(x): return "%s=%s" % [x.name, x.input_driver]))])
	if sdk != 2:
		_fails.append("two sdk: seats must resolve to SDK when they carry endpoints, got %d" % sdk)
		_report()
		return
	_launcher.call("_build_game", st, seats)
	_launcher.get("_overlay").visible = false
	_launcher.set("_game_started", true)
	_launcher.get("_game_view").call("on_game_started")


func _watch() -> void:
	var mgr = _launcher.get("_manager")
	var eng = _launcher.get("_engine")
	if mgr == null or eng == null:
		return
	var ads = mgr.get("_sdk_adapters")
	if ads is Dictionary and (ads as Dictionary).size() == 2 and _adapters.is_empty():
		for pid in (ads as Dictionary).keys():
			_adapters[int(pid)] = (ads as Dictionary)[pid]
		print("MULTI-SDK two adapters spawned (each with its own connection node)")
	if Time.get_ticks_msec() < _deadline:
		return
	_report()


func _report() -> void:
	var eng = _launcher.get("_engine")
	if eng != null and _adapters.size() == 2:
		var entries: Array = eng.log.entries()
		var counts := {}
		for pid in _adapters.keys():
			var n := 0
			for e in entries:
				var d: Dictionary = e.get("data", {})
				if int(d.get("player", -1)) == int(pid) or int(d.get("from", -1)) == int(pid):
					n += 1
			counts[int(pid)] = n
			print("MULTI-SDK intents pid=%d accepted=%d" % [int(pid), n])
		for pid in _adapters.keys():
			var a = _adapters[pid]
			var c = a.get("conn")
			print("MULTI-SDK connection pid=%d node=%s connected=%s" % [int(pid),
				str(c.name if c != null else "null"),
				str(c.websocket_is_connected if c != null else false)])
			if c == null or not bool(c.websocket_is_connected):
				_fails.append("seat %d has no live connection" % int(pid))
		for pid in counts.keys():
			if int(counts[pid]) < 3:
				_fails.append("seat %d accepted only %d intent(s) - its connection is not playing" % [
					int(pid), int(counts[pid])])
		# The proof is "both seats PLAY through their own socket", not "the match finishes": four
		# seats on two websocket round-trips per decision spend 180 s in round 1 quite legitimately.
		if entries.size() < 15:
			_fails.append("the match only logged %d event(s) - nothing is really moving" % entries.size())
		if _fails.is_empty():
			print("==> MULTI-SDK PASSED (2 connections, pid %s, round %d)" % [
				str(counts), int(eng.round_no)])
			get_tree().quit(0)
			return
	print("==> MULTI-SDK FAILED: %s" % " | ".join(_fails))
	get_tree().quit(1)
