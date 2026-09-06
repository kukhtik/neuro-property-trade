class_name PlayersPanel
extends PanelContainer
## Left panel listing every player's current state (spec §4.4): a token
## avatar in a PlayerIdentity halo, the name in the player's color, money,
## position BY TILE NAME (not "@11"), houses / mortgaged / get-out-of-jail
## card. Active turn gets an accent frame + ▶; jail shows a ⚖ badge with the
## number of tries; away is grayed with "авто-пас"; bankrupt is struck through
## and dimmed. Reads the spectator projection + the seat list. Shape-only.

const UiTheme := preload("res://ui/theme.gd")
const PI := preload("res://core/player_identity.gd")

var _rows: Array = []   # per pid: {name, money, pos, tiles, badges}

func _init() -> void:
	custom_minimum_size.x = 235
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel, UiTheme.COL.border, 1, 0))
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 10)
	add_child(outer)
	_v = UiTheme.vbox(8)
	outer.add_child(_v)

	var head := UiTheme.label("ИГРОКИ", 14, UiTheme.COL.accent)
	_v.add_child(head)
	_list = UiTheme.vbox(6)
	_v.add_child(_list)

var _v: VBoxContainer
var _list: VBoxContainer

## Cold state (pre-game): show a placeholder list (no engine yet).
func sync_cold() -> void:
	for c in _list.get_children():
		_list.remove_child(c); c.queue_free()
	_rows.clear()
	var ph := UiTheme.label("Партия ещё не начата", 13, UiTheme.COL.text_dim)
	_list.add_child(ph)

func sync(proj: Dictionary, seats: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c); c.queue_free()
	_rows.clear()
	var players: Array = proj.get("players", [])
	var tp: int = int(proj.get("turn_player", -1))
	var tile_names := _tile_name_map(proj)
	for p in players:
		var pid: int = int(p.get("index", 0))
		var row := _build_row(p, seats, pid, pid == tp, tile_names)
		_list.add_child(row)

## Map tile index -> short display name (from the projection board).
func _tile_name_map(proj: Dictionary) -> Dictionary:
	var m := {}
	for t in proj.get("board", []):
		m[int(t.get("index", -1))] = str(t.get("name", ""))
	return m

func _build_row(p: Dictionary, seats: Array, pid: int, active: bool,
		tile_names: Dictionary) -> Control:
	var seat = null
	for s in seats:
		if int(s.pid) == pid:
			seat = s
	var name: String = str(p.get("name", "P%d" % pid))
	var col: Color = seat.color if seat != null else PI.color_of(pid)
	var token_id: String = seat.token_id if seat != null else PI.token_of(pid)
	var bankrupt: bool = bool(p.get("bankrupt", false))
	var away: bool = false
	for s in seats:
		if int(s.pid) == pid and bool(s.away):
			away = true

	var out := PanelContainer.new()
	var bord: Color = UiTheme.COL.border_accent if active else UiTheme.COL.border
	var w := 2 if active else 1
	out.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel_dark, bord, w, 6))
	if bankrupt:
		out.modulate = Color(1, 1, 1, 0.5)

	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 8)
	out.add_child(m)
	var v := UiTheme.vbox(2)
	m.add_child(v)

	# row 1: token avatar (halo) + name + money
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var avatar := _avatar(token_id, col, 22, name)
	top.add_child(avatar)
	var nm := UiTheme.label(name, 14, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bankrupt:
		nm.add_theme_color_override("font_color", UiTheme.COL.text_dim)
	top.add_child(nm)
	var money := UiTheme.label("$%d" % int(p.get("money", 0)), 14, UiTheme.COL.gold)
	top.add_child(money)
	v.add_child(top)

	# row 2: position by tile name + tile count
	var pos_name: String = str(tile_names.get(int(p.get("position", 0)), "?"))
	var info := UiTheme.label("@ %s · %d тайл." % [pos_name, int(p.get("tiles", []).size())],
		12, UiTheme.COL.text_dim)
	v.add_child(info)

	# row 3: houses / mortgaged / jail card / badges
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 8)
	var h: int = int(p.get("houses", 0))
	if h > 0:
		badges.add_child(UiTheme.label("🏠 %d" % h, 12, UiTheme.COL.success))
	var mg: int = int(p.get("mortgaged", 0))
	if mg > 0:
		badges.add_child(UiTheme.label("💼 %d" % mg, 12, UiTheme.COL.text_dim))
	if bool(p.get("in_jail", false)):
		badges.add_child(UiTheme.label("⚖ %d" % int(p.get("jail_turns", 0)), 12, UiTheme.COL.jail))
	if away:
		badges.add_child(UiTheme.label("авто-пас", 12, UiTheme.COL.text_dim))
	if bankrupt:
		badges.add_child(UiTheme.label("БАНКРОТ", 12, UiTheme.COL.danger))
	if badges.get_child_count() > 0:
		v.add_child(badges)

	# active marker ▶
	if active:
		var act := UiTheme.label("▶ ход", 12, UiTheme.COL.accent)
		v.add_child(act)

	# tooltip: full summary
	var tooltip := "Игрок: %s\nДрайвер: %s\nДеньги: $%d\nПозиция: %s\nТайлы: %d\nДома: %d · Залоги: %d" % [
		name, _driver_label(seat), int(p.get("money", 0)), pos_name,
		int(p.get("tiles", []).size()), h, mg]
	out.tooltip_text = tooltip
	return out

func _driver_label(seat) -> String:
	if seat == null:
		return "?"
	return str(seat.driver_label) if str(seat.driver_label) != "" else str(seat.input_driver)

## A small token avatar: a colored halo circle with the token sprite on top.
func _avatar(token_id: String, col: Color, size: int, player_name: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.size = Vector2(size, size)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# halo
	var halo := ColorRect.new()
	halo.color = col
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(halo)
	# sprite
	var tex: Texture2D = null
	if ResourceLoader.exists(PI.token_path(token_id)):
		tex = load(PI.token_path(token_id))
	if tex != null:
		var spr := TextureRect.new()
		spr.texture = tex
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		spr.set_anchors_preset(Control.PRESET_FULL_RECT)
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(spr)
	else:
		var ini := UiTheme.label(_initial_of(player_name), 12, Color.WHITE)
		ini.set_anchors_preset(Control.PRESET_FULL_RECT)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wrap.add_child(ini)
	return wrap

func _initial_of(name: String) -> String:
	var n := name.strip_edges()
	if n.length() > 0:
		return n.substr(0, 1).to_upper()
	return "P"
