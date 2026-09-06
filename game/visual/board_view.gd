class_name BoardView
extends Control
## Code-built board from a projection + TileLayout/BoardTheme. Repaints on
## refresh_state(proj). Read-only downstream consumer of the engine projection.
## Each tile is a TileView widget (group band, name, price, corner icon, owner
## marker, houses as figures). Tokens are SVG pieces with a PlayerIdentity halo
## (P1), fanned out when several players share a tile, active player bobs.
##
## P1: colors/tokens come from PlayerIdentity (single source) — the owner
## marker, the piece halo and the players-panel row can never disagree.

signal tile_clicked(index: int)

const TL := preload("res://visual/tile_layout.gd")
const BT := preload("res://visual/theme.gd")
const PI := preload("res://core/player_identity.gd")
const TileView := preload("res://visual/tile_view.gd")
const TokenPanel := preload("res://visual/token_panel.gd")

var _tile_nodes: Array[TileView] = []
var _tokens := {}              # pid -> TokenPanel
var _cell := 64
var _tile_count := 40
var _seats: Array = []         # of Seat (for token_id + color resolution)

## Build the board control. tile_count + cell size.
func build(tile_count: int, cell: int = 64) -> Control:
	_cell = cell
	_tile_count = tile_count
	var grid := TL.grid_cells(tile_count)
	var size := grid * cell
	custom_minimum_size = Vector2(size, size)
	set_size(Vector2(size, size))

	var bkg = ColorRect.new()
	bkg.color = Color("22303c")
	bkg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bkg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bkg)

	for i in tile_count:
		var tv: TileView = TileView.new()
		tv.build(i, tile_count, cell)
		tv.position = TL.pixel_pos(i, tile_count, cell) - Vector2(cell / 2.0, cell / 2.0)
		tv.z_index = 1
		tv.gui_input.connect(_on_tile_input.bind(i))
		_tile_nodes.append(tv)
		add_child(tv)
	return self

## Provide the seat list so tokens resolve their token_id + color from the
## seat (which was assigned from PlayerIdentity). Call before refresh_tokens.
func set_seats(seats: Array) -> void:
	_seats = seats

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
func update_highlight(proj: Dictionary) -> void:
	_clear_highlights()
	var tp: int = int(proj.get("turn_player", -1))
	var players: Array = proj.get("players", [])
	if tp < 0 or tp >= players.size(): return
	var pos: int = int(players[tp].get("position", -1))
	if pos < 0 or pos >= _tile_nodes.size(): return
	# draw a bright border around the active tile via a highlight overlay
	_tile_nodes[pos].modulate = Color(1.25, 1.25, 1.0)

func _clear_highlights() -> void:
	for tv in _tile_nodes:
		tv.modulate = Color.WHITE

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
