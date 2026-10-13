class_name TileInspector
extends PanelContainer
## Right dock bottom: the tile reference card (v3 mockup #inspector). The empty state is
## the placeholder hint; a selected tile fills the card with the name + group band, the
## price / rent / owner ROWS, the house / mortgage FLAGS and the four management buttons —
## the same intents the build modal submits (the engine still validates them).
##
## Pin keeps the selection past the 5s auto-clear; that clear goes back to the EMPTY STATE
## (the hint stays on screen — the mockup never leaves the dock without the card). Reads a
## spectator projection only.

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
var _price_row: HBoxContainer
var _price_val: Label
var _rent_row: HBoxContainer
var _rent_val: Label
var _owner_row: HBoxContainer
var _owner_val: Label
var _k_price: Label
var _k_rent: Label
var _k_owner: Label
var _flags: HBoxContainer
var _acts: GridContainer
var _b_build: Button
var _b_sell: Button
var _b_mortgage: Button
var _b_unmortgage: Button
var _close: Button
var _pin: Button
var _hide_timer := 0.0
const _HIDE_AFTER := 5.0
var _pinned := false


func _init() -> void:
	# v3: a DOCK card (right dock bottom), not a floating bubble. Width comes from the
	# column; the minimum is vertical only, so a railed column never gets blown up.
	custom_minimum_size = Vector2(0, 150)
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 10)
	add_child(m)
	var v := UiTheme.vbox(6)
	m.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var lbl := UiTheme.label(I18n.t("ins.title"), 12, UiTheme.COL().accent)
	I18n.key_on(lbl, "ins.title")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)
	_pin = UiTheme.button("📌", I18n.t("ins.pin_tip"))
	I18n.tip_on(_pin, "ins.pin_tip")
	_pin.custom_minimum_size = Vector2(26, 22)
	_pin.toggle_mode = true
	_pin.connect("toggled", Callable(self, "_on_pin_toggled"))
	head.add_child(_pin)
	_close = UiTheme.button("✕", I18n.t("ins.close_tip"))
	I18n.tip_on(_close, "ins.close_tip")
	_close.custom_minimum_size = Vector2(26, 22)
	_close.connect("pressed", Callable(self, "deselect"))
	head.add_child(_close)
	v.add_child(head)

	_placeholder = UiTheme.label_wrap(I18n.t("ins.placeholder"), 12, UiTheme.COL().text_dim)
	I18n.key_on(_placeholder, "ins.placeholder")
	v.add_child(_placeholder)

	_body = UiTheme.vbox(6)
	_body.visible = false
	v.add_child(_body)

	# name + group band + type, as the mockup's .ins-name
	var name_row := UiTheme.hbox(6)
	_name_lbl = UiTheme.label("", 14)
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_lbl)
	_band = ColorRect.new()
	_band.custom_minimum_size = Vector2(10, 10)
	_band.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_band)
	_type_lbl = UiTheme.label("", 11, UiTheme.COL().text_dim)
	name_row.add_child(_type_lbl)
	_body.add_child(name_row)

	_price_row = HBoxContainer.new()
	_price_row.add_theme_constant_override("separation", 6)
	_k_price = UiTheme.label(I18n.t("ins.price") + ":", 11, UiTheme.COL().text_dim)
	_price_row.add_child(_k_price)
	_price_val = UiTheme.label("", 12)
	_price_row.add_child(_price_val)
	_body.add_child(_price_row)

	_rent_row = HBoxContainer.new()
	_rent_row.add_theme_constant_override("separation", 6)
	_k_rent = UiTheme.label(I18n.t("ins.rent") + ":", 11, UiTheme.COL().text_dim)
	_rent_row.add_child(_k_rent)
	_rent_val = UiTheme.label("", 12)
	_rent_row.add_child(_rent_val)
	_body.add_child(_rent_row)

	_owner_row = HBoxContainer.new()
	_owner_row.add_theme_constant_override("separation", 6)
	_k_owner = UiTheme.label(I18n.t("ins.owner"), 11, UiTheme.COL().text_dim)
	_owner_row.add_child(_k_owner)
	_owner_val = UiTheme.label("", 12)
	_owner_row.add_child(_owner_val)
	_body.add_child(_owner_row)

	_flags = HBoxContainer.new()
	_flags.add_theme_constant_override("separation", 6)
	_body.add_child(_flags)

	# the four management buttons, 2x2 (the mockup lets .ins-acts flex-wrap; a grid is the
	# same deterministic thing in a Godot container)
	_acts = GridContainer.new()
	_acts.columns = 2
	_acts.add_theme_constant_override("h_separation", 6)
	_acts.add_theme_constant_override("v_separation", 6)
	_b_build = _act_btn("act.build", "build_house")
	_b_sell = _act_btn("act.sell", "sell_house")
	_b_mortgage = _act_btn("act.mortgage", "mortgage_property")
	_b_unmortgage = _act_btn("act.unmortgage", "unmortgage_property")
	_body.add_child(_acts)


func _act_btn(key: String, op: String) -> Button:
	var b := UiTheme.button(I18n.t(key), I18n.t(key + "_tip"))
	I18n.key_on(b, key)
	I18n.tip_on(b, key + "_tip")
	b.custom_minimum_size.y = 28
	b.connect("pressed", Callable(self, "_emit").bind(op))
	_acts.add_child(b)
	return b


func _emit(op: String) -> void:
	if selected >= 0:
		action_requested.emit(selected, op)


func _process(delta: float) -> void:
	# auto-clear back to the EMPTY STATE a few seconds after the last selection, unless
	# pinned. The card itself stays in the dock — the mockup never leaves it blank.
	if selected >= 0 and not _pinned:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			clear()


func select(idx: int) -> void:
	selected = idx
	_hide_timer = _HIDE_AFTER   # reset the auto-clear countdown
	visible = true              # docked profiles always show the card; compact re-shows it


## ✕: back to the empty state (the card stays where the mockup keeps it).
func deselect() -> void:
	clear()


func _on_pin_toggled(pressed: bool) -> void:
	_pinned = pressed
	if pressed:
		_hide_timer = _HIDE_AFTER  # keep alive while pinned
	# Update pin button appearance
	if _pinned:
		_pin.add_theme_color_override("font_color", UiTheme.COL().accent)
		_pin.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().accent, UiTheme.COL().border_accent, 2, 6))
	else:
		_pin.add_theme_color_override("font_color", UiTheme.COL().text)
		_pin.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 6))


## P6 CR-5: re-apply the localized placeholder and row keys when the locale changes.
## (Buttons carry i18n_key metadata and are relabelled by I18n.relabel.)
func retranslate() -> void:
	if _placeholder != null:
		_placeholder.text = I18n.t("ins.placeholder")
	if _k_price != null:
		_k_price.text = I18n.t("ins.price") + ":"
	if _k_rent != null:
		_k_rent.text = I18n.t("ins.rent") + ":"
	if _k_owner != null:
		_k_owner.text = I18n.t("ins.owner")


## Back to the empty state (still visible — see the header comment).
func clear() -> void:
	selected = -1
	_hide_timer = 0.0
	_pinned = false
	if _pin != null:
		_pin.button_pressed = false
		_on_pin_toggled(false)
	_placeholder.visible = true
	_body.visible = false


## Fill from a spectator projection. `legal` = the decision holder's legal engine actions;
## `human_pid` = this execution's LOCAL seat (-1 for spectators). The four buttons are
## enabled only when the engine offers the action AND the tile belongs to the local seat —
## the same gating the mockup draws as `owner === 0`.
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
	# name + group band + type (raw group/type strings, as the mockup prints them)
	_name_lbl.text = str(t.get("name", ""))
	var group: String = str(t.get("group", ""))
	_band.visible = group != ""
	if _band.visible:
		_band.color = UiTheme.skin().group_color(group)
	_type_lbl.text = group if group != "" else str(t.get("type", ""))
	# rows
	var cost: int = int(t.get("cost", 0))
	var rent: int = int(t.get("rent_set", t.get("rent", 0)))
	_price_row.visible = cost > 0
	_price_val.text = MoneyFmt.new().amount(cost)
	_rent_row.visible = rent > 0
	_rent_val.text = MoneyFmt.new().amount(rent)
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
				break
		_owner_val.text = nm
		_owner_val.add_theme_color_override("font_color", col)
	# flags
	for c in _flags.get_children():
		_flags.remove_child(c)
		c.queue_free()
	var houses: int = int(t.get("houses", 0))
	if houses > 0:
		_flags.add_child(_chip(I18n.t("ins.house", [I18n.t("ins.hotel") if houses >= 5 else str(houses)])))
	var mortgaged: bool = bool(t.get("mortgaged", false))
	if mortgaged:
		_flags.add_child(_chip(I18n.t("ins.mortgaged")))
	# acts
	var mine: bool = human_pid >= 0 and owner == human_pid
	_b_build.disabled = not (mine and legal.has("build_house"))
	_b_sell.disabled = not (mine and houses > 0 and legal.has("sell_house"))
	_b_mortgage.disabled = not (mine and not mortgaged and legal.has("mortgage_property"))
	_b_unmortgage.disabled = not (mine and mortgaged and legal.has("unmortgage_property"))
	_placeholder.visible = false
	_body.visible = true


## A small chip like the mockup's `.ins-flags .chip`.
func _chip(text: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().get("surface3", UiTheme.COL().panel), UiTheme.COL().border, 1, 3))
	var mm := MarginContainer.new()
	mm.add_theme_constant_override("margin_left", 6)
	mm.add_theme_constant_override("margin_right", 6)
	mm.add_theme_constant_override("margin_top", 1)
	mm.add_theme_constant_override("margin_bottom", 1)
	p.add_child(mm)
	mm.add_child(UiTheme.label(text, 11, UiTheme.COL().text_dim))
	return p
