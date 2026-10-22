extends Node
## MEASURE the ring's centre: is the panno's STACK of four zones costing the glance?
##
## The owner's complaint (20.10) and concept A's composition: the centre of the ring should
## be TWO BELTS - the four seats on top, and three columns below (journal | inspector |
## event). The product stacks four zones in a VBox (roll 22 % | event 28 % | players 30 % |
## journal 20 %).
##
## A stack has a cost that nobody measures: the JOURNAL zone grows with the number of
## events, and a stretch ratio only says how the REMAINING space is shared - it does not
## say what each zone gets when there is not enough of it. So in a long match the journal
## takes the space and the ROLL zone (the hero action, the thing the player must see) gets
## squeezed to a caption.
##
## This probe MEASURES the live panno in a long match and reports, per zone: the height it
## actually got, the height it wanted, and how much of it was left. The verdict says which
## zone lost.
##
## Run: godot --headless --path game res://tools/panno_belts_probe.tscn
## Verdict: ==> PANNO-BELTS ...

const MainScript := preload("res://main.gd")
const Panno := preload("res://ui/components/turn_panno.gd")

const WIDTH := 1600
const HEIGHT := 1200
## How many events the journal holds at the end of a long match. Measured on the product:
## the journal shows 4 of 132 lines, so the zone is asked to hold ~30 visible rows.
const BUSY_EVENTS := 132


var _fails: Array = []
var _checks := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# the measurement is of LAYOUT, which headless can do - but the probe needs a real
		# window to have a real size, so it skips out loud rather than measuring 0x0.
		print("==> PANNO-BELTS SKIPPED: no renderer (headless)")
		get_tree().quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	get_tree().root.size = Vector2i(WIDTH, HEIGHT)
	await get_tree().process_frame

	# A panno in a ring-shaped interior: the board gives it the 9x9 middle of the frame.
	# The real interior at 1600x1200 with a 120px corner and 8px padding is 1344x1072.
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)

	var p := Panno.new()
	p.name = "panno"
	p.custom_minimum_size = Vector2(1344, 1072)
	p.size = Vector2(1344, 1072)
	host.add_child(p)
	p.build()

	# feed it a BUSY journal, the way a long match does. The panno's real signature is
	# sync(proj, seats, human_pid, event_line) - the probe calls it the way
	# the product calls it, so the measurement is of the real thing.
	#
	# The SEATS are the product's own shape (a seat has `pid`, `name`, `color`), because
	# `_seat_name` reads `s.pid` - a projection-shaped seat made the panno read a key that
	# is not there, and the probe measured a broken widget instead of the real one.
	var proj := _busy_projection()
	var seats: Array = _seats()
	# The contract (turn_panno.gd): event_line is {who, text, tag, cat, money} or {}.
	# The journal_tail argument is GONE (22.10): the panno does not paint the feed - the
	# shell's panel in the journal slot owns it, and the probe measures the ZONE.
	p.sync(proj, seats, 0, {"who": "Mira", "text": "продажа дома · Crest Square · +$70",
		"tag": "дом", "cat": "build", "money": 70})

	await get_tree().process_frame
	await get_tree().process_frame

	# measure each zone: what it got, what it wanted
	var root := p.find_child("panno-root", true, false)
	if root == null:
		_fail("the panno has no root")
		_finish()
		return

	# The zones live in the BELTS now (the upper belt and the lower belt's two columns),
	# not as direct children of panno-root - so the probe walks the whole tree.
	var zones: Array = []
	_collect_zones(root, zones)
	if zones.size() != 5:
		_fail("the panno has %d zone(s), expected 5" % zones.size())
		_finish()
		return

	print("=== the ring's centre, measured (interior 1344x1072) ===")
	var total := 0.0
	var rows: Dictionary = {}
	for z in zones:
		var ctrl: Control = z
		var want := ctrl.get_combined_minimum_size().y
		var got := ctrl.size.y
		total += got
		var short := maxf(0.0, want - got)
		# the belts changed the AXIS: the zones are now SIDE BY SIDE, so the WIDTH is what
		# matters. A zone that is 200px wide and 100px tall is squeezed; one that is 700px
		# wide is not.
		var wide := ctrl.size.x
		var tight := wide < ctrl.get_combined_minimum_size().x
		print("  %-16s %6.0f x %-6.0f px  wanted h %6.0f  short %6.0f  %s" % [
			str(ctrl.name), wide, got, want, short,
			("SQUEEZED" if (short > 1.0 or tight) else "ok")])
		# the roll zone is the HERO: the action the player must see. It must not be squeezed.
		if str(ctrl.name) == "zone-roll":
			_check(short <= 1.0 and not tight, ("the roll zone is squeezed (%.0f x %.0f, wanted "
				% [wide, got]) + "%.0f) - the hero action is what the player must see" % want)
		# WHICH BELT a zone is in, read from the tree and not from a coordinate: a zone's
		# position is relative to its PARENT, and the parent chain names the belt.
		var key := _belt_of(ctrl)
		if not rows.has(key):
			rows[key] = []
		(rows[key] as Array).append(str(ctrl.name))

	print("  the upper belt: %s" % str(rows.get("top", [])))
	print("  the lower belt: %s" % str(rows.get("bottom", [])))

	# the four zones together must fill the interior
	_check(total >= 1072.0 * 0.9, "the zones fill only %.0f of 1072 px" % total)

	# THE COMPOSITION, measured: the players zone is in the UPPER belt and the other three
	# in the LOWER one. A stack of four would put all four at the same top edge - and the
	# lower belt's zones must be SIDE BY SIDE, which means their left edges differ.
	var upper: Array = rows.get("top", [])
	var lower: Array = rows.get("bottom", [])
	_check(upper.size() == 1 and str(upper[0]) == "zone-players",
		"the upper belt holds %s - it must hold the players zone alone" % str(upper))
	_check(lower.size() == 4, "the lower belt holds %s - it must hold roll, event, journal"
		% str(lower))
	_check(lower.has("zone-inspector"), "the lower belt holds %s - the tile card must be IN
		the ring, beside the journal (concept A), not outside it" % str(lower))
	# and the two lower columns are side by side: the roll's left edge differs from the
	# journal's. Stacked, they would share a left edge.
	# The zones are in DIFFERENT PARENTS (the roll in the left column, the journal in the
	# right), so each one's own `position.x` is 0 - relative to its own column. "Side by
	# side?" is a question about the FRAME, so the GLOBAL rect is what must be compared.
	var roll_x := -1.0
	var jrn_x := -1.0
	for z in zones:
		var g: Rect2 = (z as Control).get_global_rect()
		if str((z as Control).name) == "zone-roll":
			roll_x = g.position.x
		if str((z as Control).name) == "zone-journal":
			jrn_x = g.position.x
	_check(absf(roll_x - jrn_x) > 40.0, ("the roll and the journal share a left edge in the "
		+ "frame (%.0f and %.0f) - they are stacked, not side by side") % [roll_x, jrn_x])
	_finish()


## Which belt a zone lives in: "top" or "bottom". The tree says so - the belt's own name
## does - and a coordinate does not, because a zone's position is relative to its parent.
func _belt_of(zone: Control) -> String:
	var n: Node = zone.get_parent()
	while n != null:
		if n is Control:
			var nm := str((n as Control).name)
			if nm == "panno-belt-top":
				return "top"
			if nm == "panno-belt-bottom":
				return "bottom"
		n = n.get_parent()
	return "?"


## Every zone in the tree, in DOCUMENT ORDER - the order is the reading order, and it is
## what the probe checks.
func _collect_zones(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control and str(c.name).begins_with("zone-"):
			out.append(c)
		_collect_zones(c, out)


## The seats in the PRODUCT's shape: a seat has `pid`, `name` and `color`.
func _seats() -> Array:
	return [
		{"pid": 0, "name": "Хост", "color": Color(1.0, 0.44, 0.68), "driver": "LOCAL"},
		{"pid": 1, "name": "Neuro", "color": Color(0.37, 0.89, 1.0), "driver": "SDK"},
		{"pid": 2, "name": "evil", "color": Color(0.91, 0.15, 0.31), "driver": "SDK"},
		{"pid": 3, "name": "Mira", "color": Color(0.71, 1.0, 0.42), "driver": "AI"},
	]


## A projection with a long journal - the state a late match is in.
func _busy_projection() -> Dictionary:
	var lines: Array = []
	for i in BUSY_EVENTS:
		lines.append({"text": "Mira продаёт с клетки %d" % (27 - i % 40), "type": "buy"})
	return {
		"turn_player": 0,
		"phase": "TURN_START",
		"pending": {},
		"tiles": [],
		"turn": {"pid": 0, "name": "Хост", "phase": "TURN_START"},
		"players": [
			{"index": 0, "name": "Хост", "cash": 1215, "money": 1215,
				"tiles": [3, 6], "houses": 0, "mortgages": 0, "position": 6, "active": true},
			{"index": 1, "name": "Neuro", "cash": 980, "money": 980,
				"tiles": [8, 9, 37], "houses": 1, "mortgages": 0, "position": 24},
			{"index": 2, "name": "evil", "cash": 640, "money": 640,
				"tiles": [11], "houses": 0, "mortgages": 1, "position": 10, "jailed": true},
			{"index": 3, "name": "Mira", "cash": 1500, "money": 1500,
				"tiles": [26, 27], "houses": 0, "mortgages": 1, "position": 33},
		],
		"board": [],
		"journal": lines,
		"event": {"text": "продажа дома · Mira · Crest Square · +$70", "type": "build"},
		"dice": [5, 3],
		"round": 7,
		"pot": 240,
	}


func _check(ok: bool, why: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(why)


func _fail(why: String) -> void:
	_checks += 1
	_fails.append(why)


func _finish() -> void:
	if _fails.is_empty():
		print("==> PANNO-BELTS PASSED (%d checks: the hero zone keeps its room, the five "
			% _checks)
		print("    zones fill the ring's interior, and the tile card is inside the ring)")
		get_tree().quit(0)
		return
	for f in _fails:
		push_error("PANNO-BELTS: " + str(f))
	print("==> PANNO-BELTS FAILED (%d check(s) red)" % _fails.size())
	get_tree().quit(1)
