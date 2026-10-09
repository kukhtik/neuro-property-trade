class_name PlayersPanel
extends PanelContainer
## Left panel listing every player's current state (spec §4.4): a token
## avatar in a PlayerIdentity halo, the name in the player's color, money,
## position BY TILE NAME (not "@11"), houses / mortgaged / get-out-of-jail
## card. Active turn gets an accent frame + ▶; jail shows a ⚖ badge with the
## number of tries; away is grayed with "авто-пас"; bankrupt is struck through
## and dimmed. Reads the spectator projection + the seat list. Shape-only.

const UiTheme := preload("res://ui/theme.gd")
const SkinPaint := preload("res://visual/skin_paint.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")
const PI := preload("res://core/player_identity.gd")
const I18n := preload("res://i18n/i18n.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## P4 observer: emitted when a player row is clicked (spectator follow).
signal player_clicked(pid: int)

var _rows: Array = []   # per pid: {name, money, pos, tiles, badges}
var _skin: SkinManager

func _init() -> void:
	_skin = SkinManager.new()
	_skin.load_skin()
	custom_minimum_size.x = 235
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 10)
	add_child(outer)
	_v = UiTheme.vbox(8)
	outer.add_child(_v)

	_head = UiTheme.label(I18n.t("ui.players"), 14, UiTheme.COL().accent)
	_v.add_child(_head)
	_list = UiTheme.vbox(6)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_v.add_child(_list)

	# The mockup pins a STATISTICS BLOCK to the bottom of this column (`#stat`): a three-column
	# grid of small tiles, each with a 9px label and a 15px value in the mono face, plus a bar
	# showing how much of the board is owned. We had nothing there, so the column just stopped
	# wherever the player list ended.
	_stat = HBoxContainer.new()
	_stat.name = "Stat"
	_stat.add_theme_constant_override("separation", 6)
	_v.add_child(_stat)
	for key in ["houses", "hotels", "mortgaged"]:
		_stat.add_child(_stat_tile(key))

	# the ownership bar: a gradient from accent to accent2, width = share of the board
	_own_bar = ProgressBar.new()
	_own_bar.name = "Ownership"
	_own_bar.show_percentage = false
	_own_bar.custom_minimum_size.y = 6
	_own_bar.max_value = 100.0
	_own_bar.add_theme_stylebox_override("background",
		UiTheme.box(UiTheme.COL().get("surface3", UiTheme.COL().panel), Color.TRANSPARENT, 0, 0))
	_own_bar.add_theme_stylebox_override("fill", _gradient_box())
	_v.add_child(_own_bar)


## One statistics tile: a label above a value, as `#stat div` in the mockup.
func _stat_tile(key: String) -> Control:
	var box := PanelContainer.new()
	box.name = "Stat_" + key
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	box.add_child(m)
	var v := UiTheme.vbox(2)
	m.add_child(v)
	var cap := UiTheme.label(I18n.t("stat." + key), 9, UiTheme.COL().text_dim)
	cap.name = "Caption"
	v.add_child(cap)
	var val := UiTheme.label("—", 15, UiTheme.COL().text)
	val.name = "Value"
	v.add_child(val)
	_stat_values[key] = val
	return box


## The accent-to-accent2 gradient the mockup uses for the ownership bar.
func _gradient_box() -> StyleBoxFlat:
	var sb := UiTheme.box(UiTheme.COL().accent, Color.TRANSPARENT, 0, 0)
	sb.bg_color = UiTheme.COL().accent
	return sb

var _v: VBoxContainer
var _list: VBoxContainer
var _stat: HBoxContainer
var _own_bar: ProgressBar
var _stat_values := {}      # key -> the Label that shows its value
var _rendered_round := 0    # last turn count seen, for the round tile
var _head: Label             # the panel's own title (hidden while railed)
var _rail                    # RailPanel wrapper, for the title text


## Attach the rail wrapper. The panel's own title is hidden while collapsed so
## the rail's vertical title is the only one (spec §5.2).
func set_rail(rail) -> void:
	_rail = rail
	if rail != null:
		rail.set_title(I18n.t("ui.players"))
		rail.toggled.connect(func(collapsed: bool) -> void:
			if _head != null:
				_head.visible = not collapsed)

## Cold state (pre-game): show a placeholder list (no engine yet).
func sync_cold() -> void:
	for c in _list.get_children():
		_list.remove_child(c); c.queue_free()
	_rows.clear()
	var ph := UiTheme.label(I18n.t("plr.cold"), 13, UiTheme.COL().text_dim)
	_list.add_child(ph)

func sync(proj: Dictionary, seats: Array) -> void:
	_last_proj = proj
	_last_seats = seats
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
	_sync_stat(proj, players)


## Update the statistics block. Everything here comes from the projection, so the panel
## shows facts the host sent rather than anything it guessed.
func _sync_stat(proj: Dictionary, players: Array) -> void:
	if _stat_values.is_empty():
		return
	# COUNT WHAT THE MOCKUP COUNTS. Its `#stat` is built from `V.hs` and `V.mort`:
	#   houses   = every house below hotel level, summed over the board
	#   hotels   = tiles holding a hotel (house count 5)
	#   mortgaged= tiles currently mortgaged
	# The values were round / parking pot / owned-tiles — three different numbers, none of them
	# in the design — while the bar underneath already measured ownership correctly.
	var houses := 0
	var hotels := 0
	var mortgaged := 0
	var owned := 0
	var total := 0
	for t in proj.get("board", []):
		total += 1
		var h: int = int(t.get("houses", 0))
		if h >= 5:
			hotels += 1
		else:
			houses += h
		if bool(t.get("mortgaged", false)):
			mortgaged += 1
		if int(t.get("owner", -1)) >= 0:
			owned += 1
	_set_stat("houses", str(houses) if total > 0 else "—")
	_set_stat("hotels", str(hotels) if total > 0 else "—")
	_set_stat("mortgaged", str(mortgaged) if total > 0 else "—")
	if _own_bar != null:
		_own_bar.value = (100.0 * float(owned) / float(total)) if total > 0 else 0.0


## Money as the player reads it. MoneyFmt owns the format; this only builds one.
func _money():
	return MoneyFmt.new()


func _set_stat(key: String, text: String) -> void:
	if _stat_values.has(key) and _stat_values[key] != null:
		(_stat_values[key] as Label).text = text

## Observer follow: which pid is currently highlighted (visual feedback on rows).
var _follow_pid := -1

func set_follow(pid: int) -> void:
	_follow_pid = pid
	# cheap re-sync of the highlight only: re-run the last sync body via refresh
	if _last_proj != null:
		sync(_last_proj, _last_seats)

var _last_proj = null
var _last_seats: Array = []

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

	# --- the card, rebuilt to the mockup's own numbers -----------------------------
	# `.pc` in the mockup is: background s2, a 1px line border, a 4px border-left in the
	# PLAYER'S colour, gap 10, padding 10, and a 40px avatar column. Active state swaps the
	# background to s3 and adds an accent ring plus a glow. Ours was a 22px avatar in an 8px
	# pad with no player colour anywhere — which is most of why the panel read as a list of
	# grey boxes rather than a set of players.
	var card := Chamfer.new()
	card.name = "Card"
	card.set_skin(_skin)
	card.fill_token = "surface.2"
	card.fill_shade = _skin.proportion("card_shade", 0.16)
	card.border_token = "line"
	card.cut = "none"
	card.border_bonus = 0
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var out := MarginContainer.new()
	out.name = "PlayerRow"
	out.add_theme_constant_override("margin_left", 0)
	out.add_theme_constant_override("margin_right", 0)
	out.add_theme_constant_override("margin_top", 0)
	out.add_theme_constant_override("margin_bottom", 0)
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# the 4px stripe in the player's colour: a plain ColorRect, exactly as the mockup's
	# `border-left:4px solid var(--c)`
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.color = col
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(edge, 10)
	for edge in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	m.add_child(body)
	out.add_child(m)

	if bankrupt:
		var dim := Color.WHITE
		dim.a = _skin.proportion("bankrupt_dim_alpha", 0.5)
		out.modulate = dim
	# P4 observer: a player row is clickable (follow them). Clicking an already
	# followed player unfollows. Signal is always connected; consumers ignore it.
	out.mouse_filter = Control.MOUSE_FILTER_STOP
	out.connect("gui_input", Callable(self, "_on_row_input").bind(pid))

	# the avatar column the mockup sizes at 40px
	var avatar := _avatar(token_id, col, 40, name)
	body.add_child(avatar)

	var v := UiTheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_theme_constant_override("alignment", BoxContainer.ALIGNMENT_BEGIN)
	var nm := UiTheme.label(name, 14, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bankrupt:
		nm.add_theme_color_override("font_color", UiTheme.COL().text_dim)
	top.add_child(nm)
	var money := UiTheme.label("$%d" % int(p.get("money", 0)), 14, UiTheme.COL().gold)
	top.add_child(money)
	v.add_child(top)

	# row 2: position by tile name + tile count — the mockup's `.r2`, at 11px and muted
	var pos_name: String = str(tile_names.get(int(p.get("position", 0)), "?"))
	var info := UiTheme.label(I18n.t("plr.pos_tiles", [pos_name, int(p.get("tiles", []).size())]),
		11, UiTheme.COL().text_dim)
	v.add_child(info)

	# row 3: houses / mortgaged / jail card / badges
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 8)
	var h: int = int(p.get("houses", 0))
	if h > 0:
		badges.add_child(UiTheme.label("🏠 %d" % h, 12, UiTheme.COL().success))
	var mg: int = int(p.get("mortgaged", 0))
	if mg > 0:
		badges.add_child(UiTheme.label("💼 %d" % mg, 12, UiTheme.COL().text_dim))
	if bool(p.get("in_jail", false)):
		badges.add_child(UiTheme.label("⚖ %d" % int(p.get("jail_turns", 0)), 12, UiTheme.COL().jail))
	if away:
		badges.add_child(UiTheme.label(I18n.t("plr.auto_pass"), 12, UiTheme.COL().text_dim))
	if bankrupt:
		badges.add_child(UiTheme.label(I18n.t("plr.bankrupt"), 12, UiTheme.COL().danger))
	if badges.get_child_count() > 0:
		v.add_child(badges)

	# active marker ▶
	if active:
		var act := UiTheme.label(I18n.t("plr.active"), 12, UiTheme.COL().accent)
		v.add_child(act)

	# `.pc.on` — the active player gets an accent ring and a halo around the card
	if active:
		card.border_token = "accent"
		card.border_bonus = 1
		card.add_theme_stylebox_override("panel", SkinPaint.glow_box(UiTheme.COL().accent, 1, 0))

	# compose: stripe | card
	var wrap := HBoxContainer.new()
	wrap.name = "Row"
	wrap.add_theme_constant_override("separation", 0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(stripe)
	card.add_child(out)
	wrap.add_child(card)

	# tooltip: full summary
	var tooltip := I18n.t("plr.tooltip", [
		name, _driver_label(seat), int(p.get("money", 0)), pos_name,
		int(p.get("tiles", []).size()), h, mg])
	wrap.tooltip_text = tooltip
	return wrap

func _driver_label(seat) -> String:
	if seat == null:
		return "?"
	return str(seat.driver_label) if str(seat.driver_label) != "" else str(seat.input_driver)

## P4 observer: left-click on a player row toggles follow for that pid.
func _on_row_input(ev: InputEvent, pid: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		player_clicked.emit(pid)

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
	var path: String = _skin.token_path(token_id)
	if ResourceLoader.exists(path):
		tex = load(path)
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
