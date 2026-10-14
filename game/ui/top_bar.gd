extends PanelContainer
## The v3 header (`#top` in design/src/proto.html): brand, whose turn it is, the round
## and pot chips, the decision area, the role badge and the control strip.
##
## Rebuilt from the prototype markup for the interface swap; reads only the spectator
## projection and emits requests — it never touches the engine.

signal settings_requested
signal restart_requested
signal skin_requested(skin_id: String)

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

var _brand: Label
var _turn_av: Control
var _turn_halo: Panel
var _turn_name: Label
var _turn_phase: Label
var _steps: HBoxContainer
var _round_chip: Label
var _pot_chip: Label
var _decision: Label
## HG-13 timer ring state: what the projection last said + when it said it
var _timer_window := 0.0
var _timer_elapsed := 0.0
var _timer_t0 := 0
var _timer_on := false
var _rolebadge: Label
var _btn_settings: Button
var _btn_restart: Button
var _btn_lang: Button
var _btn_skin: Button
var _skin_idx := 0
var _locale := "ru"
var _skin: SkinManager


func _init() -> void:
	custom_minimum_size.y = 56   # `--hdr-h`
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, Color(0, 0, 0, 0), 0, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 12)
	add_child(m)
	var row := UiTheme.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(row)

	# brand: the diamond in accent + the name in text colour (proto `.brand`)
	_brand = UiTheme.label("●  NEURO PROPERTY TRADE", 12, UiTheme.COL().text)
	_brand.add_theme_constant_override("letter_spacing", 2)
	row.add_child(_brand)

	# turn block: a haloed avatar dot + name / phase
	_turn_av = Control.new()
	_turn_av.custom_minimum_size = Vector2(26, 26)
	_turn_halo = Panel.new()
	_turn_halo.add_theme_stylebox_override("panel",
		UiTheme.box(Color(0, 0, 0, 0), UiTheme.COL().accent, 2, 13))
	_turn_halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_av.add_child(_turn_halo)
	row.add_child(_turn_av)
	var meta := UiTheme.vbox(0)
	_turn_name = UiTheme.label("—", 13, UiTheme.COL().text)
	_turn_phase = UiTheme.label("", 10, UiTheme.COL().text_dim)
	meta.add_child(_turn_name)
	meta.add_child(_turn_phase)
	row.add_child(meta)

	_steps = UiTheme.hbox(3)
	for i in 4:
		var tick := ColorRect.new()
		tick.color = UiTheme.COL().border
		tick.custom_minimum_size = Vector2(14, 3)
		_steps.add_child(tick)
	row.add_child(_steps)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_round_chip = _chip("РАУНД 1")
	row.add_child(_round_chip)
	_pot_chip = _chip("БАНК $0")
	row.add_child(_pot_chip)

	_decision = UiTheme.label("", 12, UiTheme.COL().accent)
	row.add_child(_decision)

	_rolebadge = _chip(I18n.t("mode.player"))
	row.add_child(_rolebadge)

	_btn_settings = _icon_btn("⚙", I18n.t("top.settings_tip"))
	_btn_settings.connect("pressed", func() -> void: settings_requested.emit())
	row.add_child(_btn_settings)
	_btn_restart = _icon_btn("⟳", I18n.t("top.restart_tip"))
	_btn_restart.connect("pressed", func() -> void: restart_requested.emit())
	row.add_child(_btn_restart)
	_btn_lang = _icon_btn("RU", I18n.t("top.lang_tip"))
	_btn_lang.connect("pressed", func() -> void:
		_locale = "en" if _locale == "ru" else "ru"
		I18n.set_locale(_locale)
		retranslate())
	row.add_child(_btn_lang)
	_btn_skin = _icon_btn("◐", I18n.t("top.skin_tip"))
	_btn_skin.connect("pressed", Callable(self, "_cycle_skin"))
	row.add_child(_btn_skin)


func _chip(text: String) -> Label:
	var l := UiTheme.label(text, 10, UiTheme.COL().text_dim)
	l.add_theme_stylebox_override("normal",
		UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	l.add_theme_constant_override("outline_size", 0)
	return l


func _icon_btn(glyph: String, tip: String) -> Button:
	var b := UiTheme.button(glyph, tip)
	b.custom_minimum_size = Vector2(30, 30)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.COL().panel_dark, Color(0, 0, 0, 0), 0, 0))
	return b


func _cycle_skin() -> void:
	var order := ["neuro", "evil", "default", "classic"]
	_skin_idx = (_skin_idx + 1) % order.size()
	skin_requested.emit(order[_skin_idx])


func set_cold() -> void:
	_turn_name.text = "—"
	_turn_phase.text = I18n.t("top.cold")


## Paint from the spectator projection + seat list.
func sync(proj: Dictionary, seats: Array) -> void:
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var name_txt := "—"
	var color: Color = UiTheme.COL().accent
	for s in seats:
		if int(s.pid) == turn:
			name_txt = str(s.name)
			color = s.color
			break
	_turn_name.text = name_txt
	_turn_name.add_theme_color_override("font_color", color)
	_turn_halo.add_theme_stylebox_override("panel",
		UiTheme.box(Color(0, 0, 0, 0), color, 2, 13))
	var ph: String = str(proj.get("phase", ""))
	var ph_lbl: String = I18n.t("phase." + ph)
	if ph_lbl.begins_with("{phase."):
		ph_lbl = ph
	_turn_phase.text = I18n.t("top.turn") + " " + ("—" if ph_lbl == "" else ph_lbl)
	# round chip (`top.round`) + parking pot (`top.pot`)
	var round_n: int = int(proj.get("round", 1))
	_round_chip.text = I18n.t("top.round") + " " + str(round_n)
	# THE PROJECTION'S NAME IS `parking_pot`. The UI asked for `pot` ever since the swap, a
	# missing key yields null, and the chip showed "$0" for every match while the pot filled
	# up in the engine (found by the audit; pinned by ui_contract_test / HG-10).
	var pot: int = int(proj.get("parking_pot", 0))
	_pot_chip.text = I18n.t("top.pot") + " $%d" % pot
	# the step ticks follow the turn player's position around the ring
	var pos: int = 0
	for p in (proj.get("players", []) as Array):
		if int(p.get("index", -1)) == turn:
			pos = int(p.get("position", 0))
	var step: int = pos % 11
	for i in _steps.get_child_count():
		(_steps.get_child(i) as ColorRect).color = UiTheme.COL().accent if i <= step / 3 else UiTheme.COL().border
	var pend: Dictionary = proj.get("pending", {})
	_decision.text = ""
	# HG-13: the decision zone carries the TIME while a seat waits - the projection has carried
	# timer_window/elapsed/active all along (seat_manager.emit_spectator); nobody painted them.
	_timer_on = bool(proj.get("timer_active", false)) and float(proj.get("timer_window", 0.0)) > 0.0
	if _timer_on:
		_timer_window = float(proj.get("timer_window", 0.0))
		_timer_elapsed = float(proj.get("timer_elapsed", 0.0))
		_timer_t0 = Time.get_ticks_msec()
	else:
		_timer_window = 0.0
		if str(pend.get("type", "")) == "purchase":
			_decision.text = I18n.t("top.decision")
	_decision.visible = _timer_on or _decision.text != ""


## HG-13: the remaining time ticks locally between projections - the projection says how long
## the seat has ALREADY waited, this adds the time since it arrived. With turn_timer=0 the
## projection says timer_active=false and this never runs (no widget for a disabled timer).
func _process(_delta: float) -> void:
	if not _timer_on or not is_visible_in_tree():
		return
	var rem := _timer_window - (_timer_elapsed + float(Time.get_ticks_msec() - _timer_t0) / 1000.0)
	rem = maxf(rem, 0.0)
	_decision.text = "%d:%02d" % [int(rem / 60.0), int(rem) % 60]
	_decision.visible = true


func retranslate() -> void:
	_brand.text = "●  " + I18n.t("top.title")
	# the ACTIVE locale is the source of truth: a switch from elsewhere (settings sheet, a
	# gate) must not leave the toggle showing the wrong next-language
	_locale = I18n.current
	_btn_lang.text = "EN" if _locale == "ru" else "RU"
	_btn_lang.tooltip_text = I18n.t("top.lang_tip")
	_btn_settings.tooltip_text = I18n.t("top.settings_tip")
	_btn_restart.tooltip_text = I18n.t("top.restart_tip")
	_btn_skin.tooltip_text = I18n.t("top.skin_tip")
	_rolebadge.text = I18n.t("mode.player")
