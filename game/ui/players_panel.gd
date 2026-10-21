extends PanelContainer
## The left dock (`#seats`): the player list, the stats strip and the ownership bar.
## v3 rebuild from the prototype markup; reads the spectator projection + seat list.
##
## 21.10: THE CARDS LIVE IN THE RING. The panno's players zone hosts this panel
## (`turn_panno.players_slot`), so the four seats are laid out as a WRAPPING ROW of cards -
## concept A's ".players 4 колонки карточками" - and `set_embedded(true)` drops the panel's
## own title row because the zone already carries the caption. The same panel is also what
## `drawer-seats` shows, where the row wraps down to one card per line.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

## The narrowest a seat card may be. In the ring's upper belt (1171px wide at 1600x1200) four
## cards sit side by side; in a 320px drawer the flow wraps to one per line. Without a floor the
## cards shrink to their text and the band reads as four strips.
const CARD_MIN_W := 210.0

var _title: Label
var _head: HBoxContainer
var _count: Label
var _list: HFlowContainer
var _stats: HBoxContainer
var _own_track: HBoxContainer
var _own_legend: HBoxContainer
var _skin: SkinManager
var _embedded := false
## last sync() state - a locale switch re-renders the cards from it (SG-08)
var _last_proj: Dictionary = {}
var _last_seats: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 12)
	add_child(m)
	var col := UiTheme.vbox(8)
	m.add_child(col)

	_head = UiTheme.hbox(8)
	_title = UiTheme.label(I18n.t("ui.players"), 12, UiTheme.COL().text_dim)
	_head.add_child(_title)
	_count = UiTheme.label("", 10, UiTheme.COL().text_dim)
	_head.add_child(_count)
	col.add_child(_head)

	# HFlowContainer, not VBox: the four seats are a ROW when the host is the ring's wide upper
	# belt and a COLUMN when it is the 320px drawer - the flow container is the one widget that
	# answers both without a second layout mode to keep in sync.
	_list = HFlowContainer.new()
	_list.name = "seat-cards"
	_list.add_theme_constant_override("h_separation", 6)
	_list.add_theme_constant_override("v_separation", 4)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list)
	_stats = UiTheme.hbox(4)
	col.add_child(_stats)

	var own := UiTheme.vbox(4)
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().bg, UiTheme.COL().border, 1, 0))
	track.custom_minimum_size.y = 8
	_own_track = UiTheme.hbox(0)
	_own_track.name = "ownbar"
	track.add_child(_own_track)
	own.add_child(track)
	_own_legend = UiTheme.hbox(0)
	own.add_child(_own_legend)
	col.add_child(own)


## EMBEDDED IN THE RING. The panno's players zone carries the caption "Игроки" already, so the
## panel drops its OWN title row there: two headings over one row of cards is a duplicate, not a
## hierarchy. Everything else stays - the cards, the round/pot strip, the ownership bar - because
## those are facts the ring does not otherwise show.
func set_embedded(on: bool) -> void:
	_embedded = on
	if _head != null:
		_head.visible = not on


## Update from the projection. `seats` carries pid/name/colour/input_driver.
func sync(proj: Dictionary, seats: Array) -> void:
	_last_proj = proj
	_last_seats = seats
	var players: Array = proj.get("players", [])
	_count.text = str(players.size())
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	# tile names for "pos" lines
	var names := {}
	for t in (proj.get("board", []) as Array):
		names[int(t.get("index", -1))] = str(t.get("name", ""))
	# rebuild the cards (small n — plain rebuilds are fine and always correct)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for p in players:
		_list.add_child(_card(p, seats, turn, names))
	_refresh_stats(proj, players)
	_refresh_ownbar(players, seats)


func _card(p: Dictionary, seats: Array, turn: int, names: Dictionary) -> Control:
	var pid: int = int(p.get("index", 0))
	var name := str(p.get("name", "P%d" % pid))
	var col: Color = UiTheme.COL().accent
	var driver := ""
	for s in seats:
		if int(s.pid) == pid:
			col = s.color
			driver = str(s.input_driver)
	var card := PanelContainer.new()
	var active: bool = pid == turn
	# R-2 / D5: the cards DISTRIBUTE over the host's room instead of stacking at the top and
	# leaving ~555px of dead space under them; a viewer read that as "the panel is broken".
	# In the ring they share the upper belt WIDTH instead (four across), which is why the floor
	# is a width and the flow container wraps a narrow host back into a column.
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = CARD_MIN_W
	# The ring's players zone is a DOOR (a click opens `drawer-seats`). A card that swallowed the
	# press would leave only the band's 20px caption clickable, so the press is passed up to the
	# panno's zone column instead of being eaten here.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if active else UiTheme.COL().panel,
			col if active else UiTheme.COL().border, 2 if active else 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 8)
	card.add_child(m)
	var col_box := UiTheme.vbox(2)
	# a card taller than its four lines centres them instead of hugging the top edge (the belt is
	# 326px at 1600x1200 - a top-aligned card would be half empty inside its own border)
	col_box.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(col_box)
	var row1 := UiTheme.hbox(8)
	var av := Panel.new()
	av.custom_minimum_size = Vector2(30, 30)
	av.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), col, 2, 15))
	row1.add_child(av)
	var nm := UiTheme.label(name, 13, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	row1.add_child(nm)
	var money := UiTheme.label(MoneyFmt.make("$").amount(int(p.get("money", 0))), 13, UiTheme.COL().money)
	money.clip_text = true
	row1.add_child(money)
	col_box.add_child(row1)
	# position line
	var pos: int = int(p.get("position", 0))
	var pos_lbl := UiTheme.label("%s · %s" % [str(names.get(pos, "?")), driver], 11, UiTheme.COL().text_dim)
	pos_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pos_lbl.clip_text = true
	col_box.add_child(pos_lbl)
	# chips: jail / bankrupt / tiles owned
	var chips := UiTheme.hbox(4)
	if bool(p.get("in_jail", false)):
		chips.add_child(_chip(I18n.t("plr.jail"), UiTheme.COL().danger))
	if bool(p.get("bankrupt", false)):
		chips.add_child(_chip(I18n.t("plr.bankrupt"), UiTheme.COL().danger))
	var tiles: Array = p.get("tiles", [])
	if tiles.size() > 0:
		chips.add_child(_chip(I18n.t("plr.owned", [tiles.size()]), col))
	col_box.add_child(chips)
	return card


func _chip(text: String, col: Color) -> Label:
	var l := UiTheme.label(text, 9, col)
	l.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel, col, 1, 2))
	return l


func _refresh_stats(proj: Dictionary, players: Array) -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var cells := [
		[str(proj.get("round", 1)), I18n.t("stat.round")],
		[str(players.size()), I18n.t("ui.players")],
		# `parking_pot`, not `pot`: the projection has one name for the bank (HG-10)
		["$%d" % int(proj.get("parking_pot", 0)), I18n.t("top.pot")],
	]
	for cell in cells:
		var p := PanelContainer.new()
		# the cells are VALUES: they sit at their content width, and the row's single stretch
		# slot goes to the trailing spacer (P-4: exactly one grower per flex row)
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
		var v := UiTheme.vbox(0)
		var val := UiTheme.label(cell[0], 14, UiTheme.COL().text)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.clip_text = true
		var key := UiTheme.label(cell[1], 9, UiTheme.COL().text_dim)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.clip_text = true
		v.add_child(val)
		v.add_child(key)
		p.add_child(v)
		_stats.add_child(p)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_child(sp)


func _refresh_ownbar(players: Array, seats: Array) -> void:
	for c in _own_track.get_children():
		_own_track.remove_child(c)
		c.queue_free()
	for c in _own_legend.get_children():
		_own_legend.remove_child(c)
		c.queue_free()
	# total owned across players -> proportional segments
	var total := 0
	for p in players:
		total += (p.get("tiles", []) as Array).size()
	for p in players:
		var pid: int = int(p.get("index", 0))
		var col: Color = UiTheme.COL().accent
		for s in seats:
			if int(s.pid) == pid:
				col = s.color
		var seg := ColorRect.new()
		var n: int = (p.get("tiles", []) as Array).size()
		seg.color = col
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(0.0001, float(n) / maxf(1.0, float(total)))
		_own_track.add_child(seg)
		var l := UiTheme.label(str(p.get("name", "")), 9, UiTheme.COL().text_dim)
		_own_legend.add_child(l)


func retranslate() -> void:
	_title.text = I18n.t("ui.players")
	# the cards, stats and the ownership bar are state-driven: re-render from the last state
	# so a locale switch mid-match relabels them without waiting for the next event
	if not _last_proj.is_empty():
		sync(_last_proj, _last_seats)
