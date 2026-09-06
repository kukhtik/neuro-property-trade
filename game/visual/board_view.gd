class_name BoardView
extends Control
## Code-built board from a projection + TileLayout/BoardTheme. Repaints on
## refresh_state(proj). Read-only downstream consumer of the engine projection.

signal tile_clicked(index: int)

const TL := preload("res://visual/tile_layout.gd")
const BT := preload("res://visual/theme.gd")
const TokenPanel := preload("res://visual/token_panel.gd")

var _tile_nodes: Array[PanelContainer] = []
var _name_labels: Array[Label] = []
var _house_labels: Array[Label] = []
var _tokens := {}              # pid -> TokenPanel
var _cell := 64

## Build the board control. tile_count + cell size.
func build(tile_count: int, cell: int = 64) -> Control:
	_cell = cell
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
		var panel = PanelContainer.new()
		var b := StyleBoxFlat.new()
		b.bg_color = Color("c8ccd4")
		b.border_color = Color("000000")
		b.set_border_width_all(1)
		b.corner_radius_top_left = 5
		b.corner_radius_top_right = 5
		b.corner_radius_bottom_left = 5
		b.corner_radius_bottom_right = 5
		panel.add_theme_stylebox_override("panel", b)
		panel.position = TL.pixel_pos(i, tile_count, cell) - Vector2(cell / 2.0, cell / 2.0)
		panel.size = Vector2(cell, cell)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.z_index = 1
		panel.gui_input.connect(_on_tile_input.bind(i))

		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(v)

		var nm := Label.new()
		nm.text = str(i)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.add_theme_font_size_override("font_size", 10)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)

		var hs := Label.new()
		hs.text = ""
		hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hs.add_theme_font_size_override("font_size", 9)
		hs.add_theme_color_override("font_color", Color.WHITE)
		hs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(hs)

		_name_labels.append(nm)
		_house_labels.append(hs)
		_tile_nodes.append(panel)
		add_child(panel)
	return self

## Repaint from a spectator projection dictionary (for_spectator output).
func refresh_state(proj: Dictionary) -> void:
	var tiles: Array = proj.get("board", [])
	for entry in tiles:
		var idx: int = int(entry.get("index", 0))
		if idx < 0 or idx >= _tile_nodes.size(): continue
		var b: StyleBoxFlat = _tile_nodes[idx].get_theme_stylebox("panel")
		if b == null: continue
		# ownership: tint by owner color, else tile-type/group color
		var ow: int = int(entry.get("owner", -1))
		if ow >= 0:
			b.bg_color = _owner_tint(ow, BT.tile_color(entry))
		else:
			b.bg_color = BT.tile_color(entry)
		_name_labels[idx].text = str(entry.get("name", ""))
		var h: int = int(entry.get("houses", 0))
		var lbl := ""
		if h > 0 and h <= 4: lbl = "H".repeat(h)
		elif h >= 5: lbl = "HOTEL"
		_house_labels[idx].text = lbl
	update_highlight(proj)

## Highlight the tile the given player index is on (spectacle active-player).
func update_highlight(proj: Dictionary) -> void:
	_clear_highlights()
	var tp: int = int(proj.get("turn_player", -1))
	var players: Array = proj.get("players", [])
	if tp < 0 or tp >= players.size(): return
	var pos: int = int(players[tp].get("position", -1))
	if pos < 0 or pos >= _tile_nodes.size(): return
	var b: StyleBoxFlat = _tile_nodes[pos].get_theme_stylebox("panel")
	if b == null: return
	b.set_border_width_all(3)
	b.border_color = Color("ffe066")

func _clear_highlights() -> void:
	for panel in _tile_nodes:
		var b: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if b == null: continue
		b.set_border_width_all(1)
		b.border_color = Color("000000")

## Sync a single player token. Creates on first sight, moves on change.
func refresh_tokens(players: Array) -> void:
	for p in players:
		var pid: int = int(p.get("index", 0))
		var idx: int = int(p.get("position", 0))
		if _tokens.has(pid) and is_instance_valid(_tokens[pid]):
			_tokens[pid].move_to(idx, true)
		else:
			var tp: TokenPanel = TokenPanel.new()
			tp.setup(_player_color(pid), str(p.get("name", "")), 40, _cell, idx)
			tp.z_index = 5
			add_child(tp)
			_tokens[pid] = tp

func _player_color(pid: int) -> Color:
	var colors := [Color("e74c3c"), Color("3498db"), Color("2ecc71"),
		Color("f1c40f"), Color("9b59b6"), Color("e67e22")]
	return colors[pid % colors.size()]

func _owner_tint(owner: int, base: Color) -> Color:
	# blend the owner color over the tile base so ownership reads at a glance
	var ow := _player_color(owner)
	return Color(
		base.r * 0.45 + ow.r * 0.55,
		base.g * 0.45 + ow.g * 0.55,
		base.b * 0.45 + ow.b * 0.55)

func _on_tile_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(i)
