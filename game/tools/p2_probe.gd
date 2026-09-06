extends Node
## P2 behavioral probe — verifies spec §11 P2 (tiles):
##   1. cell=48 → FULL mode (full name, 2-line autowrap); cell=36 → COMPACT
##      mode (short name, 1-line ellipsis).
##   2. No Label overflows its tile (walk the tree: label rect inside tile).
##   3. The `short` name is NOT clipped at cell >= 48 (full name shown).
##   4. Owner = 2px frame + round badge with the owner's initial.
##   5. SVG art wired: tile.svg base, house/hotel sprites, corner/type icons.
##   6. Mortgage → desaturated base + hatch overlay visible.
##   7. Highlight frames: active (glow) + selected (dashed) render.
## Run windowed: godot --path game res://tools/p2_probe.tscn

const MainScript := preload("res://main.gd")
const TileView := preload("res://visual/tile_view.gd")
const TL := preload("res://visual/tile_layout.gd")

var _launcher
var _had_fail := false

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

	# --- 1) full vs compact mode ---
	_check_mode(board, 48, false)   # full mode
	_check_mode(board, 36, true)    # compact mode

	# --- 2) no label overflows its tile ---
	_check_no_overflow(board)

	# --- 3) short name not clipped at cell >= 48 ---
	_check_short_name(board)

	# --- 4) owner frame + badge ---
	await _check_owner(board, eng, gv)

	# --- 5) SVG art wired ---
	_check_svg_art(board)

	# --- 6) mortgage hatch ---
	await _check_mortgage(board, eng, gv)

	# --- 7) highlight frames ---
	_check_highlights(board)

	if _had_fail:
		quit(1)
	else:
		print("P2 PROBE: ALL PASSED")
		quit(0)

## Rebuild the board at a given cell and assert the mode (full vs compact).
func _check_mode(board, cell: int, expect_compact: bool) -> void:
	board._cell = cell
	board._rebuild()
	# pick a property tile with a long name (e.g. tile 1 Sunset Blvd)
	var tv = board._tile_nodes[1]
	var compact: bool = tv._compact
	if compact != expect_compact:
		_fail("cell=%d: compact=%s, expected %s" % [cell, compact, expect_compact])
		return
	# full mode: autowrap on (2 lines); compact: autowrap off (1 line)
	var wrap_on: bool = (tv._name.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	if expect_compact and wrap_on:
		_fail("cell=%d compact: name should be 1-line (autowrap off)" % cell)
		return
	if not expect_compact and not wrap_on:
		_fail("cell=%d full: name should be 2-line (autowrap on)" % cell)
		return
	print("PASS: cell=%d -> %s mode" % [cell, "compact" if expect_compact else "full"])

## Walk every tile's labels and assert they stay inside the tile rect.
## Labels are children of the tile, so their position is RELATIVE to the tile;
## compare against the tile's local rect (0,0,size).
func _check_no_overflow(board) -> void:
	var bad := 0
	for tv in board._tile_nodes:
		var tile_rect := Rect2(Vector2.ZERO, tv.size)
		for c in tv.get_children():
			if c is Label and c.visible:
				var lr := Rect2(c.position, c.size)
				if lr.position.x < -1 or lr.position.y < -1 or \
				   lr.end.x > tile_rect.size.x + 1 or lr.end.y > tile_rect.size.y + 1:
					bad += 1
	if bad > 0:
		_fail("%d labels overflow their tile" % bad)
		return
	print("PASS: no label overflows its tile")

## At cell >= 48 the full name is shown (not the short one).
func _check_short_name(board) -> void:
	board._cell = 48
	board._rebuild()
	# refresh the rebuilt tiles with a projection so names populate
	board.refresh_state(_spectator(_launcher.get("_game_view")))
	var tv = board._tile_nodes[1]   # Sunset Blvd
	var shown: String = tv._name.text
	if shown != "Sunset Blvd":
		_fail("cell=48 should show full name 'Sunset Blvd', got '%s'" % shown)
		return
	print("PASS: full name shown at cell=48")

## Give player 0 a property, repaint, and assert owner frame + badge.
func _check_owner(board, eng, gv) -> void:
	eng.players[0].add_ownership(1)
	board.refresh_state(_spectator(gv))
	var tv = board._tile_nodes[1]
	if not tv._owner_frame.visible:
		_fail("owner frame not visible on owned tile")
		return
	if not tv._owner_badge.visible:
		_fail("owner badge not visible on owned tile")
		return
	if tv._badge_label.text == "":
		_fail("owner badge has no initial")
		return
	print("PASS: owner frame + badge present (initial '%s')" % tv._badge_label.text)

## Assert SVG art is wired: tile.svg base, house sprite, corner/type icons.
func _check_svg_art(board) -> void:
	# base is a TextureRect with a texture (tile.svg)
	var tv = board._tile_nodes[1]
	if tv._base.texture == null:
		_fail("tile base has no texture (tile.svg not wired)")
		return
	# corner tile has an icon texture
	var corner = board._tile_nodes[0]   # Start / GO
	if corner._icon.texture == null:
		_fail("corner icon texture not wired (go_arrow.svg)")
		return
	# type tile (tax) has an icon texture
	var tax = board._tile_nodes[4]
	if tax._icon.texture == null:
		_fail("type icon texture not wired (tax.svg)")
		return
	# houses: give a property houses and check a sprite child appears
	board._tile_nodes[1].refresh({"type": "property", "group": "brown", "cost": 60,
		"name": "Sunset Blvd", "short": "Sunset Blvd", "owner": -1, "houses": 2,
		"mortgaged": false})
	var has_house_sprite := false
	for c in board._tile_nodes[1]._house_row.get_children():
		if c is TextureRect and c.texture != null:
			has_house_sprite = true
	if not has_house_sprite:
		_fail("house SVG sprite not wired")
		return
	print("PASS: SVG art wired (tile base, corner/type icons, house sprites)")

## Mortgage a tile and assert desaturation + hatch overlay.
func _check_mortgage(board, eng, gv) -> void:
	eng._mortgaged.append(1)
	board.refresh_state(_spectator(gv))
	var tv = board._tile_nodes[1]
	if not tv._mortgage_hatch.visible:
		_fail("mortgage hatch not visible on mortgaged tile")
		return
	if tv._base.modulate == Color.WHITE:
		_fail("mortgaged tile base not desaturated")
		return
	print("PASS: mortgage desaturates base + shows hatch")

## Active + selected highlight frames render.
func _check_highlights(board) -> void:
	board.set_selected_tile(1)
	if not board._tile_nodes[1]._select_frame.visible:
		_fail("selected frame not visible")
		return
	board._tile_nodes[1].set_active(true)
	if not board._tile_nodes[1]._active_frame.visible:
		_fail("active frame not visible")
		return
	board.set_selected_tile(-1)
	if board._tile_nodes[1]._select_frame.visible:
		_fail("selected frame should clear on -1")
		return
	print("PASS: active + selected highlight frames render")

func _spectator(gv) -> Dictionary:
	return load("res://sdk/projection.gd").new().for_spectator(gv.engine)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
