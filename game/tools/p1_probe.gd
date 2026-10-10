extends Node
## P1 behavioral probe — verifies spec §11 P1 (colors + tokens):
##   1. Owner marker color == token halo color == players-panel row color
##      (probe compares hex across the three consumers).
##   2. 4 tokens on one tile do NOT overlap (probe: pairwise distances
##      >= 0.7 x piece diameter).
##   3. Tokens are SVG sprites (not the old letter circles) — a TextureRect
##      child exists on each token.
##   4. Players panel shows position BY TILE NAME (not "@11").
## Run windowed: godot --path game res://tools/p1_probe.tscn

const MainScript := preload("res://main.gd")
const PI := preload("res://core/player_identity.gd")

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

	# --- start the game with 4 default seats (Host LOCAL + 3 AI) ---
	var overlay = _launcher.get("_overlay")
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("engine not built after START")
		return

	# --- 1) color consistency across the three consumers ---
	_check_color_consistency(gv)

	# --- 2) 4 tokens on one tile do not overlap ---
	await _check_fan_out(gv)

	# --- 3) tokens are SVG sprites ---
	_check_svg_tokens(gv)

	# --- 4) players panel shows position by tile name ---
	_check_position_by_name(gv)

	if _had_fail:
		quit(1)
	else:
		print("P1 PROBE: ALL PASSED")
		quit(0)

## Owner marker (tile_view) color == token halo color == players-panel row color.
func _check_color_consistency(gv) -> void:
	var board = gv._board_scene._board
	var players_panel = gv._players
	# Give player 0 a property so the owner marker is visible, then repaint.
	var eng = gv.engine
	eng.players[0].add_ownership(1)   # tile 1 (Sunset Blvd) to player 0
	board.refresh_state(_spectator(gv))
	board.refresh_tokens(_spectator(gv).get("players", []))
	players_panel.sync(_spectator(gv), gv.seats)

	# token halo color for player 0
	var tok = board._tokens.get(0)
	if tok == null:
		_fail("no token for player 0")
		return
	var halo_color: Color = tok.color

	# owner marker color on tile 1
	var tv = board._tile_nodes[1]
	var marker_color: Color = tv._owner_stripe.color

	# players-panel row color for player 0
	var row_color := _row_color(players_panel, 0)

	if not _same_color(halo_color, marker_color):
		_fail("token halo %s != owner marker %s" % [halo_color.to_html(), marker_color.to_html()])
		return
	if not _same_color(halo_color, row_color):
		_fail("token halo %s != players-panel row %s" % [halo_color.to_html(), row_color.to_html()])
		return
	print("PASS: owner marker == token halo == players-panel row (%s)" % halo_color.to_html())

## 4 tokens on one tile fan out so pairwise distances >= 0.7 x diameter.
func _check_fan_out(gv) -> void:
	var board = gv._board_scene._board
	var eng = gv.engine
	# Disable animations so positions are instant (no walk tween in flight).
	for pid in 4:
		board._tokens[pid].set_animations(false)
	# Teleport all 4 players to tile 6 (Cedar Ave) and repaint.
	for pid in 4:
		eng._teleport(pid, 6)
	board.refresh_state(_spectator(gv))
	board.refresh_tokens(_spectator(gv).get("players", []))
	for _i in 5:
		await get_tree().process_frame

	var centers: Array = []
	for pid in 4:
		var tok = board._tokens.get(pid)
		if tok == null:
			_fail("missing token %d" % pid)
			return
		centers.append(tok.position + tok.size * 0.5)
	var diameter: float = board._tokens[0].size.x
	var min_dist := INF
	for i in 4:
		for j in range(i + 1, 4):
			var d: float = centers[i].distance_to(centers[j])
			min_dist = minf(min_dist, d)
	if min_dist < diameter * 0.7:
		_fail("tokens overlap: min pairwise dist %.1f < 0.7*diam %.1f" % [min_dist, diameter * 0.7])
		return
	print("PASS: 4 tokens on one tile fan out (min dist %.1f >= 0.7*diam %.1f)" % [min_dist, diameter * 0.7])

## Tokens are SVG sprites (a TextureRect child), not the old letter circles.
func _check_svg_tokens(gv) -> void:
	var board = gv._board_scene._board
	for pid in 4:
		var tok = board._tokens.get(pid)
		if tok == null:
			_fail("missing token %d" % pid)
			return
		if not tok._has_sprite:
			_fail("token %d has no SVG sprite (fell back to letter circle)" % pid)
			return
	print("PASS: all tokens are SVG sprites")

## Players panel shows position by tile name (not "@11").
func _check_position_by_name(gv) -> void:
	var players_panel = gv._players
	var eng = gv.engine
	eng._teleport(0, 1)   # Sunset Blvd
	players_panel.sync(_spectator(gv), gv.seats)
	var text := _row_text(players_panel, 0)
	if text.find("Sunset") == -1:
		_fail("players panel should show position by tile name, got: %s" % text)
		return
	if text.find("@1") != -1 and text.find("Sunset") == -1:
		_fail("players panel still shows raw tile index")
		return
	print("PASS: players panel shows position by tile name")

func _spectator(gv) -> Dictionary:
	return load("res://sdk/projection.gd").new().for_spectator(gv.engine)

func _same_color(a: Color, b: Color) -> bool:
	return a.to_html() == b.to_html()

func _row_color(panel, pid: int) -> Color:
	# find the row whose name label color we can read; simplest: the avatar halo
	for c in panel._list.get_children():
		var halo := _find_halo(c)
		if halo != null:
			return halo.color
	return Color.WHITE

func _find_halo(node) -> ColorRect:
	if node is ColorRect:
		return node
	for c in node.get_children():
		var r := _find_halo(c)
		if r != null:
			return r
	return null

func _row_text(panel, pid: int) -> String:
	# concatenate all label text in the first row
	var out := ""
	for c in panel._list.get_children():
		out += _collect_text(c)
		break
	return out

func _collect_text(node) -> String:
	var out := ""
	if node is Label:
		out += str(node.text) + " "
	for c in node.get_children():
		out += _collect_text(c)
	return out

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
