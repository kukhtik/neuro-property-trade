extends Node
## P2 probe — tile rendering at different CELL sizes.
##
## REWRITTEN. This probe was reading nine fields that no longer exist (`_compact`,
## `_owner_frame`, `_owner_badge`, `_base`, `_house_row`, `_mortgage_hatch`, `_select_frame`,
## `_active_frame`) and calling a method nothing implements. GDScript returns `null` for a missing
## property instead of failing loudly, so the probe reported FAILURES about a TileView that had
## been refactored away and reported NOTHING about the one that ships — the same shape as an audit
## that reads four files out of sixty-eight.
##
## It now reads the real API: `_step` for the degradation level, `_owner_stripe` / `_badge` /
## `_badge_label` for ownership, `_bg.fill_texture` / `_icon` for art, `_strip` for buildings, and
## the `_bg` metadata that `set_selected` / `set_target` write for highlighting.
##
##   1. `_step_for` maps a tile's REAL size to a degradation step (0 best .. 3 worst)
##   2. no label overflows its tile
##   3. the full name is shown on a tile big enough for it
##   4. ownership draws a stripe and a badge carrying an initial
##   5. art is wired (face texture, corner/type icons, building strip)
##   6. a mortgaged tile is visually distinct
##   7. selection and target highlight through the face metadata
## Run windowed: godot --path game res://tools/p2_probe.tscn

const MainScript := preload("res://main.gd")

var _had_fail := false
var _launcher


func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no GameView at launch")
		return

	# --- start the game with 4 default seats ---
	var overlay = _launcher.get("_overlay")
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("engine not built after START")
		return

	var board = gv._board_scene._board
	var eng = gv.engine

	_check_steps(board)          # 1
	_check_no_overflow(board)    # 2
	_check_full_name(board, gv)  # 3
	_check_owner(board, eng, gv) # 4
	_check_art(board)            # 5
	_check_mortgage(board, eng, gv)  # 6
	_check_highlights(board)     # 7

	if _had_fail:
		quit(1)
	else:
		print("P2 PROBE: ALL PASSED")
		quit(0)


## The step follows the size the LAYOUT produced, not the size the caller asked for: corners are
## 1.4x and eat width, so asking the board for 48px tiles yields 43px tiles — the worst step. The
## old probe asserted "48 -> full", which the geometry makes impossible.
func _check_steps(board) -> void:
	var tv = board._tile_nodes[1]
	var cases := {92: 0, 78: 0, 70: 1, 60: 1, 50: 2, 48: 2, 43: 3, 30: 3}
	for cell in cases:
		var got: int = tv.call("_step_for", int(cell))
		if got != int(cases[cell]):
			_fail("cell=%d: step=%d, expected %d" % [cell, got, int(cases[cell])])
			return
	print("PASS: degradation steps match tile size (8 sizes)")


## Walk every tile's labels and assert they stay inside the tile rect.
## Labels are children of the tile, so their position is RELATIVE to the tile;
## compare against the tile's local rect (0,0,size).
func _check_no_overflow(board) -> void:
	var bad := 0
	for tv in board._tile_nodes:
		var tile_rect := Rect2(Vector2.ZERO, tv.size)
		for c in tv.get_children():
			if c is Label and c.visible and c.text != "":
				var lr := Rect2(c.position, c.size)
				if lr.position.x < -1 or lr.position.y < -1 or \
				   lr.end.x > tile_rect.size.x + 1 or lr.end.y > tile_rect.size.y + 1:
					bad += 1
	if bad > 0:
		_fail("%d labels overflow their tile" % bad)
		return
	print("PASS: no label overflows its tile")


## At a size in the FULL band the whole name is shown, not the short one.
func _check_full_name(board, gv) -> void:
	board._cell = 92
	board._rebuild()
	# refresh the rebuilt tiles with a projection so names populate
	board.refresh_state(_spectator(gv))
	var tv = board._tile_nodes[1]   # Sunset Blvd
	if int(tv._step) > 1:
		_fail("cell=92: step=%d, expected the full-name band" % int(tv._step))
		return
	if tv._name.text != "Sunset Blvd":
		_fail("cell=92 should show full name 'Sunset Blvd', got '%s'" % tv._name.text)
		return
	print("PASS: full name shown on a 92px tile")


## Give player 0 a property, repaint, and assert owner stripe + badge.
func _check_owner(board, eng, gv) -> void:
	eng.players[0].add_ownership(1)
	board.refresh_state(_spectator(gv))
	var tv = board._tile_nodes[1]
	if not tv._owner_stripe.visible:
		_fail("owner stripe not visible on owned tile")
		return
	if not tv._badge.visible:
		_fail("owner badge not visible on owned tile")
		return
	if tv._badge_label.text == "":
		_fail("owner badge has no initial")
		return
	print("PASS: owner stripe + badge present (initial '%s')" % tv._badge_label.text)


## The tile face is a painted texture; corner/type tiles carry an icon; buildings live in a strip.
func _check_art(board) -> void:
	var tv = board._tile_nodes[1]
	if tv._bg.fill_texture == null:
		_fail("tile face has no texture (the face paint is not wired)")
		return
	var corner = board._tile_nodes[0]   # Start / GO
	if corner._icon.texture == null:
		_fail("corner icon texture not wired")
		return
	var tax = board._tile_nodes[4]
	if tax._icon.texture == null:
		_fail("type icon texture not wired")
		return
	board._tile_nodes[1].set_houses(2)
	if board._tile_nodes[1]._strip == null:
		_fail("building strip not built (houses cannot be drawn)")
		return
	print("PASS: art wired (face texture, corner/type icons, building strip)")


## A mortgaged tile desaturates its BAND and raises the hatch. The earlier version of this probe
## checked `_base`, a field that no longer exists; the refresh writes `_band.modulate`, so a probe
## looking at the face would report "not distinct" about a tile that is drawn perfectly well.
func _check_mortgage(board, eng, gv) -> void:
	eng._mortgaged.append(1)
	board.refresh_state(_spectator(gv))
	var tv = board._tile_nodes[1]
	var hatch = tv._overlay.get_node_or_null("Hatch")
	if hatch == null:
		_fail("mortgage hatch node missing")
		return
	if not hatch.visible:
		_fail("mortgage hatch not visible on a mortgaged tile")
		return
	if tv._band.modulate == Color.WHITE:
		_fail("mortgaged tile band not dimmed")
		return
	print("PASS: mortgaged tile dims its band and shows the hatch")


## `set_selected` / `set_target` write metadata on the face; that IS the highlight.
func _check_highlights(board) -> void:
	var tv = board._tile_nodes[1]
	tv.set_selected(true)
	if not tv._bg.has_meta("state"):
		_fail("selected state not applied to the tile face")
		return
	tv.set_selected(false)
	if tv._bg.has_meta("state"):
		_fail("selected state should clear")
		return
	tv.set_target(true)
	if not tv._bg.has_meta("target"):
		_fail("target marker not applied to the tile face")
		return
	tv.set_target(false)
	print("PASS: selection + target highlight through the face metadata")


func _spectator(gv) -> Dictionary:
	return load("res://sdk/projection.gd").new().for_spectator(gv.engine)


func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)


func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
