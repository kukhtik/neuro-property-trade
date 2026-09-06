class_name BoardView
extends Control
## Code-built board from a projection + TileLayout/BoardTheme. Repaints on
## refresh_state(proj). Read-only downstream consumer of the engine projection.
## Each tile is a TileView widget (group band, name, price, corner icon, owner
## marker, houses as figures). Tokens are unique pieces with the player's
## initial (A4).

signal tile_clicked(index: int)

const TL := preload("res://visual/tile_layout.gd")
const BT := preload("res://visual/theme.gd")
const TileView := preload("res://visual/tile_view.gd")
const TokenPanel := preload("res://visual/token_panel.gd")

var _tile_nodes: Array[TileView] = []
var _tokens := {}              # pid -> TokenPanel
var _cell := 64
var _tile_count := 40

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

## Repaint from a spectator projection dictionary (for_spectator output).
func refresh_state(proj: Dictionary) -> void:
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

## Sync a single player token. Creates on first sight, moves on change.
func refresh_tokens(players: Array) -> void:
	for p in players:
		var pid: int = int(p.get("index", 0))
		var idx: int = int(p.get("position", 0))
		if _tokens.has(pid) and is_instance_valid(_tokens[pid]):
			_tokens[pid].move_to(idx, true)
		else:
			var tp: TokenPanel = TokenPanel.new()
			tp.setup(_player_color(pid), str(p.get("name", "")), _tile_count, _cell, idx)
			tp.z_index = 5
			add_child(tp)
			_tokens[pid] = tp

func _player_color(pid: int) -> Color:
	var colors := [Color("e74c3c"), Color("3498db"), Color("2ecc71"),
		Color("f1c40f"), Color("9b59b6"), Color("e67e22")]
	return colors[pid % colors.size()]

func _on_tile_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(i)
