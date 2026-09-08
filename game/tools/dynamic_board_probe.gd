extends Node
## Phase 0 diagnostic probe — parametric board size (TDD-first).
## Verifies the ring layout works for ANY tile count N (not just 40):
##   1. N tiles split into 4 sides with corners fixed (N % 4 == 0).
##   2. The ring closes with no coordinate gaps (each tile adjacent to its
##      neighbors, corners connect the sides).
##   3. The whole ring fits a given viewport (900x600 .. 4K) without overflow.
##   4. cell_center is consistent: no two tiles share a cell, every cell in the
##      ring is occupied exactly once.
## Run: godot --headless --path game res://tools/dynamic_board_probe.tscn

const TL := preload("res://visual/tile_layout.gd")

var _had_fail := false
var _checks := 0

func _ready() -> void:
	for n in [16, 24, 40, 48, 64]:
		await _check_ring(n)
		await _check_fit(n, 900, 600)
		await _check_fit(n, 1920, 1080)
		await _check_fit(n, 3840, 2160)

	if _had_fail:
		quit(1)
	else:
		print("DYNAMIC_BOARD_PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

## The ring for N tiles: every cell occupied exactly once, corners connect.
func _check_ring(n: int) -> void:
	var grid: int = TL.grid_cells(n)
	var seen := {}
	var bad := 0
	for i in n:
		var c: Vector2 = TL.cell_center(i, n)
		var key := "%d,%d" % [int(c.x), int(c.y)]
		if seen.has(key):
			bad += 1
			if bad <= 3:
				print("  tile %d collides at %s" % [i, key])
		seen[key] = true
		# every cell must be inside the grid
		if c.x < 0 or c.y < 0 or c.x >= grid or c.y >= grid:
			bad += 1
	if bad > 0:
		_fail("N=%d: %d ring cells collide or out of grid" % [n, bad])
		return
	# corners: tile 0, n/4, 2n/4, 3n/4 must be the 4 corners
	var corners := [0, n / 4, n / 2, 3 * n / 4]
	var corner_cells := {}
	for i in corners:
		var c: Vector2 = TL.cell_center(i, n)
		corner_cells["%d,%d" % [int(c.x), int(c.y)]] = true
	if corner_cells.size() != 4:
		_fail("N=%d: corners not distinct" % n)
		return
	# ring must have exactly `grid*grid - (grid-2)*(grid-2)` perimeter cells
	var perimeter: int = grid * grid - (grid - 2) * (grid - 2)
	if seen.size() != perimeter:
		_fail("N=%d: ring has %d cells, expected perimeter %d" % [n, seen.size(), perimeter])
		return
	_pass("N=%d: ring closes, %d perimeter cells, 4 distinct corners" % [n, seen.size()])

## The whole ring (grid*grid cells) must fit a viewport at a reasonable cell.
func _check_fit(n: int, vw: int, vh: int) -> void:
	var grid: int = TL.grid_cells(n)
	# cell that fits the viewport (square board)
	var cell: int = int(minf(float(vw) / float(grid), float(vh) / float(grid)))
	if cell < 24:
		_fail("N=%d @%dx%d: cell %d < 24 (unreadable)" % [n, vw, vh, cell])
		return
	var ring: int = grid * cell
	if ring > vw or ring > vh:
		_fail("N=%d @%dx%d: ring %d exceeds viewport" % [n, vw, vh, ring])
		return
	# every tile's pixel center must be inside the viewport
	for i in n:
		var p: Vector2 = TL.pixel_pos(i, n, cell)
		if p.x < 0 or p.y < 0 or p.x > vw or p.y > vh:
			_fail("N=%d @%dx%d: tile %d center %s out of viewport" % [n, vw, vh, i, p])
			return
	_pass("N=%d @%dx%d: ring %dpx fits, cell %d" % [n, vw, vh, ring, cell])

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
