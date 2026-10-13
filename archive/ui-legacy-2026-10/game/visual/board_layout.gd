class_name BoardLayout
extends RefCounted
## Parametric ring-board geometry. Pure math, no scene nodes — headless
## testable, and the single source of tile rectangles so nothing hardcodes a
## tile count (40 used to be baked into five files).
##
## Works for any tile_count that is a multiple of 4 (16..64 per the settings
## range). `d` = tiles per side INCLUDING ONE corner, so a side holds d-1
## ordinary cells plus one corner; the ring is d+1 cells across.
##
## Index 0 is the bottom-RIGHT corner, then counter-clockwise: the bottom edge
## runs right-to-left, the left edge upward, the top edge left-to-right, and the
## right edge downward. Corners are tiles 0, d, 2d, 3d.
##
## Corner cells are `corner_ratio` times a normal cell along the ring, which is
## what gives the board its classic look; `gap` is the space between tiles.

## A computed tile rectangle plus the context a TileView needs to orient
## its band and badges.
##   index     tile index
##   rect      Rect2 in board-local pixels
##   side      0=bottom (index..d), 1=left, 2=top, 3=right
##   corner    true for the four corner tiles
##   band_side "bottom" | "left" | "top" | "right" — the INNER edge of the ring
static func compute(n: int, side: float, corner_ratio: float = 1.4, gap: float = 2.0) -> Array:
	var out: Array = []
	# the settings expose 16..64 in steps of 4; anything else is a caller bug
	if n < 16 or n > 64 or n % 4 != 0 or side <= 0.0:
		return out
	var d: int = n / 4                 # tiles per side incl. one corner

	# Ring geometry: (d+1) cells across, i.e. one corner, then d-1 ordinary cells,
	# then the next corner. A corner is a cr*u × cr*u square in the board's
	# outer corner; ordinary cells are u wide. Along one edge:
	#   cr*u + (d-1)*u + cr*u + d*gap = side
	# Each edge owns exactly ONE corner (the one it leads with); the corner at
	# the far end belongs to the next edge. That is what keeps the corners from
	# being emitted twice — the classic double-counting bug here.
	var cr: float = maxf(corner_ratio, 1.0)
	var denom: float = 2.0 * cr + float(d - 1)
	var u: float = (side - gap * float(d)) / denom
	if u <= 0.0:
		return out
	var cs: float = cr * u                # corner size, both directions

	for i in n:
		var s: int = i / d             # 0=bottom,1=left,2=top,3=right
		var j: int = i % d             # position along that side
		var a: float                   # offset along the edge, from its start
		var along: float               # extent along the edge
		if j == 0:
			a = 0.0                    # this edge's own corner
			along = cs
		else:
			a = cs + gap + float(j - 1) * (u + gap)
			along = u
		var rect: Rect2
		var band: String
		match s:
			0:  # bottom edge, running right-to-left
				rect = Rect2(side - a - along, side - cs, along, cs)
				band = "top"
			1:  # left edge, running upward
				rect = Rect2(0.0, side - a - along, cs, along)
				band = "right"
			2:  # top edge, running left-to-right
				rect = Rect2(a, 0.0, along, cs)
				band = "bottom"
			_:  # right edge, running downward
				rect = Rect2(side - cs, a, cs, along)
				band = "left"
		out.append({
			"index": i,
			"rect": rect,
			"side": s,
			"corner": j == 0,
			"band_side": band,
		})
	return out


## The inner rectangle (board centre) between the ring's inner edges.
static func center_rect(n: int, side: float, corner_ratio: float = 1.4, gap: float = 2.0) -> Rect2:
	var tiles := compute(n, side, corner_ratio, gap)
	if tiles.is_empty():
		return Rect2()
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for t in tiles:
		var r: Rect2 = t["rect"]
		min_x = minf(min_x, r.position.x)
		min_y = minf(min_y, r.position.y)
		max_x = maxf(max_x, r.end.x)
		max_y = maxf(max_y, r.end.y)
	# ring thickness: the inner boundary is set by the first tile's inward edge,
	# which spans `u` (every tile, corner included, is `u` across).
	var first: Rect2 = tiles[0]["rect"]
	var thickness: float = minf(first.size.x, first.size.y)
	if absf(first.size.x - first.size.y) < 0.001:
		# a square tile (side 2 or 3 orientation) — thickness is either side
		thickness = first.size.x
	return Rect2(
		min_x + thickness + gap,
		min_y + thickness + gap,
		(max_x - min_x) - 2.0 * (thickness + gap),
		(max_y - min_y) - 2.0 * (thickness + gap)
	)


## True when the rects tile the ring without overlapping.
static func rects_do_not_overlap(tiles: Array) -> bool:
	for a in tiles.size():
		var ra: Rect2 = tiles[a]["rect"]
		for b in range(a + 1, tiles.size()):
			var rb: Rect2 = tiles[b]["rect"]
			if ra.intersects(rb, true):   # true => touching counts as overlap
				return false
	return true


## The ring is square, i.e. its bounding box is as wide as the board.
static func is_square(tiles: Array, side: float, tol: float = 0.5) -> bool:
	if tiles.is_empty():
		return false
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for t in tiles:
		var r: Rect2 = t["rect"]
		min_x = minf(min_x, r.position.x)
		min_y = minf(min_y, r.position.y)
		max_x = maxf(max_x, r.end.x)
		max_y = maxf(max_y, r.end.y)
	return absf((max_x - min_x) - side) <= tol and absf((max_y - min_y) - side) <= tol


## Total covered area of the ring; used to assert the ring is fully covered.
static func covered_area(tiles: Array) -> float:
	var total := 0.0
	for t in tiles:
		var r: Rect2 = t["rect"]
		total += r.size.x * r.size.y
	return total


## Pixel centre of a tile — the anchor the EffectLayer places tokens at.
static func tile_center(tiles: Array, index: int) -> Vector2:
	for t in tiles:
		if int(t["index"]) == index:
			var r: Rect2 = t["rect"]
			return r.position + r.size * 0.5
	return Vector2.ZERO
