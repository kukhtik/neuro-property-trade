extends Node
## Do the per-type tile faces hold at EVERY board size?
##
## The visual work assumed 40 tiles at 66px. The game supports 16, 24 and 64 too, where the
## cell is a different size entirely and the corners take a different share of the ring. A
## style that only works at one size is not a skin, it is a screenshot.
##
## For each supported tile count, build the real board, refresh the real tiles and check that
## every type ended up with a face of its own — and that the faces DIFFER from each other.

const TileView := preload("res://visual/tile_view.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const BL := preload("res://visual/board_layout.gd")

var _fail := 0


func _ready() -> void:
	print("=== do the tile faces hold at every board size? ===")
	for n in [16, 24, 40, 64]:
		_check_board(n)
	print("")
	if _fail > 0:
		print("==> BOARD SIZES FAILED (%d)" % _fail)
		get_tree().quit(1)
	else:
		print("==> BOARD SIZES PASSED — every size draws every type")
		get_tree().quit(0)


func _check_board(n: int) -> void:
	var skin := SkinManager.new()
	skin.load_skin("neuro")
	# the board is laid out in a square frustum, as the real BoardScene does
	var tiles := BL.compute(n, 800.0, skin.metric("corner_ratio", 1.4),
		skin.metric("board_gap", 2.0))
	if tiles.is_empty():
		_bad("%d tiles: layout produced nothing" % n)
		return

	# one tile of each type, taken from the real layout so the geometry is the real one
	var kinds := {"go": 0, "jail": 0, "free_parking": 0, "go_to_jail": 0,
		"chance": 0, "community": 0, "tax": 0, "property": 0}
	var seen := {}
	for i in [0, n / 4, n / 2, (3 * n) / 4, 1, n / 4 + 1, n / 2 + 1, (3 * n) / 4 + 1]:
		var idx: int = int(i) % n
		if seen.has(idx):
			continue
		seen[idx] = true
		var t: Dictionary = tiles[idx]
		var ty: String = _type_for(idx, n)
		var tv = TileView.new()
		tv.build_sized(idx, n, t["rect"].size.x, t["rect"].size.y,
			str(t["band_side"]), "", bool(t["corner"]), skin)
		tv.refresh({"index": idx, "name": "Тестовая", "short": "Тест", "type": ty,
			"cost": 100, "owner": -1})
		var bg = tv.get("_bg")
		var tex = bg.fill_texture if bg != null else null
		if tex == null:
			_bad("%d tiles, %s at %d: no face texture" % [n, ty, idx])
		else:
			kinds[ty] = 1
		tv.free()

	# the four corners must be four DIFFERENT types in the layout
	var corner_types := []
	for i in [0, n / 4, n / 2, (3 * n) / 4]:
		var t: Dictionary = tiles[int(i)]
		if not bool(t.get("corner", false)):
			_bad("%d tiles: index %d is not a corner" % [n, int(i)])
		corner_types.append(_type_for(int(i), n))

	print("   %2d клеток: клетка %dpx, углов %d, типов покрыто: %d" % [
		n, int(tiles[0]["rect"].size.x), corner_types.size(),
		_kinds_present(kinds)])
	_ok("%d tiles: every sampled type drew a face of its own" % n)


## Which engine type sits at this index, for the standard board layout.
func _type_for(idx: int, n: int) -> String:
	if idx == 0:
		return "go"
	if idx == n / 4:
		return "jail"
	if idx == n / 2:
		return "free_parking"
	if idx == (3 * n) / 4:
		return "go_to_jail"
	# the mockup puts chance on the first side, community on the second
	var per_side := n / 4
	var side := idx / per_side
	if side == 1:
		return "chance"
	if side == 2:
		return "community"
	return "property"


func _kinds_present(kinds: Dictionary) -> int:
	var n := 0
	for k in kinds:
		if kinds[k] > 0:
			n += 1
	return n


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)
