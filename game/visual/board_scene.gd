extends Control
## The board (`#stage` → `#board`): the 40-tile ring, the centre (watermark / dice tray /
## banner / decision card) and the player tokens. v3 rebuild from the prototype: flat,
## cell = side/11, band-facing-centre tiles, dice that tumble IN the centre.
##
## Reads the spectator projection; emits tile clicks. It never touches the engine.

signal tile_clicked(index: int)

const TileView := preload("res://visual/tile_view.gd")
const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

var _skin: SkinManager
var _board: Array = []
var _tiles: Array = []
var _cell := 0.0
var _selected := -1
var _entries: Dictionary = {}       # index -> state dict handed to the tiles

var _wm1: Label
var _wm2: Label
var _tray: HBoxContainer
var _dice: Array = []
var _sum: Label
var _doubles: Label
var _banner: Label
var _card: PanelContainer
var _card_name: Label
var _card_price: Label
var _tokens: Dictionary = {}        # pid -> Control
var _token_pos: Dictionary = {}     # pid -> int (tile index)

var _rolling := false
var _roll_t := 0.0
var _roll_swap := 0.0
var _roll_to := Vector2i(1, 1)
var _watermark := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_skin = SkinManager.new()
	_skin.load_skin()
	_load_board()
	resized.connect(_layout)
	_build_centre()


func _load_board() -> void:
	var f := FileAccess.open("res://data/board.json", FileAccess.READ)
	if f == null:
		push_error("board_scene: cannot read res://data/board.json")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_board = parsed.get("tiles", [])
	elif parsed is Array:
		_board = parsed


func _build_centre() -> void:
	_wm1 = UiTheme.label("NEURO\nPROPERTY TRADE", 18, UiTheme.COL().text_dim)
	_wm1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wm1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_wm1)
	_wm2 = UiTheme.label(I18n.t("top.cold"), 10, UiTheme.COL().text_dim)
	_wm2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wm2.modulate = Color(1, 1, 1, 0.6)
	add_child(_wm2)

	_tray = UiTheme.hbox(12)
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_tray)
	for i in 2:
		var d := Control.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.set_meta("value", 1)
		d.draw.connect(_draw_die.bind(d))
		_tray.add_child(d)
		_dice.append(d)
	_sum = UiTheme.label("", 24, UiTheme.COL().text)
	_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sum.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	_sum.visible = false
	_tray.add_child(_sum)
	_doubles = UiTheme.label(I18n.t("die.doubles"), 11, UiTheme.COL().accent2)
	_doubles.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), UiTheme.COL().accent2, 1, 0))
	_doubles.visible = false
	_tray.add_child(_doubles)

	_banner = UiTheme.label("", 15, UiTheme.COL().text)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_card.visible = false
	add_child(_card)
	var cv := UiTheme.vbox(4)
	_card.add_child(cv)
	_card_name = UiTheme.label("", 16, UiTheme.COL().text)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_card_name)
	_card_price = UiTheme.label("", 14, UiTheme.COL().money)
	_card_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_card_price)


## Ring coordinates for board index (classic order: GO bottom-right, anti-clockwise).
static func _grid_pos(i: int) -> Vector2i:
	if i == 0:
		return Vector2i(10, 10)
	if i < 10:
		return Vector2i(10 - i, 10)
	if i == 10:
		return Vector2i(0, 10)
	if i < 20:
		return Vector2i(0, 10 - (i - 10))
	if i == 20:
		return Vector2i(0, 0)
	if i < 30:
		return Vector2i(i - 20, 0)
	if i == 30:
		return Vector2i(10, 0)
	return Vector2i(10, i - 30)


static func _ring_side(i: int) -> String:
	if i <= 10:
		return "b"
	if i <= 20:
		return "l"
	if i <= 30:
		return "t"
	return "r"


func _is_corner(i: int) -> bool:
	return i in [0, 10, 20, 30]


func _layout() -> void:
	var side_px: float = minf(size.x, size.y)
	if side_px <= 1.0:
		return
	_place_board(side_px)
	_place_centre()


func _place_board(side_px: float) -> void:
	var cell: float = side_px / 11.0
	var ox: float = (size.x - side_px) * 0.5
	var oy: float = (size.y - side_px) * 0.5
	var rebuild: bool = _tiles.is_empty() or absf(cell - _cell) > 0.5
	_cell = cell
	if rebuild:
		for t in _tiles:
			t.queue_free()
		_tiles.clear()
		for i in _board.size():
			var tv = TileView.new()
			var data: Dictionary = _board[i]
			var ring_side: String = "corner" if _is_corner(i) else _ring_side(i)
			add_child(tv)
			tv.setup(_skin, i, data, cell, ring_side)
			tv.pressed.connect(func(idx: int) -> void: tile_clicked.emit(idx))
			_tiles.append(tv)
	for i in _tiles.size():
		var g: Vector2i = _grid_pos(i)
		var tv2 = _tiles[i]
		tv2.position = Vector2(ox + g.x * cell, oy + g.y * cell)
		tv2.size = Vector2(cell, cell)
	for pid in _tokens.keys():
		var tok: Control = _tokens[pid]
		var idx: int = int(_token_pos.get(pid, 0))
		tok.position = _token_screen_pos(idx, int(pid), 4)


func _place_centre() -> void:
	var side_px: float = _cell * 11.0
	var ox: float = (size.x - side_px) * 0.5 + _cell
	var oy: float = (size.y - side_px) * 0.5 + _cell
	var cw: float = _cell * 9.0
	# watermark: two centred lines above the tray
	_wm1.position = Vector2(ox, oy + cw * 0.30)
	_wm1.size = Vector2(cw, 64)
	_wm1.add_theme_font_size_override("font_size", maxi(12, int(_cell * 0.30)))
	_wm2.position = Vector2(ox, oy + cw * 0.30 + 68.0)
	_wm2.size = Vector2(cw, 20)
	_wm2.add_theme_font_size_override("font_size", maxi(8, int(_cell * 0.14)))
	# tray at the vertical middle
	var die_px: float = maxf(18.0, roundf(_cell * 0.62))
	for d in _dice:
		d.custom_minimum_size = Vector2(die_px, die_px)
	_tray.position = Vector2(ox, oy + cw * 0.5 - die_px * 0.5)
	_tray.size = Vector2(cw, die_px)
	_sum.add_theme_font_size_override("font_size", maxi(14, int(_cell * 0.5)))
	# banner: top 4% of the centre
	_banner.position = Vector2(ox, oy + cw * 0.04)
	_banner.size = Vector2(cw, 30)
	_banner.add_theme_font_size_override("font_size", maxi(11, int(_cell * 0.26)))
	# card: centred panel
	_card.position = Vector2(ox + cw * 0.25, oy + cw * 0.62)
	_card.size = Vector2(cw * 0.5, 92)


## Watermark shows in the cold state only (proto renderCenter).
func set_watermark(v: bool) -> void:
	_watermark = v
	_wm1.visible = v
	_wm2.visible = v


func set_cold() -> void:
	set_watermark(true)
	_banner.visible = false
	_card.visible = false
	for pid in _tokens:
		(_tokens[pid] as Control).visible = false


## Paint from the spectator projection.
func sync(proj: Dictionary, seats: Array, human_pid: int) -> void:
	var entries := {}
	var by_index := {}
	for e in (proj.get("board", []) as Array):
		by_index[int(e.get("index", -1))] = e
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var turn_pos := -1
	for p in (proj.get("players", []) as Array):
		if int(p.get("index", -1)) == turn:
			turn_pos = int(p.get("position", -1))
	for i in _board.size():
		var e: Dictionary = by_index.get(i, {})
		var owner: int = int(e.get("owner", -1))
		if owner >= 0:
			var nm := str(e.get("owner_name", ""))
			var col: Color = UiTheme.COL().accent
			for s in seats:
				if int(s.pid) == owner:
					col = s.color
					if nm == "":
						nm = str(s.name)
			e["owner_color"] = col
			e["owner_name"] = nm
		e["active"] = i == turn_pos and not _watermark
		e["selected"] = i == _selected
		entries[i] = e
	_entries = entries
	for i in _tiles.size():
		_tiles[i].apply(entries.get(i, {}))
	_sync_tokens(proj, seats)
	_sync_centre(proj, seats)


func _sync_centre(proj: Dictionary, seats: Array) -> void:
	var phase: String = str(proj.get("phase", ""))
	var dice: Array = proj.get("dice", [0, 0])
	if int(dice[0]) > 0 and not _rolling:
		set_dice(int(dice[0]), int(dice[1]))
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var nm := ""
	var col: Color = UiTheme.COL().accent
	for s in seats:
		if int(s.pid) == turn:
			nm = str(s.name)
			col = s.color
	var ph_lbl: String = I18n.t("phase." + phase)
	if ph_lbl.begins_with("{phase."):
		ph_lbl = phase
	_banner.text = "%s · %s" % [nm, ph_lbl]
	_banner.add_theme_color_override("font_color", col)
	_banner.visible = nm != "" and phase != ""
	var pend: Dictionary = proj.get("pending", {})
	var is_card: bool = str(pend.get("type", "")) in ["purchase", "auction"] or phase == "AUCTION"
	_card.visible = is_card
	if is_card:
		var tile_idx: int = int(pend.get("tile", -1))
		var t: Dictionary = {}
		for e in (proj.get("board", []) as Array):
			if int(e.get("index", -1)) == tile_idx:
				t = e
		_card_name.text = str(t.get("name", ""))
		_card_price.text = "$%d" % int(t.get("cost", 0))


func _sync_tokens(proj: Dictionary, seats: Array) -> void:
	var players: Array = proj.get("players", [])
	var seen := {}
	for p in players:
		var pid: int = int(p.get("index", 0))
		seen[pid] = true
		var col: Color = UiTheme.COL().accent
		for s in seats:
			if int(s.pid) == pid:
				col = s.color
		var tok: Control = _tokens.get(pid)
		if tok == null:
			tok = Panel.new()
			tok.custom_minimum_size = Vector2(16, 16)
			tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tok.add_theme_stylebox_override("panel",
				UiTheme.box(Color(col.r, col.g, col.b, 0.35), col, 2, 8))
			add_child(tok)
			_tokens[pid] = tok
		var pos: int = int(p.get("position", 0))
		var target := _token_screen_pos(pos, pid, players.size())
		var old: int = int(_token_pos.get(pid, -1))
		if old != pos and old >= 0:
			var tw := create_tween()
			tw.tween_property(tok, "position", target, 0.19)
		else:
			tok.position = target
		_token_pos[pid] = pos
		tok.visible = not bool(p.get("bankrupt", false))
	for pid in _tokens.keys():
		if not seen.has(pid):
			(_tokens[pid] as Control).visible = false


func _token_screen_pos(idx: int, pid: int, count: int) -> Vector2:
	if _cell <= 0.0 or _tiles.is_empty():
		return Vector2.ZERO
	var i: int = clampi(idx, 0, _tiles.size() - 1)
	var base: Vector2 = (_tiles[i] as Control).position + Vector2(_cell * 0.5, _cell * 0.5)
	var fan: float = 16.0
	return base + Vector2((pid % 3 - 1) * fan, ((pid / 3) % 2 - 0.5) * fan) - Vector2(8, 8) * 0.5


## Select a tile: re-apply the state layer only.
func set_selected(idx: int) -> void:
	_selected = idx
	for i in _tiles.size():
		var e: Dictionary = _entries.get(i, {})
		e["selected"] = i == idx
		_tiles[i].apply(e)


## The roll: the TRAY tumbles and settles on the decided faces (0.85s).
func roll_tray(d1: int, d2: int) -> void:
	_roll_to = Vector2i(clampi(d1, 1, 6), clampi(d2, 1, 6))
	_rolling = true
	_roll_t = 0.0
	_roll_swap = 0.0
	_sum.visible = false
	_doubles.visible = false
	set_process(true)


func set_dice(a: int, b: int) -> void:
	for i in _dice.size():
		(_dice[i] as Control).set_meta("value", a if i == 0 else b)
		(_dice[i] as Control).queue_redraw()
	_sum.visible = a > 0
	if a > 0:
		_sum.text = str(a + b)
	_doubles.visible = a > 0 and a == b


func _process(delta: float) -> void:
	if not _rolling:
		return
	var dur := 0.85
	_roll_t += delta
	_roll_swap += delta
	if _roll_swap >= 0.085:
		_roll_swap = 0.0
		for i in _dice.size():
			(_dice[i] as Control).set_meta("value", 1 + (i * 3 + int(_roll_t * 24.0)) % 6)
			(_dice[i] as Control).queue_redraw()
	var p: float = clampf(_roll_t / dur, 0.0, 1.0)
	for i in _dice.size():
		var d: Control = _dice[i]
		d.pivot_offset = d.size * 0.5
		d.rotation = sin(p * TAU * 2.4 + float(i) * 1.7) * 0.55 * (1.0 - p)
		d.scale = Vector2(1.0, 1.0 - 0.25 * sin(p * PI))
	if _roll_t >= dur:
		_rolling = false
		set_process(false)
		for d in _dice:
			(d as Control).rotation = 0.0
			(d as Control).scale = Vector2.ONE
		set_dice(_roll_to.x, _roll_to.y)


## Play one engine event (adapter shape): roll tumbles the tray, move hops the token.
func play_event(ev: Dictionary) -> void:
	var k: String = str(ev.get("k", ""))
	if k == "roll":
		roll_tray(int(ev.get("a", 1)), int(ev.get("b", 1)))
	elif k in ["move", "teleport"]:
		var pid: int = int(ev.get("p", -1))
		var to: int = int(ev.get("ti", -1))
		if pid >= 0 and to >= 0 and _tokens.has(pid):
			var tw := create_tween()
			tw.tween_property(_tokens[pid], "position", _token_screen_pos(to, pid, 4), 0.19)


func _draw_die(holder: Control) -> void:
	var v: int = int(holder.get_meta("value", 1))
	var s: Vector2 = holder.size
	var side: float = maxf(4.0, minf(s.x, s.y))
	var base := Rect2((s - Vector2(side, side)) * 0.5, Vector2(side, side))
	holder.draw_rect(base, UiTheme.skin().color("dice_bg", Color(0.95, 0.96, 0.98)))
	var col: Color = UiTheme.skin().color("dice_ink", Color(0.09, 0.1, 0.12))
	var foot: Color = col
	foot.a = 0.2
	var fh: float = maxf(2.0, minf(4.0, side * 0.11))
	holder.draw_rect(Rect2(base.position + Vector2(0.0, base.size.y - fh), Vector2(side, fh)), foot)
	var pad: float = maxf(2.0, side * 0.12)
	var cell: float = (side - pad * 2.0) / 3.0
	for p in _pip_positions(v):
		var c := base.position + Vector2(
			pad + (float(p[0]) + 0.5) * cell,
			pad + (float(p[1]) + 0.5) * cell)
		holder.draw_circle(c, maxf(1.5, cell * 0.31), col)


static func _pip_positions(v: int) -> Array:
	match v:
		1: return [[1, 1]]
		2: return [[0, 0], [2, 2]]
		3: return [[0, 0], [1, 1], [2, 2]]
		4: return [[0, 0], [2, 0], [0, 2], [2, 2]]
		5: return [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]
		6: return [[0, 0], [2, 0], [0, 1], [2, 1], [0, 2], [2, 2]]
	return []
