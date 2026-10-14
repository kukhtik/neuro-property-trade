extends Node
## HG-12 gate (seed) — execution roles (docs/restoration/gates.md, HG-12).
##
## Grown out of the audit's `admin_smoke_probe.gd`. The contract covered here:
##   - the ADMIN host builds the panel, and the panel is a real surface (labels, buttons);
##   - F12 toggles it through the REAL key handler;
##   - the token gate exists (admin actions are guarded);
##   - a STREAM-role instance has NO admin panel at all (the role is decided at launch and
##     cannot be flipped from inside the app - the audit's "три роли изолированы").
## The observer/stream layout contract (input dead, wider journal) extends this gate in P2.
##
## Verdict: ==> HG-12 PASSED / FAILED: <first reason>   (quarantine until P2 closes it fully)
## Run: godot --headless --path game res://tools/gates/hg12_admin_smoke_gate.tscn

const MainScript := preload("res://main.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")

var _host = null
var _stream = null
var _frame := 0
var _fails: Array = []


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
	else:
		print("HG-12: token gate present (require_token=%s)" % str(gate.get("require_token")))

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
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("==> HG-12 PASSED (admin panel builds, F12 toggles, token gate present, stream role clean)")
		get_tree().quit(0)
	else:
		print("==> HG-12 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
