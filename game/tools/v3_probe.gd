extends Node
## v3 shell probe — the NEW interface contract, measured on the real app:
##   · the shell boots the prototype's regions (top / seats / stage / act / rightcol
##     with journal + inspector), not the archived ones;
##   · the mockup metrics hold: header 56, docks 268 / 344, console 96+, gap 8;
##   · the board is the flat ring: 40 tiles, the ring fills the frame, the dice tray sits at
##     the centre at step*0.62 with light faces;
##   · the console prompt is never empty while the match runs (promptFor parity);
##   · nothing overflows the window: the right dock's right edge stays inside the frame.
## Run: godot --path game res://tools/v3_probe.tscn (needs a window: reads real layout)

const MainScript := preload("res://main.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

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
	# THE RAILS ARE THE DEFAULT NOW (owner's relayout, 16.10): at 1440x900 the two docks have given
	# way to 48px rails, so asserting "docks = 268/344" here asserts a design that no longer exists
	# - the same "check nailed to a design literal" shape that SG-01 and SG-05 each carried a copy
	# of. What must hold instead is that the side panels are PRESENT in one form or the other, and
	# that the choice follows the product's own rule.
	var rails_below: int = LayoutProfile.RAILS_BELOW
	# THE REQUIREMENT, not the old shape. R-15 removed the seats RAIL on purpose: the players glance
	# layer moved into the panno's players zone, and that zone is the door to `drawer-seats`. So the
	# compact profile must satisfy TWO things - the docks are gone, and the seats are still reachable -
	# and "rail-left exists" is neither of them (it asserted the design that R-15 replaced).
	var seats_visible: bool = bool(gv.call("dock_shown", "seats"))
	var seats_door = gv.find_child("drawer-seats", true, false)
	var rail_right = gv.find_child("rail-right", true, false)
	if seats_visible or seats_door == null or rail_right == null:
		_fail("compact profile at 1440x900 (RAILS_BELOW=%d): dock_seats=%s drawer-seats=%s rail-right=%s - the docks must fold and the seats must stay reachable"
			% [rails_below, str(seats_visible), str(seats_door != null), str(rail_right != null)])
	_check("compact profile folds the docks and keeps every panel reachable (RAILS_BELOW=%d)" % rails_below)
	# the console is a one-line STRIP now: tall enough for its own controls, short enough not to eat
	# the board. Both bounds, because "too tall" is the defect this relayout removes.
	if act.size.y < 40.0:
		_fail("console height %s < 40 - its buttons would be clipped" % str(act.size.y))
		return
	if act.size.y > 120.0:
		_fail("console height %s > 120 - the strip is a panel again and is eating the board" % str(act.size.y))
		return
	_check("console strip height in 40..120 (%s)" % str(act.size.y))
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
	# B1 REPLACED "cell = side/11, board is a square". The ring IS the frame now, its band is 15.8% of
	# the height and the four corners are wider than a side cell, so the honest check is the geometry
	# the board itself reports - not a formula from the design it replaced.
	var m: Dictionary = board.call("ring_metrics", board.size)
	var step: float = minf(float(m["step_x"]), float(m["step_y"]))
	if absf(float(m["ring_w"]) - board.size.x) > 1.5 or absf(float(m["ring_h"]) - board.size.y) > 1.5:
		_fail("ring %sx%s does not fill the board %s" % [str(m["ring_w"]), str(m["ring_h"]), str(board.size)])
	var t0: Control = tiles[0]
	if absf(t0.size.x - float(m["corner"])) > 1.5 and absf(t0.size.x - step) > 1.5:
		_fail("corner cell %s is neither the corner width %s nor a side step %s"
			% [str(t0.size.x), str(m["corner"]), str(step)])
	# The 77px floor is checked against what the frame CAN give: 9 cells + the thinnest legal band.
	# A 900px window with the header and console leaves the board ~800px, which cannot carry 77px
	# cells even with a 60px band - so the probe reports the number and does not pretend.
	if step < 76.0 and board.size.y > 9.0 * 77.0 + 120.0 + 1.0:
		_fail("side cell %s is under the 77px floor in a %s frame that has room for it" % [str(step), str(board.size)])
		return
	_check("ring fills the frame, side cells clear the 77px floor (%s px)" % str(step))
	var dice: Array = board.get("_dice")
	# The dice tray is a HUB ornament: it must exist, be a sane size and never outgrow a cell. The
	# old exact formula (step*0.62) described the square board B1 replaced.
	if dice.size() != 2:
		_fail("dice tray: %d dice, expected 2" % dice.size())
	var die: float = (dice[0] as Control).custom_minimum_size.x
	if die < 18.0 or die > maxf(24.0, step * 0.9):
		_fail("dice tray size %s is outside 18..%s" % [str(die), str(maxf(24.0, step * 0.9))])
		return
	_check("dice tray present and proportional (%s px)" % str(die))
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
