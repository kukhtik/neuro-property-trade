extends PanelContainer
## The tile card docked at the bottom of the right column (`#inspector`): the selected
## tile's name / group band / price / rent / owner rows, the flags and the four
## management buttons. v3 rebuild; reads the spectator projection only.

signal action_requested(tile: int, op: String)

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const MoneyFmt := preload("res://ui/core/money.gd")

var selected := -1
var _placeholder: Label
var _body: VBoxContainer
var _name_lbl: Label
var _band: ColorRect
var _type_lbl: Label
var _rows_box: VBoxContainer
var _price_val: Label
var _rent_val: Label
## E-3: the rent row's CAPTION, so it can say "сейчас" when the live rent differs from the card's
var _rent_caption: Label
var _owner_val: Label
var _flags: HBoxContainer
var _acts: GridContainer
var _b_build: Button
var _b_sell: Button
var _b_mortgage: Button
var _b_unmortgage: Button
var _hide_timer := 0.0
const _HIDE_AFTER := 5.0
var _pinned := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 10)
	add_child(m)
	var v := UiTheme.vbox(6)
	m.add_child(v)

	var head := UiTheme.hbox(6)
	var title := UiTheme.label(I18n.t("ins.title"), 12, UiTheme.COL().accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var pin := UiTheme.button("", I18n.t("ins.pin_tip"))
	pin.custom_minimum_size = Vector2(26, 22)
	pin.toggle_mode = true
	pin.connect("toggled", func(pressed: bool) -> void:
		_pinned = pressed
		if pressed:
			_hide_timer = _HIDE_AFTER)
	head.add_child(pin)
	var close := UiTheme.button("×", I18n.t("ins.close_tip"))
	close.custom_minimum_size = Vector2(26, 22)
	close.connect("pressed", Callable(self, "clear"))
	head.add_child(close)
	v.add_child(head)

	_placeholder = UiTheme.label_wrap(I18n.t("ins.placeholder"), 12, UiTheme.COL().text_dim)
	v.add_child(_placeholder)

	_body = UiTheme.vbox(6)
	_body.visible = false
	v.add_child(_body)

	var name_row := UiTheme.hbox(6)
	_name_lbl = UiTheme.label("", 14)
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(_name_lbl)
	_band = ColorRect.new()
	_band.custom_minimum_size = Vector2(10, 10)
	_band.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_band)
	_type_lbl = UiTheme.label("", 11, UiTheme.COL().text_dim)
	name_row.add_child(_type_lbl)
	_body.add_child(name_row)

	_rows_box = UiTheme.vbox(3)
	_price_val = _fact_row(_rows_box, "ins.price")
	_rent_val = _fact_row(_rows_box, "ins.rent")
	# E-3: `_fact_row` builds the caption from a key ASKED BY VARIABLE, which a static scan cannot
	# see (that is how `{ins.price}:` once reached the screen). The caption is kept so the rent row
	# can relabel itself to "сейчас"/"now", and so HG-09's live pass has something to scan.
	_rent_caption = _last_caption
	_owner_val = _fact_row(_rows_box, "ins.owner")
	_body.add_child(_rows_box)

	_flags = UiTheme.hbox(6)
	_body.add_child(_flags)

	_acts = GridContainer.new()
	_acts.columns = 2
	_acts.add_theme_constant_override("h_separation", 6)
	_acts.add_theme_constant_override("v_separation", 6)
	_b_build = _act_btn("act.build", "build_house")
	_b_sell = _act_btn("act.sell", "sell_house")
	_b_mortgage = _act_btn("act.mortgage", "mortgage_property")
	_b_unmortgage = _act_btn("act.unmortgage", "unmortgage_property")
	_body.add_child(_acts)


## The caption of the row built by the last `_fact_row` call - so a caller can relabel its own row
## later (E-3 needs exactly that for the rent).
var _last_caption: Label = null


func _fact_row(box: VBoxContainer, key: String) -> Label:
	var row := UiTheme.hbox(6)
	var k := UiTheme.label(I18n.t(key) + ":", 11, UiTheme.COL().text_dim)
	k.custom_minimum_size.x = 84
	row.add_child(k)
	_last_caption = k
	var val := UiTheme.label("", 12)
	row.add_child(val)
	box.add_child(row)
	return val


func _act_btn(key: String, op: String) -> Button:
	var b := UiTheme.button(I18n.t(key), I18n.t(key + "_tip"))
	b.custom_minimum_size.y = 28
	b.connect("pressed", func() -> void:
		if selected >= 0:
			action_requested.emit(selected, op))
	_acts.add_child(b)
	return b


func _process(delta: float) -> void:
	if selected >= 0 and not _pinned:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			clear()


func select(idx: int) -> void:
	selected = idx
	_hide_timer = _HIDE_AFTER
	visible = true


func clear() -> void:
	selected = -1
	_placeholder.visible = true
	_body.visible = false


## Fill from the projection. `legal` = the decision holder's legal actions;
## `human_pid` = this execution's local seat (-1 spectator).
func sync(proj: Dictionary, seats: Array, legal: Array = [], human_pid: int = -1) -> void:
	if selected < 0:
		_placeholder.visible = true
		_body.visible = false
		return
	var t: Dictionary = {}
	for e in (proj.get("board", []) as Array):
		if int(e.get("index", -1)) == selected:
			t = e
			break
	if t.is_empty():
		return
	_name_lbl.text = str(t.get("name", ""))
	var group: String = str(t.get("group", ""))
	_band.visible = group != ""
	if _band.visible:
		_band.color = UiTheme.skin().group_color(group)
	_type_lbl.text = group if group != "" else str(t.get("type", ""))
	var cost: int = int(t.get("cost", 0))
	# E-3/D11: show what the tile charges RIGHT NOW (houses + monopoly applied), and keep the base
	# card rent visible when it differs - the player needs both numbers to make a decision: what the
	# card says, and what the game will actually take. Showing only "rent_set" told a bare-plot
	# owner that a rival's 3-house row was worth the un-improved value.
	var rent_base: int = int(t.get("rent_set", t.get("rent", 0)))
	var rent_now: int = int(t.get("rent_now", rent_base))
	_price_val.text = MoneyFmt.make("$").amount(cost)
	_rent_val.text = MoneyFmt.make("$").amount(rent_now)
	# the "now" marker: only when the two differ, so the common case stays a single clean number
	_rent_caption.text = I18n.t("ins.rent_now") if rent_now != rent_base else I18n.t("ins.rent")
	var owner: int = int(t.get("owner", -1))
	if owner < 0:
		_owner_val.text = I18n.t("ins.free")
		_owner_val.add_theme_color_override("font_color", UiTheme.COL().success)
	else:
		var nm := ""
		var col: Color = UiTheme.COL().text
		for s in seats:
			if int(s.pid) == owner:
				nm = str(s.name)
				col = s.color
		_owner_val.text = nm
		_owner_val.add_theme_color_override("font_color", col)
	for c in _flags.get_children():
		_flags.remove_child(c)
		c.queue_free()
	var houses: int = int(t.get("houses", 0))
	if houses > 0:
		_flags.add_child(_chip(I18n.t("ins.house", [I18n.t("ins.hotel") if houses >= 5 else str(houses)])))
	if bool(t.get("mortgaged", false)):
		_flags.add_child(_chip(I18n.t("ins.mortgaged")))
	var mine: bool = human_pid >= 0 and owner == human_pid
	_b_build.disabled = not (mine and legal.has("build_house"))
	_b_sell.disabled = not (mine and houses > 0 and legal.has("sell_house"))
	_b_mortgage.disabled = not (mine and not bool(t.get("mortgaged", false)) and legal.has("mortgage_property"))
	_b_unmortgage.disabled = not (mine and bool(t.get("mortgaged", false)) and legal.has("unmortgage_property"))
	_placeholder.visible = false
	_body.visible = true


func _chip(text: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 3))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	p.add_child(m)
	m.add_child(UiTheme.label(text, 11, UiTheme.COL().text_dim))
	return p


func retranslate() -> void:
	if _placeholder != null:
		_placeholder.text = I18n.t("ins.placeholder")
