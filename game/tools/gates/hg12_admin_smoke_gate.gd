extends Node
## HG-12 gate (seed) — execution roles (docs/restoration/gates.md, HG-12).
##
## Grown out of the audit's `admin_smoke_probe.gd`. The contract covered here:
##   - the ADMIN host builds the panel, and the panel is a real surface (labels, buttons);
##   - F12 toggles it through the REAL key handler;
##   - the token gate exists (admin actions are guarded);
##   - a STREAM-role instance has NO admin panel at all (the role is decided at launch and
##     cannot be flipped from inside the app - the audit's "три роли изолированы");
##   - the OBSERVER contract (P2): the stream role drives the view into observer mode, an
##     observer's input is dead even with a live session attached (the wire path included),
##     its console offers no buttons, and the journal widens to 400px (F-57).
##
## Verdict: ==> HG-12 PASSED / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/hg12_admin_smoke_gate.tscn

const MainScript := preload("res://main.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const GameViewScript := preload("res://ui/game_view.gd")

const MIN_OBSERVER_CHECKS := 6

var _host = null
var _stream = null
var _frame := 0
var _fails: Array = []
var _obs_checks := 0


## A live wire with a recorder: if anything reaches it during the observer checks, input was
## not dead.
class FakeRemote:
	var sent: Array = []
	func is_joined() -> bool:
		return true
	func act(action: String, params: Dictionary) -> void:
		sent.append([action, params])


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_host = MainScript.new()
	_host.set("_force_profile", UiProfileScript.for_id("admin"))
	add_child(_host)
	# the stream instance: same binary, different role, decided BEFORE it enters the tree
	_stream = MainScript.new()
	_stream.set("_force_profile", UiProfileScript.for_id("stream"))
	add_child(_stream)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_host.call("_autostart")
		return
	if _frame < 40 or _frame % 20 != 0:
		return
	_report()


func _report() -> void:
	# --- the stream instance must own NO admin surface at all ---
	var sp = _stream.get("_panel")
	if sp != null:
		_fail("the stream role built an admin panel - roles are not isolated")
	else:
		print("HG-12: stream role carries no admin panel (is_host=%s)" % str(_stream.get("_is_host")))

	var panel = _host.get("_panel")
	if panel == null:
		_fail("the admin host has no panel object (is_host=%s)" % str(_host.get("_is_host")))
		_finish()
		return
	var gate = _host.get("_gate")
	if gate == null:
		_fail("no admin token gate wired - admin actions are unguarded")
	elif not (gate.has_method("is_guarded") and gate.has_method("authorize")):
		# The gate used to be "checked" by reading `gate.get("require_token")` - a property that does
		# not exist on admin_gate.gd, so the line printed `null` and proved nothing (found by the admin
		# audit, 19.10). Exercise the behaviour instead.
		_fail("the admin gate has no is_guarded/authorize - the token check cannot be exercised")
	else:
		var guarded: bool = bool(gate.is_guarded())
		var empty_ok: bool = bool(gate.authorize(""))
		if guarded and empty_ok:
			_fail("the token gate is configured with a token but accepts an EMPTY one")
		elif not guarded and not empty_ok:
			_fail("the token gate is open (no token configured) yet refuses an empty presented token")
		else:
			print("HG-12: token gate behaves as configured (guarded=%s, empty token accepted=%s)" % [str(guarded), str(empty_ok)])
		# BOTH CONFIGURATIONS, not just the one this smoke happens to run in. The live match has no
		# token, so the guarded path would never be exercised and a broken guarded path would hide
		# (measured: with authorize() accepting everything, the first version of this check still
		# PASSED, because the open configuration made every answer "true" and therefore "consistent").
		var ctrl = gate.get("_controller")
		gate.setup(ctrl, "hg12-secret")
		var refuses_empty: bool = not bool(gate.authorize(""))
		var accepts_right: bool = bool(gate.authorize("hg12-secret"))
		var refuses_wrong: bool = not bool(gate.authorize("hg12-nope"))
		gate.setup(ctrl, "")
		if not (refuses_empty and accepts_right and refuses_wrong):
			_fail("the guarded token path is broken: refuses_empty=%s accepts_right=%s refuses_wrong=%s" % [str(refuses_empty), str(accepts_right), str(refuses_wrong)])
		else:
			print("HG-12: guarded token path exercised (secret refused empty + accepted right + refused wrong)")

	# F12 through the handler the app really uses
	var ev := InputEventKey.new()
	ev.keycode = KEY_F12
	ev.pressed = true
	var before: bool = (panel as Control).visible
	_host.call("_unhandled_key_input", ev)
	var after: bool = (panel as Control).visible
	if before == after:
		_fail("F12 did not toggle the admin panel (visible stayed %s)" % str(before))
	else:
		print("HG-12: F12 toggles the panel (%s -> %s)" % [str(before), str(after)])
	if not after:
		_host.call("_unhandled_key_input", ev)
	(panel as Control).visible = true
	(panel as CanvasItem).move_to_front()

	var labels := 0
	var buttons := 0
	var stack: Array = [panel]
	while stack.size() > 0:
		var nd = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
			if c is Label and str((c as Label).text).strip_edges() != "":
				labels += 1
			if c is Button and str((c as Button).text).strip_edges() != "":
				buttons += 1
	print("HG-12: admin panel anatomy: %d labels, %d buttons" % [labels, buttons])
	if labels < 10 or buttons < 8:
		_fail("the admin panel is an empty shell (%d labels, %d buttons)" % [labels, buttons])
	_check_observer()
	_finish()


## The observer half (HG-12 / UiProfile.stream): input dead on every path, no buttons, wider
## journal. The real stream instance gives the launch-role half; a crafted view with a live
## FakeRemote proves the input half (with the guard the wire hears nothing, without it - it
## does, which is exactly what makes the first assert meaningful).
func _check_observer() -> void:
	var sgv = _stream.get("_game_view")
	if sgv == null:
		_fail("stream: no game view")
	elif not bool(sgv.get("_observer")):
		_fail("stream role: the view is not in observer mode (input_enabled=%s)" % str(_stream.get("_profile").input_enabled))
	else:
		_obs_checks += 1
		var src = sgv.find_child("rightcol", true, false)
		var w: float = (src as Control).custom_minimum_size.x if src != null else -1.0
		if absf(w - 400.0) > 1.0:
			_fail("stream: the observer journal is %spx wide, F-57 wants 400" % str(w))
		else:
			_obs_checks += 1
			print("HG-12: stream view is observer (input dead, journal 400px)")

	# crafted tree: a LOCAL seat that turns into an observer (the autodetect path)
	var gv = GameViewScript.new()
	add_child(gv)
	gv.setup_cold(null)
	var fake := FakeRemote.new()
	gv.set_remote_session(fake)
	gv.set_human_pid(0)
	gv.set_observer(true)
	gv.apply_projection({
		"phase": "TURN_START", "round": 1, "turn_player": 0, "holder": 0,
		"legal": ["roll", "buy"], "pending": {}, "players": [], "board": [],
	})
	var row = gv.find_child("act", true, false).get("_btn_row")
	var nbtn: int = (row as Container).get_child_count() if row != null else -1
	if nbtn != 0:
		_fail("an observer's console offered %d button(s)" % nbtn)
	else:
		_obs_checks += 1
	# a press (or a hotkey path) must not reach the wire - the session is attached and live
	gv.call("_submit", 0, "roll", {})
	if not fake.sent.is_empty():
		_fail("an observer SENT over the wire: %s" % str(fake.sent))
	else:
		_obs_checks += 1
	# ...and the same call without the guard DOES reach it: the stub proves the check bites
	gv.set_observer(false)
	gv.call("_submit", 0, "roll", {})
	if fake.sent.size() != 1:
		_fail("the wire recorder never fired even unguarded - the observer check proves nothing")
	else:
		_obs_checks += 1
		print("HG-12: observer input is dead (0 sent guarded, 1 sent unguarded)")
	# the AUTODETECT: a screen with no LOCAL/ADMIN seat becomes an observer by itself
	gv.set_human_pid(-1)
	if not bool(gv.get("_observer")):
		_fail("a screen with no local seat did not fall into observer mode")
	else:
		_obs_checks += 1
	gv.queue_free()


func _finish() -> void:
	if _obs_checks < MIN_OBSERVER_CHECKS and _fails.is_empty():
		_fail("only %d observer check(s) ran - the gate aborted silently (want >= %d)" % [_obs_checks, MIN_OBSERVER_CHECKS])
	if _fails.is_empty():
		print("==> HG-12 PASSED (admin panel builds, F12 toggles, token gate present, stream role clean, observer input dead)")
		get_tree().quit(0)
	else:
		print("==> HG-12 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
