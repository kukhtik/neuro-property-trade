extends Node
## Phase 0 diagnostic probe — board geometry "vision" (TDD-first).
## Verifies the tile ring renders correctly BEFORE any fix:
##   1. Band orientation: the group band must face the board CENTER on every
##      side (top row=top, right col=left, bottom row=bottom, left col=right).
##      Root cause confirmed: seg 1 is the LEFT column (x=0) and seg 3 the
##      RIGHT column (x=s), but tile_view maps seg 1->left band and seg 3->right
##      band, so both vertical sides face OUTWARD.
##   2. Icon size: corner/type icons must be <= 0.35 * cell (not fill the tile).
##   3. No label overflow: every visible Label stays inside its tile rect.
##   4. Token spacing: >= 2 pieces on a tile are >= 0.6 * token-size apart.
## Run: godot --headless --path game res://tools/board_layout_probe.tscn

const BoardView := preload("res://visual/board_view.gd")
const TL := preload("res://visual/tile_layout.gd")

var _had_fail := false
var _checks := 0

func _ready() -> void:
	# Build a board at cell=64 (full mode) and cell=36 (compact) and check both.
	# NOTE: every _check_* contains `await`, so each MUST be awaited here or it
	# runs as a detached coroutine that never executes (masked-pass trap).
	await _check_band_orientation(64)
	await _check_band_orientation(36)
	await _check_icon_size(64)
	await _check_icon_size(36)
	await _check_no_overflow(64)
	await _check_no_overflow(36)
	await _check_token_spacing(64)

	if _had_fail:
		quit(1)
	else:
		print("BOARD_LAYOUT_PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

## Build a board at `cell`, refresh with a synthetic projection, and assert the
## band on every tile faces the board center.
func _check_band_orientation(cell: int) -> void:
	var board: Control = BoardView.new()
	board.build(40, cell)
	add_child(board)
	board.refresh_state(_synthetic_proj())
	await get_tree().process_frame

	var grid: int = TL.grid_cells(40)
	var center: Vector2 = Vector2((grid - 1) * 0.5, (grid - 1) * 0.5)
	var bad := 0
	for i in 40:
		var tv = board._tile_nodes[i]
		var c: Vector2 = TL.cell_center(i, 40)
		var to_center: Vector2 = center - c
		# Determine which edge the band is actually on from its rect.
		var band_edge := _edge_of(tv._band)
		var expect := _expected_edge(to_center)
		if band_edge != expect:
			bad += 1
			if bad <= 5:
				print("  band tile %d: edge=%d expect=%d" % [i, band_edge, expect])
	if bad > 0:
		_fail("cell=%d: %d tiles have band facing OUTWARD (not board center)" % [cell, bad])
	else:
		_pass("cell=%d: band faces board center on all 40 tiles" % cell)
	board.queue_free()

## Which edge a rect sits on (0=top,1=left,2=bottom,3=right) given it spans the
## full tile width/height on that edge.
func _edge_of(r: Control) -> int:
	var p: Vector2 = r.position
	var s: Vector2 = r.size
	if s.y <= s.x and p.y <= 0.5:
		return 0
	if s.y <= s.x and p.y > 0.5:
		return 2
	if s.x <= s.y and p.x <= 0.5:
		return 1
	return 3

## Expected band edge given the vector from tile center to board center.
func _expected_edge(to_center: Vector2) -> int:
	if absf(to_center.y) > absf(to_center.x):
		return 0 if to_center.y < 0 else 2
	return 1 if to_center.x < 0 else 3

## Corner/type icons must be <= 0.35 * cell (proportional, not filling the tile).
func _check_icon_size(cell: int) -> void:
	var board: Control = BoardView.new()
	board.build(40, cell)
	add_child(board)
	board.refresh_state(_synthetic_proj())
	await get_tree().process_frame
	var max_frac := 0.35
	var bad := 0
	for i in 40:
		var tv = board._tile_nodes[i]
		if not tv._icon.visible:
			continue
		var s: Vector2 = tv._icon.size
		var frac: float = maxf(s.x, s.y) / float(cell)
		if frac > max_frac + 0.02:
			bad += 1
			if bad <= 5:
				print("  icon tile %d: size %s frac=%.2f" % [i, s, frac])
	if bad > 0:
		_fail("cell=%d: %d icons exceed 0.35*cell (giant, over text)" % [cell, bad])
	else:
		_pass("cell=%d: all icons <= 0.35*cell" % cell)
	board.queue_free()

## No visible Label may overflow its tile rect (local coords).
func _check_no_overflow(cell: int) -> void:
	var board: Control = BoardView.new()
	board.build(40, cell)
	add_child(board)
	board.refresh_state(_synthetic_proj())
	await get_tree().process_frame
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
		_fail("cell=%d: %d labels overflow their tile" % [cell, bad])
	else:
		_pass("cell=%d: no label overflows its tile" % cell)
	board.queue_free()

## >= 2 pieces on a tile must be >= 0.6 * token-size apart (no pile in a corner).
func _check_token_spacing(cell: int) -> void:
	var board: Control = BoardView.new()
	board.build(40, cell)
	add_child(board)
	# 4 players all on tile 0 (GO) — the worst pile case.
	var players := []
	for pid in 4:
		players.append({"index": pid, "position": 0, "name": "P%d" % pid,
			"in_jail": false})
	board.set_seats([])
	board.refresh_tokens(players)
	await get_tree().process_frame
	# token size = max(MIN_PIECE, cell*0.38)
	var tok_size: float = maxf(20.0, float(cell) * 0.38)
	var min_gap: float = tok_size * 0.6
	var centers: Array = []
	for pid in 4:
		var tok = board._tokens[pid]
		centers.append(tok.position + tok.size * 0.5)
	var bad := 0
	for a in centers.size():
		for b in range(a + 1, centers.size()):
			var d: float = (centers[a] - centers[b]).length()
			if d < min_gap - 1.0:
				bad += 1
	if bad > 0:
		_fail("cell=%d: %d token pairs overlap (< 0.6*token-size apart)" % [cell, bad])
	else:
		_pass("cell=%d: 4 co-located tokens spaced >= 0.6*token-size" % cell)
	board.queue_free()

## A synthetic spectator projection with a mix of tile types.
func _synthetic_proj() -> Dictionary:
	var tiles := []
	for i in 40:
		var t := {"index": i, "name": "Tile %d" % i, "short": "T%d" % i,
			"owner": -1, "houses": 0, "mortgaged": false}
		if i == 0:
			t["type"] = "go"
		elif i == 10:
			t["type"] = "jail"
		elif i == 20:
			t["type"] = "free_parking"
		elif i == 30:
			t["type"] = "go_to_jail"
		elif i == 4:
			t["type"] = "tax"; t["amount"] = 200
		elif i == 5:
			t["type"] = "railroad"; t["cost"] = 200
		elif i == 12:
			t["type"] = "utility"; t["cost"] = 150
		elif i == 7:
			t["type"] = "chance"
		elif i == 2:
			t["type"] = "community"
		else:
			t["type"] = "property"; t["group"] = "brown"; t["cost"] = 60
		tiles.append(t)
	return {"turn_player": 0, "players": [], "board": tiles}

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
