class_name BoardView
extends Control
## Code-built board from a projection + BoardLayout/SkinManager. Repaints on
## refresh_state(proj). Read-only downstream consumer of the engine projection.
## Each tile is a TileView widget (group band, name, price, corner icon, owner
## marker, houses as figures). Tokens are SVG pieces with a PlayerIdentity halo
## (P1), fanned out when several players share a tile, active player bobs.
##
## P1: colors/tokens come from PlayerIdentity (single source) — the owner
## marker, the piece halo and the players-panel row can never disagree.

signal tile_clicked(index: int)
signal tile_hovered(index: int)   # P4 §7: observer inspector on hover

const BL := preload("res://visual/board_layout.gd")
const PI := preload("res://core/player_identity.gd")
const TileView := preload("res://visual/tile_view.gd")
const TokenPanel := preload("res://visual/token_panel.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

var _tile_nodes: Array[TileView] = []
var _tokens := {}              # pid -> TokenPanel
var _cell := 64
var _tile_count := 0   # set by build(); never assume 40 — the board is parametric
var _seats: Array = []         # of Seat (for token_id + color resolution)
var _skin: SkinManager
var _layout: Array = []        # BoardLayout.compute output (rects + band sides)

## Build the board control. tile_count + cell size.
func build(tile_count: int, cell: int = 64, skin: SkinManager = null) -> Control:
	_cell = cell
	_tile_count = tile_count
	_skin = skin if skin != null else SkinManager.new()
	_skin.load_skin()
	# parametric geometry: rects for any tile count, with band orientation
	_layout = BL.compute(tile_count, float(BL_side()), _skin.metric("corner_ratio", 1.4),
		_skin.metric("board_gap", 2.0))
	var size := BL_side()
	custom_minimum_size = Vector2(size, size)
	set_size(Vector2(size, size))

	var bkg = ColorRect.new()
	bkg.color = _skin.color("board_bg", Color("22303c"))
	bkg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bkg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bkg)

	_rebuild()
	return self

## The board side in px, derived from the tile count and the cell size so the
## ring always fits (d+1 cells across).
func BL_side() -> float:
	var d: int = maxi(1, _tile_count / 4)
	return float(d + 1) * float(_cell)

## Provide the seat list so tokens resolve their token_id + color from the
## seat (which was assigned from PlayerIdentity). Call before refresh_tokens.
func set_seats(seats: Array) -> void:
	_seats = seats

## Rebuild the board at the current `_cell` (used by probes to test different
## cell sizes / compact mode). Frees the old tile nodes and recreates them.
func _rebuild() -> void:
	for tv in _tile_nodes:
		if is_instance_valid(tv):
			tv.queue_free()
	_tile_nodes.clear()
	_tokens.clear()
	_layout = BL.compute(_tile_count, float(BL_side()), _skin.metric("corner_ratio", 1.4),
		_skin.metric("board_gap", 2.0))
	var size := BL_side()
	custom_minimum_size = Vector2(size, size)
	set_size(Vector2(size, size))
	for entry in _layout:
		var i: int = int(entry["index"])
		var r: Rect2 = entry["rect"]
		var tv: TileView = TileView.new()
		# the tile is built at the exact geometry BoardLayout produced, and told
		# which edge faces the centre so its band is oriented without a formula
		tv.build_sized(i, _tile_count, r.size.x, r.size.y,
			str(entry["band_side"]), "", bool(entry["corner"]), _skin)
		tv.position = r.position
		tv.size = r.size
		tv.z_index = 1
		tv.gui_input.connect(_on_tile_input.bind(i))
		_tile_nodes.append(tv)
		add_child(tv)

## Repaint from a spectator projection dictionary (for_spectator output).
func refresh_state(proj: Dictionary) -> void:
	_last_turn_player = int(proj.get("turn_player", -1))
	var tiles: Array = proj.get("board", [])
	for entry in tiles:
		var idx: int = int(entry.get("index", 0))
		if idx < 0 or idx >= _tile_nodes.size(): continue
		_tile_nodes[idx].refresh(entry)
	update_highlight(proj)

## Highlight the tile the given player index is on (spectacle active-player).
## Uses a glowing accent FRAME (spec §4.2), not a modulate that yellows text.
func update_highlight(proj: Dictionary) -> void:
	_clear_highlights()
	var tp: int = int(proj.get("turn_player", -1))
	var players: Array = proj.get("players", [])
	if tp < 0 or tp >= players.size(): return
	var pos: int = int(players[tp].get("position", -1))
	if pos < 0 or pos >= _tile_nodes.size(): return
	_tile_nodes[pos].set_active(true)

func _clear_highlights() -> void:
	for tv in _tile_nodes:
		tv.set_active(false)

## Mark a tile as inspector-selected (dashed accent frame). Pass -1 to clear.
func set_selected_tile(idx: int) -> void:
	for i in _tile_nodes.size():
		_tile_nodes[i].set_selected(i == idx)

## Mark a set of tiles as valid management targets (soft fill). Pass [] to clear.
func set_target_tiles(indices: Array) -> void:
	for i in _tile_nodes.size():
		_tile_nodes[i].set_target(indices.has(i))

## Sync all player tokens. Groups pieces by tile so co-located players fan out
## along an arc instead of stacking. Creates on first sight, moves on change.
func refresh_tokens(players: Array) -> void:
	# group pids by their current tile
	var by_tile := {}
	for p in players:
		var pid: int = int(p.get("index", 0))
		var idx: int = int(p.get("position", 0))
		if not by_tile.has(idx):
			by_tile[idx] = []
		by_tile[idx].append(pid)

	var tp: int = int(_last_turn_player)
	for p in players:
		var pid: int = int(p.get("index", 0))
		var idx: int = int(p.get("position", 0))
		var group: Array = by_tile.get(idx, [pid])
		var fan_index: int = group.find(pid)
		if fan_index < 0:
			fan_index = 0
		var fan_count: int = group.size()
		var in_jail: bool = bool(p.get("in_jail", false))
		var active: bool = (pid == tp)
		if _tokens.has(pid) and is_instance_valid(_tokens[pid]):
			var tok: TokenPanel = _tokens[pid]
			tok.move_to(idx, fan_index, fan_count, in_jail, true)
			tok.set_active(active)
		else:
			var tok: TokenPanel = TokenPanel.new()
			tok.setup(_token_id(pid), _player_color(pid), str(p.get("name", "")),
				_tile_count, _cell, idx, pid)
			tok.set_active(active)
			tok.set_compact(_cell < 44)
			# P6: a freshly-created token must be fanned out with the correct
			# fan_index/fan_count, not stacked at the tile center (setup() only
			# knows fan_index=0, fan_count=1).
			tok.move_to(idx, fan_index, fan_count, in_jail, false)
			add_child(tok)
			_tokens[pid] = tok

var _last_turn_player := -1

## Remember the active player so refresh_tokens can bob the right piece.
func set_turn_player(tp: int) -> void:
	_last_turn_player = tp

## Resolve a player's token id from the seat list (assigned from PlayerIdentity),
## falling back to PlayerIdentity.token_of(pid).
func _token_id(pid: int) -> String:
	for s in _seats:
		if int(s.pid) == pid and str(s.token_id) != "":
			return str(s.token_id)
	return PI.token_of(pid)

## Resolve a player's color from the seat list, falling back to PlayerIdentity.
func _player_color(pid: int) -> Color:
	for s in _seats:
		if int(s.pid) == pid:
			return s.color
	return PI.color_of(pid)

func _on_tile_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(i)
	elif ev is InputEventMouseMotion:
		# P4 §7: hovering a tile opens the inspector (used by observer layout;
		# game_view decides whether to act on it)
		tile_hovered.emit(i)
