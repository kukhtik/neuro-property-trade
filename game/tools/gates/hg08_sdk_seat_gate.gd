extends Node
## HG-08 gate — the SDK seat plays (docs/restoration/gates.md HG-08).
##
## RUN THROUGH tools/ci/gates/hg08_sdk_seat_gate.sh: it starts the mock Neuro websocket and
## sets NEURO_SDK_WS_URL, which the vendored addon reads at process start. Run bare, the addon
## has no endpoint and the gate fails honestly at the connection check.
##
## The audit's finding this closes: an SDK seat had no actor at all. seat_manager never spawned
## the adapter ("SDK needs no auto-driver: the adapter self-drives" - with nothing to self-drive),
## so the first SDK decision stalled the match forever.
##
## Checks:
##   1. the SDK seat has an actor (SdkAdapter node under the manager, engine known);
##   2. the addon is really connected to the mock (Websocket.websocket_is_connected);
##   3. the SDK seat's intents are ACCEPTED: >= 3 engine-log entries authored by the seat;
##   4. the match does not stall: it advances to >= 3 rounds with the SDK seat answering;
##   5. one SDK per process: a second sdk: assignment resolves to AI (and is documented).
##
## Verdict: ==> HG-08 PASSED (...) / FAILED: <first reason>
## Run: bash tools/ci/gates/hg08_sdk_seat_gate.sh

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")

const MIN_CHECKS := 4   # adapter/spawn, connected, intents+advance, one-SDK rule
const SDK_NAME := "Neuro"
const TARGET_ROUNDS := 3
const MIN_INTENTS := 3

var _launcher = null
var _frame := 0
var _state := "boot"
var _deadline := 0
var _fails: Array = []
var _checks := 0
var _adapter = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			if _frame < 6:
				return
			_build_match()
			_state = "wait_adapter"
			_deadline = Time.get_ticks_msec() + 15000
		"wait_adapter":
			var mgr = _launcher.get("_manager")
			if mgr != null:
				var ads = mgr.get("_sdk_adapters")
				if ads is Dictionary and not (ads as Dictionary).is_empty():
					_adapter = (ads as Dictionary).values()[0]
					var apid: int = int(_adapter.get("seat_pid")) if _adapter != null else -1
					if _adapter == null or _adapter.get("engine") == null or apid < 0:
						_fail("the adapter exists but is not wired to the engine/seat (pid=%d)" % apid)
						_report()
						return
					for s in mgr.get("seats"):
						print("HG-08 seat: pid=%d name=%s driver=%s" % [int(s.pid), str(s.name), str(s.input_driver)])
					_checks += 1
					print("HG-08: SdkAdapter spawned for the SDK seat (pid=%d)" % apid)
					_state = "wait_connect"
					_deadline = Time.get_ticks_msec() + 30000
					return
			if Time.get_ticks_msec() >= _deadline:
				_fail("no SdkAdapter appeared under the seat manager within 15s - the SDK seat still has no actor")
				_report()
		"wait_connect":
			if bool(Websocket.websocket_is_connected):
				_checks += 1
				print("HG-08: the addon is connected to the mock endpoint")
				_state = "watch"
				_deadline = Time.get_ticks_msec() + 180000
				return
			if Time.get_ticks_msec() >= _deadline:
				_fail("the addon never connected (is NEURO_SDK_WS_URL set to the running mock?)")
				_report()
		"watch":
			var eng = _launcher.get("_engine")
			if eng == null:
				_fail("engine vanished mid-match")
				_report()
				return
			var rounds := int(eng.round_no)
			var intents := _sdk_intents(eng)
			if rounds >= TARGET_ROUNDS and intents >= MIN_INTENTS:
				_checks += 1
				print("HG-08: the match advanced to round %d with %d SDK-seat intent(s) accepted" % [rounds, intents])
				_check_one_sdk_rule()
				_report()
				return
			if Time.get_ticks_msec() >= _deadline:
				_fail("the match did not advance: round %d, %d SDK-seat intent(s) (a stalled SDK seat)" % [rounds, intents])
				_report()


func _build_match() -> void:
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 4242
	st.round_limit = 8
	# A REAL CLOCK, on purpose: with turn_timer = 0 the invite-latency check in HG-08 was VACUOUS -
	# the vendored window's "force after the timeout" fired immediately too, so the gate could not tell
	# the fix from the defect (measured: both gave 0.9s). The seat answers every force instantly, so the
	# clock costs this gate nothing; it only makes a regression visible (~20s late invite).
	st.turn_timer = 20
	st.seat_assignments = [
		{"driver": "sdk:neuro", "name": SDK_NAME},
		{"driver": "AI", "name": "Bot 2"},
		{"driver": "AI", "name": "Bot 3"},
		{"driver": "AI", "name": "Bot 4"},
	]
	var seats: Array = SeatConfigScript.from_settings(st)
	_launcher.call("_build_game", st, seats)
	_launcher.get("_overlay").visible = false
	_launcher.set("_game_started", true)
	_launcher.get("_game_view").call("on_game_started")


## Engine-log entries authored by the SDK seat. The engine logs pids (ints), not names -
## the first version compared against the seat NAME and counted zero on a match that had
## already reached its round limit (the match itself was the proof the seat played).
func _sdk_intents(eng) -> int:
	var pid := int(_adapter.get("seat_pid")) if _adapter != null else -1
	if pid < 0:
		return 0
	var n := 0
	for e in eng.log.entries():
		var data: Dictionary = e.get("data", {})
		if int(data.get("player", -1)) == pid or int(data.get("from", -1)) == pid:
			n += 1
	return n


func _check_one_sdk_rule() -> void:
	if SeatConfigScript.resolve_driver("sdk:neuro", false) != "SDK":
		_fail("the first sdk: assignment no longer resolves to the SDK driver")
		return
	if SeatConfigScript.resolve_driver("sdk:evil", true) != "AI":
		_fail("a SECOND sdk: assignment must fall back to AI (one SDK per process) - it did not")
		return
	_checks += 1
	print("HG-08: one-SDK-per-process rule holds (second sdk: slot plays as AI)")


func _report() -> void:
	print("HG-08: %d checks" % _checks)
	if _checks < MIN_CHECKS and _fails.is_empty():
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	_check_missing_endpoint_is_recorded()
	if _fails.is_empty():
		print("==> HG-08 PASSED (adapter spawned, mock answered, intents accepted, match advanced; a seat with no endpoint of its own says so in the journal)")
		get_tree().quit(0)
	else:
		print("==> HG-08 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)


## NO SILENT FALLBACKS. This gate's seat speaks through the shared NEURO_SDK_WS_URL and has no endpoint
## of its OWN - the arrangement that used to be indistinguishable from "the seat quietly became an AI"
## when a second SDK seat wanted the same connection. The seat must therefore leave a line in the match
## journal (which every client renders) saying exactly that.
func _check_missing_endpoint_is_recorded() -> void:
	var eng = _launcher.get("_engine")
	if eng == null:
		_fail("no engine to read the journal from")
		return
	var seats: Array = _launcher.get("_manager").get("seats") if _launcher.get("_manager") != null else []
	var missing := 0
	for s in seats:
		if str(s.get("sdk_endpoint")) == "" and str(s.get("input_driver")) == "SDK":
			missing += 1
	var logged := 0
	for entry in eng.log.entries():
		if str(entry.get("type", "")) == "seat_no_endpoint":
			logged += 1
	_checks += 1
	if missing == 0:
		print("HG-08: every SDK seat names its own endpoint - nothing to warn about")
	elif logged == 0:
		_fail("%d SDK seat(s) have no endpoint of their own and the journal says NOTHING about it - the fallback is silent again" % missing)
	else:
		print("HG-08: %d SDK seat(s) without an endpoint, %d journal line(s) saying so" % [missing, logged])
