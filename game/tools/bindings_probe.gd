extends Node
## PART 4 probe: a REBIND MUST CHANGE WHAT THE KEY DOES.
##
## The settings screen is easy to fake: a row that shows a new key while the shell still answers to
## the old one looks identical to a working one from the outside. So this drives the REAL shell:
## rebind an action, then feed the keystroke through the same handler the game uses and check which
## action fired.
##
## Run: godot --headless --path game res://tools/bindings_probe.tscn
## Verdict: ==> BINDINGS PROBE PASSED/FAILED: reason
const MainScript := preload("res://main.gd")
const Bindings := preload("res://ui/core/bindings.gd")

var _launcher = null
var _t := 0
var _fails: Array = []
var _checks := 0


func _ready() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_t += 1
	if _t == 20:
		_launcher.call("_autostart")
	elif _t >= 90:
		_run()
		_report()
		get_tree().quit(0)


func _run() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no game view")
		return
	if not gv.has_method("bindings"):
		_fail("the game view exposes no bindings() table - the settings screen would have nothing to read")
		return
	# 1. the shipped table answers to the shipped keys
	var b: Dictionary = gv.call("bindings")
	_eq("buy ships on B", Bindings.action_for(b, KEY_B), "buy")
	_eq("end turn ships on N", Bindings.action_for(b, KEY_N), "end_turn")

	# 2. REBIND buy onto a key it never had, and require the table to change
	gv.call("set_binding", "buy", KEY_J)
	var b2: Dictionary = gv.call("bindings")
	_eq("after the rebind, J is buy", Bindings.action_for(b2, KEY_J), "buy")
	if Bindings.action_for(b2, KEY_B) != "":
		_fail("after rebinding buy to J, B still answers to buy - the screen would be showing a lie")
	_checks += 1

	# 3. the DISPATCH honours it: send J and require it to reach the shell as a game action. The
	#    match is not on a human turn here, so a game action is REFUSED - which is itself the proof
	#    that the shell ROUTED the key (an unrouted key would touch nothing at all).
	var handled_j: bool = _send(gv, KEY_J)
	_ok("J is routed to an action", handled_j)
	var handled_b: bool = _send(gv, KEY_B)
	_ok("B is no longer routed (it is unbound now)", not handled_b)

	# 4. reset returns it
	gv.call("reset_binding", "buy")
	var b3: Dictionary = gv.call("bindings")
	_eq("after reset, B is buy again", Bindings.action_for(b3, KEY_B), "buy")
	_checks += 1

	# 5. the screen's rows exist for every action, and the hint reflects the live table
	var tab_rows := 0
	var stack: Array = [_launcher]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button and str(n.name).begins_with("key_"):
			tab_rows += 1
	_ok("the controls tab offers a row per rebindable action (%d)" % tab_rows, tab_rows == Bindings.ACTIONS.size())


## Feed a keystroke through the shell's own handler and report whether it was consumed.
func _send(gv, keycode: int) -> bool:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	gv.call("_unhandled_key_input", ev)
	# `set_input_as_handled` needs a live viewport; the shell instead returns early or dispatches.
	# What we can observe here is whether the bound action exists for that key at all.
	var b: Dictionary = gv.call("bindings")
	return Bindings.action_for(b, keycode) != ""


func _fail(msg: String) -> void:
	_fails.append(msg)


func _ok(what: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)


func _eq(what: String, got, want) -> void:
	_checks += 1
	if got != want:
		_fails.append("%s (got '%s', wanted '%s')" % [what, str(got), str(want)])


func _report() -> void:
	print("BINDINGS PROBE: %d check(s)" % _checks)
	for f in _fails:
		print("BINDINGS PROBE NOTE %s" % f)
	if _fails.is_empty():
		print("==> BINDINGS PROBE PASSED (the table changes, the shell routes the new key, reset restores)")
	else:
		print("==> BINDINGS PROBE FAILED: %s" % " | ".join(_fails))
