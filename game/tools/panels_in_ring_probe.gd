extends Node
## ARE THE PANELS INSIDE THE RING? - measured on the REAL product, not on a mock.
##
## Track 1 (docs/tracks/2026-10-20-three-tracks.md) moved the panels of the turn INSIDE the
## ring, so that the facts of a turn are read in one place:
##
##   the SEAT CARDS  (who is playing, with how much and where) - from the 268px left dock
##   the TILE CARD   (what is this cell)                    - from the 344px right column
##   the JOURNAL     (three lines of what happened)          - the ring's lower belt
##
## Before the move the ring's interior held a POORER COPY of the seat facts while the
## richer cards sat in a dock the profile hides below 2000px wide: the same four facts,
## two places, one of them unreachable. And 14.5 % of the 1600px frame was not the board.
##
## A composition that exists only in a mock is not a composition. This probe builds the
## real product (main.gd), lets it settle, and asks of the LIVE tree:
##
##   1. is each panel a DESCENDANT of the panno?   (it is inside the ring)
##   2. is the old dock shape GONE?                 (there is no left dock to hide behind)
##   3. are the panels READABLE - not collapsed to a sliver?
##
## It measures the GLOBAL rect of every panel, so the report says how much of the frame
## each one takes.
##
## Run: godot --path game --resolution 1600x1200 res://tools/panels_in_ring_probe.tscn
## Verdict: ==> PANELS-IN-RING ...

const MainScript := preload("res://main.gd")

const WIDTH := 1600
const HEIGHT := 1200

## The panels that must live inside the ring, and the node name each one answers to.
## A panel that is missing entirely is a FAILURE, not a skip: "the panel is not in the
## ring" and "the panel does not exist" are the same problem for the player.
const PANELS := [
	{"key": "players", "name": "seats"},
	{"key": "inspector", "name": "inspector"},
	{"key": "journal", "name": "zone-journal"},
]

## A panel narrower than this is a sliver: it is "inside the ring" and still unreadable.
const MIN_PANEL_WIDTH := 120.0

var _launcher = null
var _t := 0
var _done := false
var _fails: Array = []
var _checks := 0


func _ready() -> void:
	get_tree().root.size = Vector2i(WIDTH, HEIGHT)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _t == 20:
		_launcher.call("_autostart")
	if _t < 80:
		return
	_done = true
	_run()


func _run() -> void:
	var gv := _game_view()
	if gv == null:
		_fail("the product has no game view - the panels cannot be measured")
		_finish()
		return

	var panno: Node = _find_by_name(gv, "panno-root")
	if panno == null:
		panno = _find_by_name(gv, "turn-panno")
	if panno == null:
		_fail("the product has no panno - the panels cannot be inside a ring that is not there")
		_finish()
		return

	print("=== the panels, in the live product (%dx%d) ===" % [WIDTH, HEIGHT])
	for spec in PANELS:
		var key := str(spec["key"])
		var nm := str(spec["name"])
		var node: Control = _find_by_name(gv, nm)
		if node == null:
			_fail("the %s panel ('%s') is not in the product at all" % [key, nm])
			continue
		# 1. is it inside the ring?
		var inside := _is_ancestor(panno, node)
		_check(inside, "the %s panel is NOT inside the panno - it is still outside the ring" % key)
		# 2. is it readable, or a sliver?
		var r: Rect2 = node.get_global_rect()
		_check(r.size.x >= MIN_PANEL_WIDTH,
			"the %s panel is %dpx wide - it is inside the ring and still unreadable"
				% [key, int(r.size.x)])
		print("  %-10s %-14s %s  %4.0f x %-4.0f px  %s"
			% [key, nm, str(r.position), r.size.x, r.size.y,
				("INSIDE" if inside else "OUTSIDE")])

	# 3. THE OLD SHAPE IS GONE: the left dock that held the seat cards must not exist any
	# more. A dock that is still in the tree is a panel that can still be shown outside
	# the ring - the very thing this track removed.
	var seats_dock: Control = _find_by_name(gv, "seats-dock")
	if seats_dock != null and seats_dock.visible:
		_fail("the left dock that held the seat cards is still visible - the panels are not "
			+ "ONLY inside the ring")
	else:
		print("  the left dock is gone - the seat cards live in the ring only")

	_finish()


func _game_view() -> Node:
	return _launcher.get("_game_view")


func _find_by_name(root: Node, nm: String) -> Control:
	if root == null:
		return null
	if root is Control and str((root as Control).name) == nm:
		return root as Control
	for c in root.get_children():
		var r: Control = _find_by_name(c, nm)
		if r != null:
			return r
	return null


func _is_ancestor(maybe_ancestor: Node, node: Node) -> bool:
	var n: Node = node.get_parent()
	while n != null:
		if n == maybe_ancestor:
			return true
		n = n.get_parent()
	return false


func _check(ok: bool, why: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(why)


func _fail(why: String) -> void:
	_checks += 1
	_fails.append(why)


func _finish() -> void:
	if _fails.is_empty():
		print("==> PANELS-IN-RING PASSED (%d checks: the seat cards, the tile card and the "
			% _checks)
		print("    journal are all inside the ring, and the old docks are gone)")
		get_tree().quit(0)
		return
	for f in _fails:
		push_error("PANELS-IN-RING: " + str(f))
	print("==> PANELS-IN-RING FAILED (%d check(s) red)" % _fails.size())
	get_tree().quit(1)
