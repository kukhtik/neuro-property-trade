extends Node
## HG-05 gate - seat identity and intent addressing (docs/restoration/gates.md, HG-05).
##
## The audit: `game_view` hardcoded `_human_pid = 0` ("на хосте работает случайно; у удалённого
## клиента кнопки не покажутся никогда, а интенты ушли бы за место 0") and `main._on_remote_state`
## answered `legal[0]` unconditionally ("автоигра в продакшене"). This gate pins the repairs:
##   (a) WHO PLAYS: `setup()` derives the human seat from the seat list - LOCAL/ADMIN anywhere,
##       not only pid 0 (a 4-seat match with LOCAL in slot 2 must address slot 2);
##   (b) NO BUTTONS FOR OTHERS: when the decision holder is an AI, the console offers no
##       buttons and marks the console non-human - the UI cannot start an intent for someone
##       else;
##   (c) A CLIENT PLAYS OVER THE WIRE: with a joined remote session set, a console press goes
##       through `RemoteSession.act` (the client owns no manager - the old `_submit` returned
##       silently, so every browser press died);
##   (d) NO AUTO-PLAY WITHOUT THE FIXTURE FLAG: `main._on_remote_state` must send NOTHING for a
##       state with legal actions when neither `--smoke-drive` nor `smoke=1` is set.
##
## Verdict: ==> HG-05 PASSED / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/hg05_identity_gate.tscn

const MainScript := preload("res://main.gd")
const GameView := preload("res://ui/game_view.gd")
const EngineScript := preload("res://core/engine.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")
const LaunchParams := preload("res://ui/core/launch_params.gd")

var _fails: Array = []


## A wire stand-in: records what a client would send.
class FakeSession:
	var sent: Array = []
	func is_joined() -> bool:
		return true
	func act(action: String, params: Dictionary) -> String:
		sent.append({"action": action, "params": params})
		return "fake1"


func _ready() -> void:
	await _run()
	if _fails.is_empty():
		print("==> HG-05 PASSED (who-plays derived, no buttons for others, client submits on the wire, no auto-play without the flag)")
		get_tree().quit(0)
	else:
		print("==> HG-05 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _run() -> void:
	_check_slot_zero()
	await _check_local_in_slot_two()
	await _check_no_buttons_for_ai()
	await _check_client_wire_path()
	await _check_no_auto_play()


## Build a real engine + seat manager + seats with the given drivers (LOCAL in slot `local_i`).
func _build(drivers: Array) -> Dictionary:
	var st = SettingsScript.new()
	st.seat_count = drivers.size()
	var assigns: Array = []
	for i in drivers.size():
		assigns.append({"driver": str(drivers[i]), "name": "S%d" % i})
	st.seat_assignments = assigns
	var seats: Array = SeatConfigScript.from_settings(st)
	var names: Array = []
	for s in seats:
		names.append(str(s.name))
	var eng = EngineScript.new()
	eng.setup(st, names)
	var mgr = SeatManager.new()
	add_child(mgr)
	mgr.setup(eng, seats)
	return {"engine": eng, "manager": mgr, "seats": seats, "settings": st}


## (a) the plain shape: LOCAL in slot 0 must resolve to pid 0.
func _check_slot_zero() -> void:
	var w := _build(["LOCAL", "AI", "AI", "AI"])
	var gv = GameView.new()
	add_child(gv)
	gv.setup(w["engine"], w["manager"], w["seats"], w["settings"])
	if int(gv.get("_human_pid")) != 0:
		_fail("LOCAL in slot 0 resolved to pid %s, expected 0" % str(gv.get("_human_pid")))
	else:
		print("PASS: LOCAL in slot 0 -> _human_pid=0")
	w["manager"].queue_free()
	gv.queue_free()


## (a') the shape the hardcoded 0 got wrong: LOCAL in slot 2.
func _check_local_in_slot_two() -> void:
	var w := _build(["AI", "AI", "LOCAL", "AI"])
	var gv = GameView.new()
	add_child(gv)
	gv.setup(w["engine"], w["manager"], w["seats"], w["settings"])
	var expect := int((w["seats"] as Array)[2].pid)
	if int(gv.get("_human_pid")) != expect:
		_fail("LOCAL in slot 2 resolved to pid %s, expected %d" % [str(gv.get("_human_pid")), expect])
	else:
		print("PASS: LOCAL in slot 2 -> _human_pid=%d" % expect)
	w["manager"].queue_free()
	gv.queue_free()
	await get_tree().process_frame


## (b) the holder is an AI: the console must offer no buttons (nobody may act for it).
func _check_no_buttons_for_ai() -> void:
	var w := _build(["LOCAL", "AI", "AI", "AI"])
	var gv = GameView.new()
	add_child(gv)
	gv.setup(w["engine"], w["manager"], w["seats"], w["settings"])
	var eng = w["engine"]
	# hand the turn to the AI without a manager tick: roll (and pass a purchase if offered)
	eng.submit_intent(0, "roll", {})
	if str(eng.phase) == "PURCHASE_WAIT":
		eng.submit_intent(0, "buy", {})
		if str(eng.phase) == "PURCHASE_WAIT":
			eng.submit_intent(0, "pass", {})
	gv.call("_sync_all")
	var console = gv.find_child("act", true, false)
	var human_now: bool = bool(console.get("_human_now"))
	# the row is an HFlowContainer since SG-02 (it WRAPS); cast to Container, not HBoxContainer
	var row0: Container = console.get("_btn_row")
	var buttons: int = row0.get_child_count() if row0 != null else -1
	if int(eng.turn_player) == 0:
		print("HG-05 note: the roll did not hand the turn over (phase=%s); check (b) skipped" % str(eng.phase))
	elif human_now or buttons > 0:
		_fail("holder is the AI but the console still offers %d button(s) (human_now=%s)" % [buttons, str(human_now)])
	else:
		print("PASS: AI holds the decision -> console offers 0 buttons, human_now=false")
	w["manager"].queue_free()
	gv.queue_free()
	await get_tree().process_frame


## (c) a joined client: a press must travel over the wire, addressed to ITS pid.
func _check_client_wire_path() -> void:
	var gv = GameView.new()
	add_child(gv)
	gv.setup_cold(null)
	var fake := FakeSession.new()
	gv.set_remote_session(fake)
	gv.set_human_pid(1)
	# the host's own push for this client's turn: holder 1, its legal set
	gv.apply_projection({
		"phase": "TURN_START", "round": 1, "turn_player": 1, "holder": 1,
		"legal": ["roll", "build_house"], "pending": {}, "players": [], "board": [],
	})
	var console = gv.find_child("act", true, false)
	var row: Container = console.get("_btn_row")
	var roll: Button = null
	for c in row.get_children():
		if c is Button and str((c as Button).text).begins_with("Бросок"):
			roll = c
	if roll == null:
		_fail("client with _human_pid=1 and legal=[roll,...] was offered no roll button")
	else:
		roll.emit_signal("pressed")
		if fake.sent.size() != 1 or str(fake.sent[0]["action"]) != "roll":
			_fail("a client press did not reach the wire (sent=%s)" % str(fake.sent))
		else:
			print("PASS: client press -> RemoteSession.act(roll, {})")
	# and the other seat's turn: no buttons for a client either
	gv.apply_projection({
		"phase": "TURN_START", "round": 1, "turn_player": 0, "holder": 0,
		"legal": ["roll"], "pending": {}, "players": [], "board": [],
	})
	if bool(console.get("_human_now")) or row.get_child_count() > 0:
		_fail("client was offered buttons while ANOTHER seat holds the decision")
	else:
		print("PASS: another seat's turn -> the client offers nothing")
	gv.queue_free()
	await get_tree().process_frame


## (d) no auto-play without the fixture flag: a state WITH legal actions must produce zero sends.
func _check_no_auto_play() -> void:
	if LaunchParams.smoke_drive():
		_fail("this run behaves like a smoke fixture (smoke=1/--smoke-drive set) - case (d) cannot be checked")
		return
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 10:
		await get_tree().process_frame
	var fake := FakeSession.new()
	launcher.set("_remote_session", fake)
	launcher.set("_game_view", launcher.get("_game_view"))
	launcher.call("_on_remote_state", {
		"phase": "TURN_START", "turn_player": 5, "holder": 5, "legal": ["roll"], "pending": {},
	})
	if fake.sent.size() != 0:
		_fail("main auto-answered %s without --smoke-drive/smoke=1 (the audit's silent auto-play)" % str(fake.sent))
	else:
		print("PASS: a wire state with legal actions produced 0 intents (no auto-play without the fixture flag)")
	launcher.queue_free()
	await get_tree().process_frame


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
