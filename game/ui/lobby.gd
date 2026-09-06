class_name Lobby
extends Control
## Pre-game lobby: configure players (driver/name/color), game settings, then
## START. Emits `started(settings, seats)` when the host starts. Pure UI over
## GameSettings + SeatConfig — no engine here. Shape-only widgets (theme), so
## art can replace them later without logic changes.

signal started(settings, seats)

const UiTheme := preload("res://ui/theme.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")

const DRIVERS := ["LOCAL", "AI"]
const NAMES := ["Host", "AI-2", "AI-3", "AI-4", "AI-5", "AI-6", "AI-7", "AI-8"]
const COLORS := [Color("e74c3c"), Color("3498db"), Color("2ecc71"),
	Color("f1c40f"), Color("9b59b6"), Color("e67e22"), Color("1abc9c"), Color("34495e")]

var _rows: Array = []            # per-player: {driver, name, color, remove_btn}
var _seat_count := 4

var _turn_timer: OptionButton    # seconds
var _auction_timer: OptionButton
var _free_parking: OptionButton
var _starting_order: OptionButton
var _auctions: OptionButton
var _language: OptionButton
var _animations: CheckButton
var _event_overlay: CheckButton
var _rng_seed: SpinBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

## A1: keep the centered lobby panel within the viewport so the inner
## ScrollContainer can scroll instead of clipping on small screens.
func _process(_delta: float) -> void:
	if _root == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	var target := Vector2(minf(_root.custom_minimum_size.x, vs.x), minf(_root.custom_minimum_size.y, vs.y))
	if _root.size != target:
		_root.size = target
		_root.position = (vs - target) * 0.5

func _build() -> void:
	_build_background()
	var root := UiTheme.panel()
	_root = root
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(720, 540)
	root.reset_size()
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.position = (get_viewport().get_visible_rect().size - root.size) * 0.5
	add_child(root)

	# A1: wrap the content in a ScrollContainer so the lobby scrolls on small
	# screens instead of clipping (the panel keeps its min size; the scroll
	# view shrinks to fit the viewport).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var v := UiTheme.vbox(12)
	margin.add_child(v)

	# title
	var title := UiTheme.label("●  NEURO PROPERTY TRADE", 26, UiTheme.COL.gold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var subtitle := UiTheme.label("Настройка партии", 13, UiTheme.COL.text_dim)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)

	# players section
	var players_lbl := UiTheme.label("ИГРОКИ", 15, UiTheme.COL.accent)
	v.add_child(players_lbl)
	var players_box := UiTheme.panel()
	v.add_child(players_box)
	_players_list = UiTheme.vbox(6)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 12)
	pm.add_theme_constant_override("margin_right", 12)
	pm.add_theme_constant_override("margin_top", 10)
	pm.add_theme_constant_override("margin_bottom", 10)
	players_box.add_child(pm)
	pm.add_child(_players_list)

	var add_row := UiTheme.button("+ добавить игрока", "Добавить ещё одного игрока (до 8)")
	add_row.connect("pressed", Callable(self, "_add_row"))
	add_row.custom_minimum_size.y = 30
	v.add_child(add_row)

	# settings section
	var set_lbl := UiTheme.label("НАСТРОЙКИ", 15, UiTheme.COL.accent)
	v.add_child(set_lbl)
	var set_grid := GridContainer.new()
	set_grid.columns = 4
	set_grid.add_theme_constant_override("h_separation", 14)
	set_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(set_grid)

	_turn_timer = _seconds_option([0, 5, 10, 15, 20, 30, 45, 60], 30)
	var tt_row := _h(UiTheme.label("Таймер хода"), _turn_timer)
	set_grid.add_child(tt_row)

	_auction_timer = _seconds_option([0, 5, 8, 10, 12, 15, 20], 15)
	set_grid.add_child(_h(UiTheme.label("Аукцион"), _auction_timer))

	_free_parking = OptionButton.new()
	_free_parking.add_item("Выкл"); _free_parking.add_item("Вкл")
	_free_parking.selected = 0
	set_grid.add_child(_h(UiTheme.label("Беспл. стоянка"), _free_parking))

	_starting_order = OptionButton.new()
	_starting_order.add_item("случайный"); _starting_order.add_item("вручную")
	_starting_order.selected = 0
	set_grid.add_child(_h(UiTheme.label("Нач. порядок"), _starting_order))

	# language selector (full localization is a follow-up; this stores the choice)
	_language = OptionButton.new()
	_language.add_item("Русский"); _language.add_item("English")
	_language.selected = 0
	set_grid.add_child(_h(UiTheme.label("Язык"), _language))

	# auctions optional
	_auctions = OptionButton.new()
	_auctions.add_item("вкл"); _auctions.add_item("выкл")
	_auctions.selected = 0
	set_grid.add_child(_h(UiTheme.label("Аукционы"), _auctions))

	# help button
	var help_btn := UiTheme.button("?", "Показать справку по настройке партии")
	help_btn.custom_minimum_size = Vector2(30, 24)
	help_btn.connect("pressed", Callable(self, "_show_help"))
	set_grid.add_child(_h(UiTheme.label("Справка"), help_btn))

	# toggles row
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 24)
	_animations = CheckButton.new()
	_animations.text = "анимации"
	_animations.button_pressed = true
	toggles.add_child(_animations)
	_event_overlay = CheckButton.new()
	_event_overlay.text = "журнал событий"
	_event_overlay.button_pressed = true
	toggles.add_child(_event_overlay)
	v.add_child(toggles)

	# rng seed
	var seed_row := HBoxContainer.new()
	var seed_lbl := UiTheme.label("RNG-сид (0 = случайно):")
	_rng_seed = SpinBox.new()
	_rng_seed.min_value = 0
	_rng_seed.max_value = 99999
	_rng_seed.value = 0
	_rng_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_lbl)
	seed_row.add_child(_rng_seed)
	v.add_child(seed_row)

	# start button
	var start := UiTheme.button_accent("▶  СТАРТ ПАРТИЮ", "Начать партию с выбранными игроками и настройками")
	start.custom_minimum_size.y = 44
	start.connect("pressed", Callable(self, "_start_pressed"))
	v.add_child(start)

	# add default rows
	for i in _seat_count:
		_add_row(i)

var _players_list: VBoxContainer
var _root: PanelContainer

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.COL.bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _h(lbl: Label, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(lbl)
	ctl.custom_minimum_size.x = 120
	h.add_child(ctl)
	return h

func _seconds_option(vals: Array, def: int) -> OptionButton:
	var o := OptionButton.new()
	for value in vals:
		var txt: String = str(value) + "с"
		o.add_item(txt if value > 0 else "нет лимита")
		if value == def:
			o.selected = o.item_count - 1
	return o

func _add_row(_unused: Variant = null) -> void:
	if _rows.size() >= 8:
		return
	var idx := _rows.size()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)

	var num := UiTheme.label("%d." % (idx + 1), 14, UiTheme.COL.text_dim)
	num.custom_minimum_size.x = 22
	h.add_child(num)
	# driver selector
	var driver := OptionButton.new()
	for d in DRIVERS:
		driver.add_item(d)
	driver.selected = 0 if idx == 0 else 1   # first seat LOCAL by default
	if idx == 0:
		driver.disabled = true   # host must be LOCAL this pass
	h.add_child(driver)

	# color swatch + selector
	var swatch := ColorRect.new()
	swatch.color = COLORS[idx % COLORS.size()]
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size = Vector2(20, 20)
	h.add_child(swatch)

	var name_edit := LineEdit.new()
	name_edit.text = NAMES[idx % NAMES.size()]
	name_edit.custom_minimum_size.x = 200
	h.add_child(name_edit)

	# remove button (disabled for the host seat)
	var remove_btn := UiTheme.button("✕", "Удалить этого игрока из партии")
	remove_btn.custom_minimum_size = Vector2(24, 20)
	remove_btn.disabled = (idx == 0)
	remove_btn.connect("pressed", Callable(self, "_remove_row").bind(idx))
	h.add_child(remove_btn)

	_rows.append({
		"driver": driver,
		"name": name_edit,
		"color": swatch,
		"remove_btn": remove_btn,
		"row": h,
		"num": num,
	})
	_players_list.add_child(h)

func _remove_row(i: int) -> void:
	if i <= 0 or i >= _rows.size():
		return
	var row: HBoxContainer = _rows[i]["row"]
	_players_list.remove_child(row)
	row.queue_free()
	_rows.remove_at(i)
	# renumber + re-disable host remove
	for j in _rows.size():
		var r: Dictionary = _rows[j]
		(r["num"] as Label).text = "%d." % (j + 1)
		(r["remove_btn"] as Button).disabled = (j == 0)

func _show_help() -> void:
	var msg := "ИГРОКИ: добавьте/удалите игроков, выберите драйвер (LOCAL = человек, AI = компьютер) и имя.\n\n" \
		+ "НАСТРОЙКИ: таймер хода/аукциона (0 = без лимита), бесплатная стоянка, начальный порядок, язык, аукционы.\n\n" \
		+ "СТАРТ: начните партию с выбранными настройками."
	# reuse the modal host pattern via a simple popup
	var popup := AcceptDialog.new()
	popup.title = "Справка"
	popup.dialog_text = msg
	popup.ok_button_text = "OK"
	add_child(popup)
	popup.popup_centered()

func _start_pressed() -> void:
	var s = Settings.new()
	s.seat_count = _rows.size()
	s.seat_assignments = []
	for r in _rows:
		s.seat_assignments.append({
			"driver": str(r["driver"].get_item_text(r["driver"].selected)),
			"name": str(r["name"].text),
			"token_color": (r["color"] as ColorRect).color.to_html(),
		})
	s.rng_seed = int(_rng_seed.value)
	s.starting_order = "random" if _starting_order.selected == 0 else "manual"
	s.turn_timer = _selected_seconds(_turn_timer)
	s.auction_timer = _selected_seconds(_auction_timer)
	s.free_parking = (_free_parking.selected == 1)
	s.auctions_on_refusal = (_auctions.selected == 0)
	s.animations = _animations.button_pressed
	s.event_overlay = _event_overlay.button_pressed
	# language choice stored for future localization (not yet wired to strings)
	s.language = "ru" if _language.selected == 0 else "en"
	# build seats through the resolver so driver labels map (LOCAL/AI/CHAT...)
	var seats: Array = SeatConfig.from_settings(s)
	started.emit(s, seats)

func _selected_seconds(o: OptionButton) -> int:
	var item: int = o.selected
	if item < 0:
		return 0
	# values are stored in order [0,5,10,...]; reconstruct from label
	var txt: String = o.get_item_text(item)
	if txt == "нет лимита":
		return 0
	return int(txt.trim_suffix("с"))
