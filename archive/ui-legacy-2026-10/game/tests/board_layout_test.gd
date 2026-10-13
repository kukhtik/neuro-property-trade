extends RefCounted
## Tests for the parametric board geometry (BoardLayout).
##
## The stage-3 DoD: tile_count 16/24/40/64 must produce a square ring with no
## overlapping cells, fully covering the perimeter — and nothing may assume 40.

const BL := preload("res://visual/board_layout.gd")

static func test_list() -> Array[String]:
	return [
		"test_count_is_parametric", "test_all_sizes_no_overlap",
		"test_ring_is_square", "test_tile_count_from_board",
		"test_corner_indices", "test_corner_is_larger",
		"test_index0_is_bottom_right", "test_winding_is_counterclockwise",
		"test_band_faces_the_centre", "test_center_rect_inside_ring",
		"test_ring_is_fully_covered", "test_degenerate_inputs",
		"test_tile_center_anchor", "test_engine_loads_generated_boards",
		"test_generated_boards_are_wellformed"]

const SIZES := [16, 24, 40, 64]

static func test_count_is_parametric() -> String:
	# the whole point: geometry follows n, it does not assume 40
	for n in SIZES:
		var tiles := BL.compute(n, 800.0, 1.4, 2.0)
		if tiles.size() != n:
			return "compute(%d) produced %d tiles" % [n, tiles.size()]
		# each side holds n/4 tiles, one of them a corner
		var d: int = n / 4
		var per_side := {}
		for t in tiles:
			var s: int = t["side"]
			per_side[s] = int(per_side.get(s, 0)) + 1
		if per_side.size() != 4:
			return "n=%d should span 4 sides, got %d" % [n, per_side.size()]
		for s in per_side:
			if int(per_side[s]) != d:
				return "n=%d side %d has %d tiles, expected %d" % [n, s, per_side[s], d]
	return ""

static func test_all_sizes_no_overlap() -> String:
	for n in SIZES:
		for side in [400.0, 800.0, 1200.0]:
			var tiles := BL.compute(n, side, 1.4, 2.0)
			if not BL.rects_do_not_overlap(tiles):
				return "n=%d side=%.0f: tiles overlap" % [n, side]
	return ""

static func test_ring_is_square() -> String:
	for n in SIZES:
		var tiles := BL.compute(n, 900.0, 1.4, 2.0)
		if not BL.is_square(tiles, 900.0):
			return "n=%d: ring is not square" % n
	# a different corner ratio must still fill the same square
	for n in SIZES:
		var tiles2 := BL.compute(n, 900.0, 1.1, 2.0)
		if not BL.is_square(tiles2, 900.0):
			return "n=%d cr=1.1: ring is not square" % n
	return ""

static func test_tile_count_from_board() -> String:
	# geometry must be driven by the real board length, so changing the board
	# file changes the layout with no code edit
	for n in SIZES:
		var tiles := BL.compute(n, 640.0, 1.4, 2.0)
		var max_index := -1
		for t in tiles:
			max_index = maxi(max_index, int(t["index"]))
		if max_index != n - 1:
			return "n=%d: max tile index should be %d, got %d" % [n, n - 1, max_index]
	return ""

static func test_corner_indices() -> String:
	for n in SIZES:
		var d: int = n / 4
		var tiles := BL.compute(n, 700.0, 1.4, 2.0)
		var corners: Array = []
		for t in tiles:
			if t["corner"]:
				corners.append(int(t["index"]))
		corners.sort()
		var want := [0, d, 2 * d, 3 * d]
		if corners != want:
			return "n=%d corners should be %s, got %s" % [n, str(want), str(corners)]
	return ""

static func test_corner_is_larger() -> String:
	# The corner is larger ALONG the edge; across the ring every tile is the
	# same u (that is what keeps the ring the same thickness everywhere).
	var n := 40
	var tiles := BL.compute(n, 800.0, 1.4, 2.0)
	var corner_along := 0.0
	var normal_along := 0.0
	for t in tiles:
		var r: Rect2 = t["rect"]
		# extent along the edge: x for the top/bottom rows, y for the sides
		var along: float = r.size.x if int(t["side"]) % 2 == 0 else r.size.y
		if t["corner"]:
			corner_along = along
		elif normal_along == 0.0:
			normal_along = along
	if corner_along <= normal_along:
		return "a corner (%.1f along) should be larger than a normal cell (%.1f)" % [corner_along, normal_along]
	var ratio := corner_along / normal_along
	if absf(ratio - 1.4) > 0.05:
		return "corner_ratio should be ~1.4, got %.3f" % ratio
	return ""

static func test_index0_is_bottom_right() -> String:
	var n := 40
	var side := 800.0
	var tiles := BL.compute(n, side, 1.4, 2.0)
	var r0: Rect2 = tiles[0]["rect"]
	# index 0 must sit at the bottom-right: right half, bottom half
	if r0.position.x < side / 2.0:
		return "tile 0 should be on the right half (x=%.1f)" % r0.position.x
	if r0.position.y < side / 2.0:
		return "tile 0 should be on the bottom half (y=%.1f)" % r0.position.y
	if str(tiles[0]["side"]) != "0":
		return "tile 0 should belong to side 0 (bottom)"
	return ""

static func test_winding_is_counterclockwise() -> String:
	# bottom runs right-to-left, so tile 1 is LEFT of tile 0
	var n := 40
	var side := 800.0
	var tiles := BL.compute(n, side, 1.4, 2.0)
	var c0 := BL.tile_center(tiles, 0)
	var c1 := BL.tile_center(tiles, 1)
	if c1.x >= c0.x:
		return "tile 1 should be left of tile 0 (%.1f vs %.1f)" % [c1.x, c0.x]
	# the left column runs upward, so the tile after the left corner is above
	var d: int = n / 4
	var corner_l := BL.tile_center(tiles, d)
	var next_l := BL.tile_center(tiles, d + 1)
	if next_l.y >= corner_l.y:
		return "the left column should run upward (%.1f vs %.1f)" % [next_l.y, corner_l.y]
	return ""

static func test_band_faces_the_centre() -> String:
	var n := 40
	var tiles := BL.compute(n, 800.0, 1.4, 2.0)
	var want := {"0": "top", "1": "right", "2": "bottom", "3": "left"}
	for t in tiles:
		var b := str(t["band_side"])
		if b != want[str(t["side"])]:
			return "side %d band should face '%s', got '%s'" % [t["side"], want[str(t["side"])], b]
	return ""

static func test_center_rect_inside_ring() -> String:
	for n in SIZES:
		var side := 900.0
		var tiles := BL.compute(n, side, 1.4, 2.0)
		var c := BL.center_rect(n, side, 1.4, 2.0)
		if c.size.x <= 0.0 or c.size.y <= 0.0:
			return "n=%d: centre rect is empty (%s)" % [n, str(c)]
		# the centre must not touch any tile
		for t in tiles:
			if c.intersects(t["rect"], true):
				return "n=%d: centre rect overlaps tile %d" % [n, t["index"]]
	return ""

static func test_ring_is_fully_covered() -> String:
	# without gaps the ring's tiles must tile the perimeter exactly:
	# covered area == outer square - centre hole
	for n in SIZES:
		var side := 900.0
		var tiles := BL.compute(n, side, 1.4, 0.0)
		var c := BL.center_rect(n, side, 1.4, 0.0)
		var ring_area: float = side * side - c.size.x * c.size.y
		var covered := BL.covered_area(tiles)
		if absf(covered - ring_area) > ring_area * 0.02:
			return "n=%d: ring covered %.0f, expected %.0f" % [n, covered, ring_area]
	return ""

static func test_degenerate_inputs() -> String:
	# bad input must return an empty layout, never crash or divide by zero
	for bad in [0, 7, 15, 41, 100]:
		var tiles := BL.compute(bad, 800.0, 1.4, 2.0)
		if not tiles.is_empty():
			return "compute(%d) should be empty (not a multiple of 4 in 16..64)" % bad
	if not BL.compute(40, 0.0, 1.4, 2.0).is_empty():
		return "a zero side should produce no layout"
	if not BL.compute(40, -10.0, 1.4, 2.0).is_empty():
		return "a negative side should produce no layout"
	# a huge gap can eat all the space -> empty, not negative rects
	if not BL.compute(40, 100.0, 1.4, 50.0).is_empty():
		return "an impossible gap should produce no layout"
	return ""

static func test_tile_center_anchor() -> String:
	var n := 40
	var tiles := BL.compute(n, 800.0, 1.4, 2.0)
	for t in [0, 5, 19, 20, 39]:
		var c := BL.tile_center(tiles, t)
		var r: Rect2 = tiles[t]["rect"]
		var expect := r.position + r.size * 0.5
		if c != expect:
			return "tile_center(%d) should be the rect centre" % t
	# an unknown index yields zero rather than crashing
	if BL.tile_center(tiles, 999) != Vector2.ZERO:
		return "an unknown index should return Vector2.ZERO"
	return ""

## The engine must actually load board_<N>.json for each configured size —
## otherwise settings.tile_count stays a dead switch (the other half of the
## "no 40 hardcode" requirement).
static func test_engine_loads_generated_boards() -> String:
	var E := preload("res://core/engine.gd")
	var S := preload("res://core/game_settings.gd")
	for n in [16, 24, 40, 64]:
		var s = S.new()
		s.tile_count = n
		var e = E.new()
		e.setup(s, ["A", "B"])
		if e.board.tile_count() != n:
			return "tile_count=%d loaded %d tiles" % [n, e.board.tile_count()]
		# the four corners must keep their canonical identity at any size
		var d: int = n / 4
		var want := ["go", "jail", "free_parking", "go_to_jail"]
		for k in 4:
			var got: String = e.board.type_at(k * d)
			if got != want[k]:
				return "n=%d corner %d should be '%s', got '%s'" % [n, k, want[k], got]
	return ""

## A generated board must be internally consistent: contiguous indices and a
## name on every cell (the UI renders names from the board, never from code).
static func test_generated_boards_are_wellformed() -> String:
	for n in [16, 24, 64]:
		var path := "res://data/board_%d.json" % n
		if not FileAccess.file_exists(path):
			return "missing %s (run tools/gen_boards.py)" % path
		var f := FileAccess.open(path, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if not (d is Dictionary) or not d.has("tiles"):
			return "%s is not a board file" % path
		var tiles: Array = d["tiles"]
		if tiles.size() != n:
			return "%s has %d tiles, expected %d" % [path, tiles.size(), n]
		for i in tiles.size():
			if int(tiles[i].get("index", -1)) != i:
				return "%s: tile %d has index %s" % [path, i, str(tiles[i].get("index"))]
			if str(tiles[i].get("name", "")) == "":
				return "%s: tile %d has no name" % [path, i]
	return ""
