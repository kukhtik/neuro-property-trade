extends PanelContainer
## The v3 header (`#top` in design/src/proto.html): brand, whose turn it is, the round
## and pot chips, the decision area, the role badge and the control strip.
##
## Rebuilt from the prototype markup for the interface swap; reads only the spectator
## projection and emits requests — it never touches the engine.

signal settings_requested
signal restart_requested
signal skin_requested(skin_id: String)
## PART 2: the header's panels button - the same toggle as the H key.
signal panels_requested

const UiTheme := preload("res://ui/theme.gd")
# the ONE home for the HUD's smallest type size (see HUD_MIN_PX)
const LayoutProfile := preload("res://ui/core/layout_profile.gd")
const I18n := preload("res://i18n/i18n.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const KeyboardNav := preload("res://ui/core/keyboard_nav.gd")

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
## PART 2: the header button that hides/shows the side panels.
var _btn_panels: Button
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
	_brand = UiTheme.label("•  NEURO PROPERTY TRADE", 12, UiTheme.COL().text)
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
	# NAMED BY ROLE, exactly as the ring cells name their own labels (tile-name/tile-price):
	# a gate that identifies a label by its text or its font is guessing, and a guess that
	# matches nothing says nothing. These two carry what a viewer must grasp at a glance -
	# whose turn it is and what is happening - so the stream-readability measurement has to be
	# able to find them. See game/tools/gates/stream_read_gate.gd.
	_turn_name.name = "turn-name"
	_turn_phase = UiTheme.label("", LayoutProfile.HUD_MIN_PX, UiTheme.COL().text_dim)
	_turn_phase.name = "turn-phase"
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
	_round_chip.name = "top-round"
	row.add_child(_round_chip)
	_pot_chip = _chip("БАНК $0")
	_pot_chip.name = "top-pot"
	row.add_child(_pot_chip)

	_decision = UiTheme.label("", 12, UiTheme.COL().accent)
	row.add_child(_decision)

	_rolebadge = _chip(I18n.t("mode.player"))
	row.add_child(_rolebadge)

	_btn_settings = _text_btn("top.settings", I18n.t("top.settings_tip"))
	_btn_settings.connect("pressed", func() -> void: settings_requested.emit())
	row.add_child(_btn_settings)
	# PART 2: hide/show the side panels. A header button and the H key do the same thing, so the
	# order's "a button on the panel OR a hotkey" is both, and the badge names the key.
	_btn_panels = _text_btn("top.panels", I18n.t("top.panels_tip"))
	_btn_panels.connect("pressed", func() -> void: panels_requested.emit())
	row.add_child(_btn_panels)
	_btn_restart = _text_btn("top.restart", I18n.t("top.restart_tip"))
	_btn_restart.connect("pressed", func() -> void: restart_requested.emit())
	row.add_child(_btn_restart)
	_btn_lang = _text_btn("top.lang", I18n.t("top.lang_tip"))
	_btn_lang.connect("pressed", func() -> void:
		_locale = "en" if _locale == "ru" else "ru"
		I18n.set_locale(_locale)
		retranslate())
	row.add_child(_btn_lang)
	_btn_skin = _text_btn("top.skin", I18n.t("top.skin_tip"))
	_btn_skin.connect("pressed", Callable(self, "_cycle_skin"))
	row.add_child(_btn_skin)

	_apply_header_fit()


## THE HEADER SHEDS ITS DECORATION BEFORE IT OVERFLOWS.
##
## At the minimum supported width (880) the row already carried every chip and control; one more
## button pushed it to 885px inside an 880px window (SG-02 caught it: "leaves the viewport"). The
## brand is a watermark - the board's centre states the name in full - so it is the first thing to
## go, exactly as the compact profile trims content instead of shrinking type.
##
## One place computes it, so the button's arrival cannot re-introduce the overflow.
func _apply_header_fit() -> void:
	if _brand == null:
		return
	var frame_w := 0.0
	var vp := get_viewport()
	if vp != null:
		frame_w = vp.get_visible_rect().size.x
	if frame_w <= 1.0:
		return          # not laid out yet (a headless probe): keep the default, do not guess
	# THE HEADER SHEDS CONTROLS AS THE WINDOW NARROWS.
	#
	# The controls read as WORDS now (owner, 17.10: no glyphs), and words are wider than symbols were:
	# the five buttons measure ~320px together where the five glyphs took 150. At 1000px that pushed
	# the header to 1175px - SG-02 measured `@Button@23 rect [958,8 84x56]` in a 1000px frame. So the
	# header gives things up in order of how little they are needed, and every one of them is also
	# reachable from the settings screen (`Настройки`), which is never hidden:
	#   < 1500  drop the brand watermark (a decoration)
	#   < 1180  drop the skin and language buttons (both live in the settings sheet)
	#   <  980  drop the restart button (destructive, and the sheet asks for confirmation)
	_brand.visible = frame_w >= 1500.0
	_btn_skin.visible = frame_w >= 1180.0
	_btn_lang.visible = frame_w >= 1180.0
	_btn_restart.visible = frame_w >= 980.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _brand != null:
		_apply_header_fit()


func _chip(text: String) -> Label:
	var l := UiTheme.label(text, LayoutProfile.HUD_MIN_PX, UiTheme.COL().text_dim)
	l.add_theme_stylebox_override("normal",
		UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	l.add_theme_constant_override("outline_size", 0)
	return l


## A header control. It is a WORD, not a glyph.
##
## The owner's rule (17.10): "значки не используем впринципе ... нужны нормальные читаемые надписи".
## A symbol asks the player to learn it; a word does not. This replaced `_icon_btn`, whose captions
## were a single character - and several of those characters ("*", "◊", "«") carried no meaning even
## once the font question was settled.
##
## The label is read from i18n and the TIP names the action, so the button keeps a hover explanation
## too. `_relabel` refreshes both on a locale change.
func _text_btn(label_key: String, tip: String) -> Button:
	var b := UiTheme.button(I18n.t(label_key), tip)
	b.set_meta("label_key", label_key)
	b.set_meta("tip", tip)
	# ONE place sets the boxes, and it is the padded one. These two overrides used to be written AFTER
	# `_pad_caption`, replacing the padded styleboxes with zero-padded ones - which is why the gate
	# kept measuring `min 77 vs text 77` no matter what the padding function did.
	_pad_caption(b)
	b.custom_minimum_size.y = 30
	return b


## The width a word button needs: its caption at the button's own font, plus room for a longer word
## in the other language. The margin is deliberate and measured, not a round number.
##
## `custom_minimum_size` ALONE IS NOT ENOUGH: measured `cms=101` on the button while
## `get_minimum_size()` still returned 77, because a Button's minimum is its CONTENT's minimum and the
## header row recomputes it - `custom_minimum_size` never raised it. SG-11 reads
## `get_minimum_size()`, so the number has to be real: the button's theme is given the extra padding
## its caption needs.
func _caption_min_width(b: Button) -> float:
	var f: Font = b.get_theme_font("font")
	var fs: int = b.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return 0.0
	return ceilf(f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 24.0


## Give the button enough side padding that its MINIMUM is wider than its caption.
##
## `content_margin_*` on the stylebox is what a Button's `get_minimum_size()` actually reads, so this
## is where the headroom has to be written. The button keeps the transparent look: the margins are
## set on the same empty boxes `_text_btn` uses.
func _pad_caption(b: Button) -> void:
	var f: Font = b.get_theme_font("font")
	var fs: int = b.get_theme_font_size("font_size")
	if f == null or fs <= 0:
		return
	var tw: float = ceilf(f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	# half the margin per side, so text + 2*pad = text + 24
	var pad: float = 12.0
	b.add_theme_stylebox_override("normal",
		UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, pad))
	b.add_theme_stylebox_override("hover",
		UiTheme.box(UiTheme.COL().panel_dark, Color(0, 0, 0, 0), 0, 0, pad))
	b.custom_minimum_size.x = tw + pad * 2.0


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
	_brand.text = "•  " + I18n.t("top.title")
	# the ACTIVE locale is the source of truth: a switch from elsewhere (settings sheet, a
	# gate) must not leave the toggle showing the wrong next-language
	_locale = I18n.current
	# the language button names the ACTION ("Язык"/"Language") and says in its tip which language it
	# switches TO, so a word button does not lose the old glyph's immediate feedback
	_btn_lang.text = I18n.t("top.lang")
	_btn_lang.tooltip_text = "%s → %s" % [I18n.t("top.lang_tip"), "EN" if _locale == "ru" else "RU"]
	# EVERY header control reads as a word, in the current language. The minimum width is recomputed
	# because a word button must keep headroom over THIS language's caption (SG-11).
	for b in [_btn_settings, _btn_panels, _btn_restart, _btn_skin]:
		if b != null and b.has_meta("label_key"):
			b.text = I18n.t(str(b.get_meta("label_key")))
			b.custom_minimum_size.x = _caption_min_width(b)
	_btn_lang.custom_minimum_size.x = _caption_min_width(_btn_lang)
	_btn_settings.tooltip_text = I18n.t("top.settings_tip")
	# PART 2/3: the panels button's tooltip carries its key AND the keyboard model's hotkey list, so
	# the player reads the whole keyboard from the one control that is about the interface. The list
	# is BUILT FROM KeyboardNav.HOTKEYS - a rebinding cannot leave this text lying.
	_btn_panels.tooltip_text = "%s\n%s" % [I18n.t("top.panels_tip"), KeyboardNav.hotkey_hint()]
	_btn_restart.tooltip_text = I18n.t("top.restart_tip")
	_btn_skin.tooltip_text = I18n.t("top.skin_tip")
	_rolebadge.text = I18n.t("mode.player")
