extends Node
## IS THE TILE CARD INSIDE THE RING? - measured on the REAL product, not on a mock.
##
## Concept A (21.10) puts the tile card (the inspector) in the ring's lower belt, beside
## the journal: "what happened" and "what is this tile" are two views of the same turn.
## Before the move, the card sat in the shell's right column - 344px of a 1600px frame
## (14.5 %) that was NOT the board.
##
## A composition that only exists in a mock is not a composition. This probe builds the
## real product (main.gd), lets it settle, and then asks three questions of the LIVE tree:
##
##   1. is the card a descendant of the panno?      (it is inside the ring)
##   2. is it OUTSIDE the panno?                    (the old shape is gone)
##   3. does it share the lower belt with the journal? (they are side by side)
##
## It measures the card's GLOBAL rect and the ring's interior, so the report says how
## much of the frame is board and how much is the card.
##
## Run: godot --path game --resolution 1600x1200 res://tools/inspector_in_ring_probe.tscn
## Verdict: ==> INSPECTOR-IN-RING ...

const MainScript := preload("res://main.gd")

const WIDTH := 1600
const HEIGHT := 1200

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
	var card: Control = _find_card()
	if card == null:
		_fail("the product has no tile card (the inspector) in its tree")
		_finish()
		return

	# the panno: the ring's interior panel
	var gv := _game_view()
	var panno: Node = _find_by_name(gv, "panno-root")
	if panno == null:
		panno = _find_by_name(gv, "turn-panno")
	if panno == null:
		_fail("the product has no panno - the card cannot be inside a ring that is not there")
		_finish()
		return

	# 1. is the card INSIDE the panno?
	var inside := _is_ancestor(panno, card)
	_check(inside, "the tile card is NOT inside the panno - it is still outside the ring")

	# 2. is the card in the LOWER belt, beside the journal?
	var belt := _belt_of(card)
	_check(belt == "bottom",
		"the tile card is in the %s belt - the lower belt holds the journal and the card" % belt)

	# 3. does the journal sit BESIDE it (not under it)?
	var journal: Control = _find_by_name(gv, "zone-journal")
	if journal == null:
		_fail("the product has no journal zone")
		_finish()
		return
	var card_rect: Rect2 = card.get_global_rect()
	var jrn_rect: Rect2 = journal.get_global_rect()
	var side_by_side := absf(card_rect.position.x - jrn_rect.position.x) > 20.0
	_check(side_by_side,
		"the tile card and the journal share a left edge (%.0f and %.0f) - they are stacked"
			% [card_rect.position.x, jrn_rect.position.x])

	# the measurement: how much of the frame is the card, and where does it live?
	var frame := Vector2(WIDTH, HEIGHT)
	var area := card_rect.size.x * card_rect.size.y / (frame.x * frame.y) * 100.0
	print("=== the tile card, in the live product (1600x1200) ===")
	print("  the card's rect: %s" % str(card_rect))
	print("  the card's share of the frame: %.1f %%" % area)
	print("  the journal's rect: %s" % str(jrn_rect))
	print("  the card is %s the ring" % ("INSIDE" if inside else "OUTSIDE"))
	_finish()


func _game_view() -> Node:
	return _launcher.get("_game_view")


func _find_card() -> Control:
	var gv := _game_view()
	if gv == null:
		return null
	var found: Control = _find_by_name(gv, "inspector")
	return found


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


## Which belt a node lives in - read from the TREE, because a position is relative to a
## parent and the parent's name says which belt it is.
func _belt_of(node: Node) -> String:
	var n: Node = node.get_parent()
	while n != null:
		if n is Control:
			var nm := str((n as Control).name)
			if nm == "panno-belt-top":
				return "top"
			if nm == "panno-belt-bottom":
				return "bottom"
		n = n.get_parent()
	return "?"


func _check(ok: bool, why: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(why)


func _fail(why: String) -> void:
	_checks += 1
	_fails.append(why)


func _finish() -> void:
	if _fails.is_empty():
		print("==> INSPECTOR-IN-RING PASSED (%d checks: the tile card is inside the ring, in the "
			% _checks)
		print("    lower belt, beside the journal)")
		get_tree().quit(0)
		return
	for f in _fails:
		push_error("INSPECTOR-IN-RING: " + str(f))
	print("==> INSPECTOR-IN-RING FAILED (%d check(s) red)" % _fails.size())
	get_tree().quit(1)
