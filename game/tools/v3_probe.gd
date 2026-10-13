extends Node
## v3 shell probe — the NEW interface contract, measured on the real app:
##   · the shell boots the prototype's regions (top / seats / stage / act / rightcol
##     with journal + inspector), not the archived ones;
##   · the mockup metrics hold: header 56, docks 268 / 344, console 96+, gap 8;
##   · the board is the flat ring: 40 tiles, cell = side/11, the dice tray sits at the
##     centre at cell*0.62 with light faces;
##   · the console prompt is never empty while the match runs (promptFor parity);
##   · nothing overflows the window: the right dock's right edge stays inside the frame.
## Run: godot --path game res://tools/v3_probe.tscn (needs a window: reads real layout)

const MainScript := preload("res://main.gd")

var _had_fail := false
var _checks := 0
var _n := 0
var _launcher = null


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_n += 1
	if _n == 10:
		_launcher.call("_autostart")
	if _n == 90:
		_run_checks()
		if _had_fail:
			print("V3 PROBE: FAILED (%d checks)" % _checks)
			get_tree().quit(1)
		else:
			print("V3 PROBE: ALL PASSED (%d checks)" % _checks)
			get_tree().quit(0)


func _run_checks() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no game view")
		return
	for nm in ["top", "seats", "stage", "act", "rightcol", "journal", "inspector", "modal", "toast"]:
		var nd = gv.find_child(nm, true, false)
		if nd == null:
			_fail("region '%s' missing from the v3 shell" % nm)
			return
	_check("regions present (top/seats/stage/act/rightcol/journal/inspector/modal/toast)")
	var top: Control = gv.find_child("top", true, false)
	var seats: Control = gv.find_child("seats", true, false)
	var act: Control = gv.find_child("act", true, false)
	var rightcol: Control = gv.find_child("rightcol", true, false)
	if absf(top.size.y - 56.0) > 2.0:
		_fail("header height %s != 56" % str(top.size.y))
		return
	_check("header = 56")
	if absf(seats.size.x - 268.0) > 2.0 or absf(rightcol.size.x - 344.0) > 2.0:
		_fail("docks %s/%s != 268/344" % [str(seats.size.x), str(rightcol.size.x)])
		return
	_check("docks = 268 / 344")
	if act.size.y < 90.0:
		_fail("console height %s < 90" % str(act.size.y))
		return
	_check("console height >= 90")
	if rightcol.global_position.x + rightcol.size.x > 1441.0:
		_fail("right dock overflows the frame: %s + %s" % [str(rightcol.global_position.x), str(rightcol.size.x)])
		return
	_check("no horizontal overflow (right dock inside the frame)")
	var board = gv.get("_board")
	if board == null:
		_fail("no board")
		return
	var tiles: Array = board.get("_tiles")
	if tiles.size() != 40:
		_fail("board tiles %d != 40" % tiles.size())
		return
	_check("board = 40 tiles")
	var cell: float = minf(board.size.x, board.size.y) / 11.0
	var t0: Control = tiles[0]
	if absf(t0.size.x - cell) > 1.5:
		_fail("cell %s != side/11 = %s" % [str(t0.size.x), str(cell)])
		return
	_check("cell = side/11")
	var dice: Array = board.get("_dice")
	if dice.size() != 2 or absf((dice[0] as Control).custom_minimum_size.x - maxf(18.0, roundf(cell * 0.62))) > 1.5:
		_fail("dice tray broken (size %s vs cell*0.62)" % str((dice[0] as Control).custom_minimum_size.x) if dice.size() > 0 else "no dice")
		return
	_check("dice tray at cell*0.62")
	board.call("set_dice", 3, 4)
	if str(board.get("_sum").text) != "7" or not (board.get("_sum") as Control).visible:
		_fail("sum chip wrong after 3+4")
		return
	_check("sum chip shows 7")
	var hint: Control = act.get("_hint")
	if hint == null or str(hint.text).strip_edges() == "":
		_fail("console prompt is empty while the match runs")
		return
	_check("console prompt is never empty")


func _check(msg: String) -> void:
	_checks += 1
	print("PASS: %s" % msg)


func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: %s" % msg)
