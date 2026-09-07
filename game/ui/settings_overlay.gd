class_name SettingsOverlay
extends Control
## Pre-game / in-game settings overlay (replaces the old lobby). One screen:
## this overlay sits on top of the live board. Pre-game it opens on first run
## with focus on START; in-game ⚙ reopens the same overlay. Tabs per spec 5.1:
## Игроки / Правила / Темп / Интерфейс / Данные. Emits `started(settings, seats)`
## on pre-game START and `apply_requested(settings, seats)` on in-game restart.
## Pure UI over GameSettings + SeatConfig — no engine here.

signal started(settings, seats)
signal apply_requested(settings, seats)
signal closed

const UiTheme := preload("res://ui/theme.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const PI := preload("res://core/player_identity.gd")

const DRIVERS := ["LOCAL", "AI", "CHAT", "sdk:neuro", "sdk:evil"]
const NAMES := ["Host", "AI-2", "AI-3", "AI-4", "AI-5", "AI-6", "AI-7", "AI-8"]
const COLORS := PI.COLORS
const TOKENS := PI.TOKENS

var _rows: Array = []            # per-player: {driver, name, color, token, remove_btn, row}
var _pre_game := true            # true => main button is СТАРТ; false => ПРИМЕНИТЬ (restart)

# control refs
var _root: PanelContainer
var _tabs: TabContainer
var _players_list: VBoxContainer
var _host_role: OptionButton
var _starting_order: OptionButton
var _start_btn: Button
var _apply_btn: Button
var _rules_btn: Button
var _status_lbl: Label

# rules tab
var _starting_cash: SpinBox
var _go_bonus: SpinBox
var _jail_rule: OptionButton
var _jail_fine: SpinBox
var _free_parking: OptionButton
var _doubles: CheckButton
var _triple_doubles: CheckButton
var _auctions: OptionButton
var _housing: CheckButton
var _even_build: CheckButton
var _monopoly_x2: CheckButton
var _mortgage: CheckButton
var _loan_pct: SpinBox
var _repay_pct: SpinBox
var _trades: CheckButton
var _ai_aggression: SpinBox

# tempo tab
var _turn_timer: OptionButton
var _auction_timer: OptionButton
var _timeout_action: OptionButton

# interface tab
var _animations: CheckButton
var _event_overlay: CheckButton
var _spectacle: CheckButton
var _language: OptionButton
var _sound: CheckButton

# data tab
var _rng_seed: SpinBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

## Pre-game (START button) vs in-game (ПРИМЕНИТЬ / restart) mode.
func set_mode(pre_game: bool) -> void:
	_pre_game = pre_game
	_refresh_buttons()

func _build() -> void:
	# dim background under the overlay
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_root = UiTheme.panel()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(860, 600)
	_root.reset_size()
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.position = (get_viewport().get_visible_rect().size - _root.size) * 0.5
	add_child(_root)

	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 16)
	_root.add_child(margin)
	var v := UiTheme.vbox(10)
	margin.add_child(v)

	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var title := UiTheme.label("НАСТРОЙКИ МАТЧА", 20, UiTheme.COL.gold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset_btn := UiTheme.button("сброс", "Сбросить все настройки к значениям по умолчанию")
	reset_btn.connect("pressed", Callable(self, "_reset_all"))
	head.add_child(reset_btn)
	var close_btn := UiTheme.button("✕ ESC", "Закрыть настройки (ESC)")
	close_btn.connect("pressed", Callable(self, "_on_close"))
	head.add_child(close_btn)
	v.add_child(head)

	# presets row
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	presets.add_child(UiTheme.label("ПРЕСЕТЫ:", 13, UiTheme.COL.text_dim))
	var p_classic := UiTheme.button("Классика", "Стандартные правила Monopoly")
	p_classic.connect("pressed", Callable(self, "_preset_classic"))
	presets.add_child(p_classic)
	var p_fast := UiTheme.button("Быстрая партия", "Таймер 10с, капитал 1000")
	p_fast.connect("pressed", Callable(self, "_preset_fast"))
	presets.add_child(p_fast)
	var p_hard := UiTheme.button("Хардкор", "Без залога/торгов, агрессия 80")
	p_hard.connect("pressed", Callable(self, "_preset_hard"))
	presets.add_child(p_hard)
	v.add_child(presets)

	# tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_players_tab()
	_build_rules_tab()
	_build_tempo_tab()
	_build_interface_tab()
	_build_data_tab()

	# status + action row
	_status_lbl = UiTheme.label("", 12, UiTheme.COL.text_dim)
	v.add_child(_status_lbl)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_start_btn = UiTheme.button_accent("▶  СТАРТ ПАРТИЮ", "Начать партию с выбранными игроками и настройками")
	_start_btn.custom_minimum_size.y = 40
	_start_btn.connect("pressed", Callable(self, "_start_pressed"))
	actions.add_child(_start_btn)
	_apply_btn = UiTheme.button_accent("ПРИМЕНИТЬ: новая партия", "Пересобрать движок с этими настройками (нужен рестарт)")
	_apply_btn.custom_minimum_size.y = 40
	_apply_btn.connect("pressed", Callable(self, "_apply_pressed"))
	actions.add_child(_apply_btn)
	_rules_btn = UiTheme.button("📜 ПРАВИЛА", "Показать полные правила по текущим настройкам")
	_rules_btn.connect("pressed", Callable(self, "_show_rules"))
	actions.add_child(_rules_btn)
	v.add_child(actions)

	# default rows
	for i in 4:
		_add_row(i)
	_refresh_buttons()

func _build_players_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Игроки")

	var players_box := UiTheme.panel()
	tab.add_child(players_box)
	_players_list = UiTheme.vbox(6)
	var pm := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pm.add_theme_constant_override(edge, 10)
	players_box.add_child(pm)
	pm.add_child(_players_list)

	var add_row := UiTheme.button("+ добавить игрока", "Добавить ещё одного игрока (до 8)")
	add_row.connect("pressed", Callable(self, "_add_row"))
	add_row.custom_minimum_size.y = 28
	tab.add_child(add_row)

	# host role + starting order
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 20)
	opts.add_child(UiTheme.label("Роль хоста:", 13))
	_host_role = OptionButton.new()
	_host_role.add_item("играю (LOCAL)"); _host_role.add_item("только наблюдаю (без LOCAL)")
	_host_role.selected = 0
	_host_role.tooltip_text = "«только наблюдаю» = в матче нет LOCAL-места, ИИ играют сами (режим наблюдателя)."
	opts.add_child(_host_role)
	opts.add_child(UiTheme.label("Нач. порядок:", 13))
	_starting_order = OptionButton.new()
	_starting_order.add_item("случайный"); _starting_order.add_item("вручную")
	_starting_order.selected = 0
	_starting_order.tooltip_text = "Случайный порядок ходов или порядок в списке игроков."
	opts.add_child(_starting_order)
	tab.add_child(opts)

func _build_rules_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Правила")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_starting_cash = _spin(100, 100000, 1500, "Стартовый капитал", "Сколько денег у каждого игрока в начале.")
	grid.add_child(_h("Стартовый капитал", _starting_cash))
	_go_bonus = _spin(0, 10000, 200, "Бонус за GO", "Сколько получает игрок, проходя через GO.")
	grid.add_child(_h("Бонус за GO", _go_bonus))

	_jail_rule = OptionButton.new()
	_jail_rule.add_item("оба"); _jail_rule.add_item("штраф"); _jail_rule.add_item("карта")
	_jail_rule.selected = 0
	_jail_rule.tooltip_text = "Как можно выйти из тюрьмы: оба способа, только штраф или только карта."
	grid.add_child(_h("Тюрьма", _jail_rule))
	_jail_fine = _spin(0, 10000, 50, "Штраф тюрьмы", "Сколько стоит выйти из тюрьмы за деньги.")
	grid.add_child(_h("Штраф тюрьмы", _jail_fine))

	_free_parking = OptionButton.new()
	_free_parking.add_item("выкл"); _free_parking.add_item("вкл")
	_free_parking.selected = 0
	_free_parking.tooltip_text = "Собирать ли налоги в «Бесплатную стоянку» и отдавать их приземлившемуся."
	grid.add_child(_h("Беспл. стоянка", _free_parking))
	_doubles = CheckButton.new(); _doubles.text = "дубли"
	_doubles.button_pressed = true
	_doubles.tooltip_text = "Повторный ход при выпадении дублей."
	grid.add_child(_h("Дубли", _doubles))

	_triple_doubles = CheckButton.new(); _triple_doubles.text = "3 дубля → тюрьма"
	_triple_doubles.button_pressed = true
	_triple_doubles.tooltip_text = "Три дубля подряд отправляют в тюрьму."
	grid.add_child(_h("3 дубля → тюрьма", _triple_doubles))
	_auctions = OptionButton.new()
	_auctions.add_item("вкл"); _auctions.add_item("выкл")
	_auctions.selected = 0
	_auctions.tooltip_text = "Проводить ли аукцион, когда игрок отказывается покупать клетку."
	grid.add_child(_h("Аукционы", _auctions))

	_housing = CheckButton.new(); _housing.text = "застройка"
	_housing.button_pressed = true
	_housing.tooltip_text = "Разрешить строительство домов и отелей."
	grid.add_child(_h("Застройка", _housing))
	_even_build = CheckButton.new(); _even_build.text = "ровная застройка"
	_even_build.button_pressed = true
	_even_build.tooltip_text = "Строить можно только равномерно по группе."
	grid.add_child(_h("Ровная застройка", _even_build))

	_monopoly_x2 = CheckButton.new(); _monopoly_x2.text = "монополия ×2"
	_monopoly_x2.button_pressed = true
	_monopoly_x2.tooltip_text = "Владелец всей группы получает двойную аренду."
	grid.add_child(_h("Монополия ×2", _monopoly_x2))
	_mortgage = CheckButton.new(); _mortgage.text = "залог"
	_mortgage.button_pressed = true
	_mortgage.tooltip_text = "Разрешить залог клеток."
	grid.add_child(_h("Залог", _mortgage))

	_loan_pct = _spin(0, 100, 50, "Залог %", "Какой процент стоимости даёт залог.")
	grid.add_child(_h("Залог %", _loan_pct))
	_repay_pct = _spin(0, 300, 110, "Выкуп %", "Какой процент стоимости стоит выкуп залога.")
	grid.add_child(_h("Выкуп %", _repay_pct))

	_trades = CheckButton.new(); _trades.text = "торги"
	_trades.button_pressed = true
	_trades.tooltip_text = "Разрешить сделки между игроками."
	grid.add_child(_h("Торги", _trades))
	_ai_aggression = _spin(0, 100, 50, "Агрессия ИИ", "Насколько агрессивно ИИ торгуется и строит.")
	grid.add_child(_h("Агрессия ИИ", _ai_aggression))

func _build_tempo_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Темп")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_turn_timer = _seconds_option([0, 5, 10, 15, 20, 30, 45, 60], 30)
	_turn_timer.tooltip_text = "Сколько секунд у игрока на ход. 0 = без лимита."
	grid.add_child(_h("Таймер хода", _turn_timer))
	_auction_timer = _seconds_option([0, 5, 8, 10, 12, 15, 20], 15)
	_auction_timer.tooltip_text = "Сколько секунд на ставку в аукционе. 0 = без лимита."
	grid.add_child(_h("Таймер аукциона", _auction_timer))

	_timeout_action = OptionButton.new()
	_timeout_action.add_item("авто-пас"); _timeout_action.add_item("пометить away")
	_timeout_action.selected = 0
	_timeout_action.tooltip_text = "Что делать, когда игрок не успел сходить за таймер."
	grid.add_child(_h("Тайм-аут", _timeout_action))

func _build_interface_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Интерфейс")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	tab.add_child(grid)

	_animations = CheckButton.new(); _animations.text = "анимации"
	_animations.button_pressed = true
	_animations.tooltip_text = "Плавные анимации фишек и камеры. Выключите для слабых машин."
	grid.add_child(_h("Анимации", _animations))
	_event_overlay = CheckButton.new(); _event_overlay.text = "журнал событий"
	_event_overlay.button_pressed = true
	_event_overlay.tooltip_text = "Показывать ли журнал событий поверх доски."
	grid.add_child(_h("Журнал событий", _event_overlay))

	_spectacle = CheckButton.new(); _spectacle.text = "камера-«кино»"
	_spectacle.button_pressed = false
	_spectacle.tooltip_text = "Камера, следящая за действием. По умолчанию выключена — доска всегда целиком."
	grid.add_child(_h("Камера-«кино»", _spectacle))
	_sound = CheckButton.new(); _sound.text = "звук"
	_sound.button_pressed = true
	_sound.tooltip_text = "Звуковые эффекты (кубики, тосты, таймер)."
	grid.add_child(_h("Звук", _sound))

	_language = OptionButton.new()
	_language.add_item("Русский"); _language.add_item("English")
	_language.selected = 0
	_language.tooltip_text = "Язык интерфейса (полная локализация — в фазе P5)."
	grid.add_child(_h("Язык", _language))

func _build_data_tab() -> void:
	var tab := UiTheme.vbox(8)
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, "Данные")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.label("RNG-сид (0 = случайно):", 13))
	_rng_seed = SpinBox.new()
	_rng_seed.min_value = 0
	_rng_seed.max_value = 99999
	_rng_seed.value = 0
	_rng_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rng_seed.tooltip_text = "Число для воспроизводимой партии. 0 = случайная."
	row.add_child(_rng_seed)
	tab.add_child(row)

func _h(lbl: String, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UiTheme.label(lbl, 13))
	ctl.custom_minimum_size.x = 120
	h.add_child(ctl)
	return h

func _spin(minv: int, maxv: int, def: int, _lbl: String, tip: String) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = def
	sb.tooltip_text = tip
	return sb

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

	var driver := OptionButton.new()
	for d in DRIVERS:
		driver.add_item(d)
	driver.selected = 0 if idx == 0 else 1
	driver.tooltip_text = "LOCAL = человек за этим компьютером, AI = компьютер, CHAT = чат, sdk:neuro = Neuro, sdk:evil = второй SDK (играет как ИИ)."
	if idx == 0:
		driver.disabled = true
	h.add_child(driver)

	var swatch := ColorRect.new()
	swatch.color = COLORS[idx % COLORS.size()]
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size = Vector2(20, 20)
	h.add_child(swatch)

	var name_edit := LineEdit.new()
	name_edit.text = NAMES[idx % NAMES.size()]
	name_edit.custom_minimum_size.x = 180
	name_edit.tooltip_text = "Имя игрока, отображаемое на доске и в списке."
	h.add_child(name_edit)

	var token := OptionButton.new()
	for t in TOKENS:
		token.add_item(t)
	token.selected = idx % TOKENS.size()
	token.tooltip_text = "Фишка игрока (уникальная)."
	h.add_child(token)

	var remove_btn := UiTheme.button("✕", "Удалить этого игрока из партии")
	remove_btn.custom_minimum_size = Vector2(24, 20)
	remove_btn.disabled = (idx == 0)
	remove_btn.connect("pressed", Callable(self, "_remove_row").bind(idx))
	h.add_child(remove_btn)

	_rows.append({
		"driver": driver, "name": name_edit, "color": swatch,
		"token": token, "remove_btn": remove_btn, "row": h,
	})
	_players_list.add_child(h)
	_refresh_buttons()

func _remove_row(i: int) -> void:
	if i <= 0 or i >= _rows.size():
		return
	var row: HBoxContainer = _rows[i]["row"]
	_players_list.remove_child(row)
	row.queue_free()
	_rows.remove_at(i)
	for j in _rows.size():
		var r: Dictionary = _rows[j]
		(r["num"] as Label).text = "%d." % (j + 1)
		(r["remove_btn"] as Button).disabled = (j == 0)
	_refresh_buttons()

func _collect_settings() -> Settings:
	# host role: "только наблюдаю" => the host seat (row 0) is not driven by a
	# human, it's an AI seat (observer mode). Computed at collection time —
	# we do NOT mutate the row widgets, so toggling host_role back to
	# "играю" restores the host's LOCAL seat.
	var observer: bool = (_host_role.selected == 1)
	var s = Settings.new()
	s.seat_count = _rows.size()
	s.seat_assignments = []
	var first := true
	for r in _rows:
		var drv: String = str(r["driver"].get_item_text(r["driver"].selected))
		if first and observer and drv == "LOCAL":
			drv = "AI"
		first = false
		s.seat_assignments.append({
			"driver": drv,
			"name": str(r["name"].text),
			"token_color": (r["color"] as ColorRect).color.to_html(),
			"token_id": str(r["token"].get_item_text(r["token"].selected)),
		})
	s.rng_seed = int(_rng_seed.value)
	s.starting_order = "random" if _starting_order.selected == 0 else "manual"
	s.turn_timer = _selected_seconds(_turn_timer)
	s.auction_timer = _selected_seconds(_auction_timer)
	s.free_parking = (_free_parking.selected == 1)
	s.auctions_on_refusal = (_auctions.selected == 0)
	s.animations = _animations.button_pressed
	s.event_overlay = _event_overlay.button_pressed
	s.spectacle = _spectacle.button_pressed
	s.language = "ru" if _language.selected == 0 else "en"
	s.starting_cash = int(_starting_cash.value)
	s.go_bonus = int(_go_bonus.value)
	s.jail_rule = _jail_rule.get_item_text(_jail_rule.selected).to_lower()
	s.jail_fine = int(_jail_fine.value)
	s.doubles = _doubles.button_pressed
	s.triple_doubles_to_jail = _triple_doubles.button_pressed
	s.housing = _housing.button_pressed
	s.even_build = _even_build.button_pressed
	s.monopoly_rent_x2 = _monopoly_x2.button_pressed
	s.mortgage = _mortgage.button_pressed
	s.mortgage_loan_pct = int(_loan_pct.value)
	s.mortgage_repay_pct = int(_repay_pct.value)
	s.trades = _trades.button_pressed
	s.ai_aggression = int(_ai_aggression.value)
	s.timeout_action = "auto-pass" if _timeout_action.selected == 0 else "mark-away"
	return s

func _selected_seconds(o: OptionButton) -> int:
	var item: int = o.selected
	if item < 0:
		return 0
	var txt: String = o.get_item_text(item)
	if txt == "нет лимита":
		return 0
	return int(txt.trim_suffix("с"))

func _validation_error() -> String:
	if _rows.size() < 2:
		return "Нужно минимум 2 игрока."
	var names := {}
	var colors := {}
	var tokens := {}
	for r in _rows:
		var nm: String = str(r["name"].text).strip_edges()
		if nm == "":
			return "Имя игрока не может быть пустым."
		if names.has(nm):
			return "Имена игроков должны быть уникальными."
		names[nm] = true
		var col: String = (r["color"] as ColorRect).color.to_html()
		if colors.has(col):
			return "Цвета игроков должны быть уникальными."
		colors[col] = true
		var tok: String = str(r["token"].get_item_text(r["token"].selected))
		if tokens.has(tok):
			return "Фишки игроков должны быть уникальными."
		tokens[tok] = true
	return ""

func _refresh_buttons() -> void:
	var err: String = _validation_error()
	_status_lbl.text = err
	_start_btn.disabled = err != ""
	_apply_btn.disabled = err != ""
	_start_btn.tooltip_text = err if err != "" else "Начать партию с выбранными игроками и настройками"
	_apply_btn.tooltip_text = err if err != "" else "Пересобрать движок с этими настройками (нужен рестарт)"
	_start_btn.visible = _pre_game
	_apply_btn.visible = not _pre_game

func _start_pressed() -> void:
	var s := _collect_settings()
	var seats: Array = SeatConfig.from_settings(s)
	started.emit(s, seats)

func _apply_pressed() -> void:
	var s := _collect_settings()
	var seats: Array = SeatConfig.from_settings(s)
	apply_requested.emit(s, seats)

func _on_close() -> void:
	closed.emit()

func _show_rules() -> void:
	var s := _collect_settings()
	var lines: Array[String] = []
	lines.append("ПРАВИЛА (по текущим настройкам)")
	lines.append("")
	lines.append("Стартовый капитал: $%d" % s.starting_cash)
	lines.append("Бонус за GO: $%d" % s.go_bonus)
	lines.append("Тюрьма: %s (штраф $%d)" % [s.jail_rule, s.jail_fine])
	lines.append("Бесплатная стоянка: %s" % ("вкл" if s.free_parking else "выкл"))
	lines.append("Дубли: %s" % ("вкл" if s.doubles else "выкл"))
	lines.append("Тройные дубли → тюрьма: %s" % ("вкл" if s.triple_doubles_to_jail else "выкл"))
	lines.append("Аукционы при отказе: %s" % ("вкл" if s.auctions_on_refusal else "выкл"))
	lines.append("Строительство: %s" % ("вкл" if s.housing else "выкл"))
	lines.append("Равномерная застройка: %s" % ("вкл" if s.even_build else "выкл"))
	lines.append("Монополия ×2 аренда: %s" % ("вкл" if s.monopoly_rent_x2 else "выкл"))
	lines.append("Залог: %s (%d%% / %d%%)" % [("вкл" if s.mortgage else "выкл"), s.mortgage_loan_pct, s.mortgage_repay_pct])
	lines.append("Торги: %s" % ("вкл" if s.trades else "выкл"))
	lines.append("Таймер хода: %dс" % s.turn_timer)
	lines.append("Таймер аукциона: %dс" % s.auction_timer)
	lines.append("Тайм-аут: %s" % s.timeout_action)
	lines.append("Агрессия ИИ: %d" % s.ai_aggression)
	_show_rules_modal("\n".join(lines))

func _show_rules_modal(text: String) -> void:
	var popup := AcceptDialog.new()
	popup.title = "ПРАВИЛА"
	popup.dialog_text = text
	popup.ok_button_text = "OK"
	popup.size = Vector2(520, 420)
	add_child(popup)
	popup.popup_centered()

func _preset_classic() -> void:
	_reset_all()

func _preset_fast() -> void:
	_reset_all()
	_turn_timer.selected = _index_of_seconds(_turn_timer, 10)
	_starting_cash.value = 1000

func _preset_hard() -> void:
	_reset_all()
	_mortgage.button_pressed = false
	_trades.button_pressed = false
	_ai_aggression.value = 80

func _index_of_seconds(o: OptionButton, target: int) -> int:
	for i in o.item_count:
		var txt: String = o.get_item_text(i)
		if txt == str(target) + "с":
			return i
	return 0

func _reset_all() -> void:
	_starting_cash.value = 1500
	_go_bonus.value = 200
	_jail_rule.selected = 0
	_jail_fine.value = 50
	_free_parking.selected = 0
	_doubles.button_pressed = true
	_triple_doubles.button_pressed = true
	_auctions.selected = 0
	_housing.button_pressed = true
	_even_build.button_pressed = true
	_monopoly_x2.button_pressed = true
	_mortgage.button_pressed = true
	_loan_pct.value = 50
	_repay_pct.value = 110
	_trades.button_pressed = true
	_ai_aggression.value = 50
	_turn_timer.selected = _index_of_seconds(_turn_timer, 30)
	_auction_timer.selected = _index_of_seconds(_auction_timer, 15)
	_timeout_action.selected = 0
	_animations.button_pressed = true
	_event_overlay.button_pressed = true
	_spectacle.button_pressed = false
	_sound.button_pressed = true
	_language.selected = 0
	_rng_seed.value = 0
	_host_role.selected = 0
	_starting_order.selected = 0
	_refresh_buttons()
