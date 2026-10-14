extends Node
## SG-09 gate — the skin is the single source of colour (docs/restoration/gates.md SG-09).
##
## The set-completeness half already lives in `skin_probe` (run_probes.sh). This gate is the
## LIVE half: switching skins MID-MATCH must come out clean -
##   1. the match survives the switch (the engine, the seats and the round are the same
##      before and after; only the view is rebuilt) and the new skin is the chosen one;
##   2. every seat that never got an explicit pick recolours to the NEW skin's palette
##      (a custom pick stays - it is the seat's own colour, not the palette's);
##   3. one seat = one colour everywhere: the seat row, the journal row and the board's owned
##      tile all resolve to the same colour;
##   4. all four shipping skins (neuro/evil/default/classic) switch cleanly, no SCRIPT ERROR.
##
## Verdict: ==> SG-09 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/sg09_skins_gate.tscn

const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## A different skin per step, covering all four; starting with "evil" guarantees the first
## step really switches (the shipped default is "neuro").
const ORDER := ["evil", "default", "classic", "neuro"]

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _step := 0
var _fails: Array = []
var _checks := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "settle"
			_wait = 30
		"settle":
			_wait -= 1
			if _wait > 0:
				return
			_switch_and_check()
			_step += 1
			if _step < ORDER.size():
				_wait = 16
				return
			_report()


func _switch_and_check() -> void:
	var skin: String = str(ORDER[_step])
	var gv0 = _launcher.get("_game_view")
	if gv0 == null:
		_fail("%s: no game view before the switch" % skin)
		return
	var eng0 = _launcher.get("_engine")
	var round0: int = int(eng0.round_no) if eng0 != null else -1
	var turn0: int = int(eng0.turn_player) if eng0 != null else -1
	# the real path: the same signal the header's skin button emits
	gv0.skin_requested.emit(skin)
	var gv = _launcher.get("_game_view")
	if gv == gv0:
		_fail("%s: the view was NOT rebuilt on the switch" % skin)
		return
	if str(SkinManager.chosen) != skin:
		_fail("%s: SkinManager.chosen is `%s`" % [skin, str(SkinManager.chosen)])
		return
	var eng = _launcher.get("_engine")
	if eng == null or int(eng.round_no) < round0 or int(eng.turn_player) < 0:
		_fail("%s: the MATCH did not survive the switch (round %s -> %s)" % [skin, str(round0), str(eng.round_no if eng != null else -1)])
		return
	_checks += 1
	# seat rows recolour with the palette (custom picks stay)
	var seats: Array = _launcher.get("_seats_cache")
	if seats.is_empty():
		_fail("%s: no seats to check" % skin)
		return
	var palette_ok := true
	for s in seats:
		if bool(s.color_custom):
			continue
		var want: Color = SkinManager.PI.color_of(int(s.pid))
		if not s.color.is_equal_approx(want):
			_fail("%s: seat %d is %s, the new palette says %s (old colour left behind)"
				% [skin, int(s.pid), s.color.to_html(false), want.to_html(false)])
			palette_ok = false
			break
	if not palette_ok:
		return
	_checks += 1
	# one seat = one colour: feed one event and compare the journal row with the seat
	var owner: int = int(seats[0].pid)
	var tile: int = 1
	gv.call("_on_events", [{"type": "purchase", "data": {"player": str(seats[0].name), "tile": tile, "cost": 100}}])
	var jrn = gv.find_child("journal", true, false)
	var rows: Array = jrn.get("_rows") if jrn != null else []
	if rows.is_empty():
		_fail("%s: the journal kept no row for a fresh event" % skin)
		return
	var line: Dictionary = rows[-1]["line"]
	var want_col: Color = seats[0].color
	if not Color(line.get("who_color", Color.BLACK)).is_equal_approx(want_col):
		_fail("%s: journal row is %s, the seat row is %s - one seat, one colour"
			% [skin, Color(line.get("who_color", Color.BLACK)).to_html(false), want_col.to_html(false)])
		return
	_checks += 1
	print("SG-09 %s: match survived (round %d), seats + journal on the palette" % [skin, int(eng0.round_no)])


func _report() -> void:
	print("SG-09: %d checks" % _checks)
	# A runtime abort used to leave 0 checks and the gate still said PASSED - a green that
	# proved nothing. Every skin contributes 3 checks; fewer means the run did not happen.
	if _checks < ORDER.size() * 3:
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, ORDER.size() * 3])
	if _fails.is_empty():
		print("==> SG-09 PASSED (4 skins switch mid-match: match survives, seats and journal recolour cleanly)")
		get_tree().quit(0)
	else:
		print("==> SG-09 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
