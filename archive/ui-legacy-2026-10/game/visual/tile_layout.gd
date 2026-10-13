class_name TileLayout
extends RefCounted
## Pure layout math for the 40-tile ring board. No scene nodes — headless
## testable. Standard 11x11 grid: 9 side cells + 2 corner cells per edge.
## Tile 0 is the bottom-left corner; movement is counterclockwise (0 -> 1 ..).

static func side_cells(tile_count: int) -> int:
	return (tile_count / 4) - 1   # 40/4 - 1 = 9 side cells between corners

static func grid_cells(tile_count: int) -> int:
	return side_cells(tile_count) + 2   # 11

## Cell center (in cell units) for a tile index. Top-left origin.
static func cell_center(index: int, tile_count: int) -> Vector2:
	var grid: int = grid_cells(tile_count)
	var s: int = grid - 1   # max index 0..s
	var n := tile_count / 4
	var seg := index / n          # 0=bottom,1=right,2=top,3=left
	var off := index % n          # position within the segment
	match seg:
		0:  return Vector2(s - off, s)          # bottom row, leftwards (x decreases)
		1:  return Vector2(0, s - off)          # right col, upwards (y decreases)
		2:  return Vector2(off, 0)              # top row, rightwards (x increases)
		3:  return Vector2(s, off)              # left col, downwards (y increases)
	return Vector2.ZERO

## True when index is one of the four corner tiles.
static func is_corner(index: int, tile_count: int) -> bool:
	var n := tile_count / 4
	return index % n == 0   # 0, n, 2n, 3n

## Pixel center given cell size. Used by the scene; pure.
static func pixel_pos(index: int, tile_count: int, cell: int) -> Vector2:
	var c := cell_center(index, tile_count)
	return Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell)
