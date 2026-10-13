extends RefCounted

const TL := preload("res://visual/tile_layout.gd")

static func test_list() -> Array[String]:
	return ["test_corners", "test_side_tiles", "test_grid_size",
			"test_bottom_segment_order", "test_pixel_pos"]

static func test_corners() -> String:
	var N := 40
	for idx in [0, 10, 20, 30]:
		if not TL.is_corner(idx, N):
			return "expected corner at %d" % idx
	if TL.is_corner(1, N): return "tile 1 not a corner"
	return ""

static func test_grid_size() -> String:
	if TL.grid_cells(40) != 11: return "11x11 grid expected"
	if TL.side_cells(40) != 9:  return "9 side cells expected"
	return ""

static func test_side_tiles() -> String:
	var N := 40
	# bottom row between corners: 1..9 -> x from 9 down to 1, y = 10
	var c = TL.cell_center(1, N)
	if c.x != 9.0 or c.y != 10.0: return "tile1=%s want (9,10)" % c
	var c9 = TL.cell_center(9, N)
	if c9.x != 1.0 or c9.y != 10.0: return "tile9=%s want (1,10)" % c9
	return ""

static func test_bottom_segment_order() -> String:
	var N := 40
	var c0 = TL.cell_center(0, N)   # (10,10) bottom-left corner
	var c1 = TL.cell_center(1, N)   # (9,10) first side cell
	if c0.x - c1.x != 1.0: return "tiles 0..1 should step leftx, got %s,%s" % [c0, c1]
	return ""

static func test_pixel_pos() -> String:
	# cell=40, tile0 cell center (10,10) -> pixel center (420,420)
	var p = TL.pixel_pos(0, 40, 40)
	if p != Vector2(420, 420): return "pixel pos tile0=%s want (420,420)" % p
	return ""
