class_name ModalHost
extends Control
## A single full-screen overlay that hosts a modal panel. Content is swapped
## via open_* methods; each emits a result via signals. Transparent clickaway
## closes it. Shape-only widgets (theme).

const UiTheme := preload("res://ui/theme.gd")

signal build_requested(tile: int, op: String)
signal trade_proposed(to: int, give_tiles: Array, give_cash: int, want_tiles: Array, want_cash: int)
signal trade_responded(accept: bool)
signal auction_bid(amount: int)
signal auction_pass()
signal sound_toggled(category: String, on: bool)

var _panel: PanelContainer
var _content: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# dim background under the modal
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# clicking the dim closes (clickaway)
	bg.connect("gui_input", Callable(self, "_on_dim_input"))

func open_build(tile: int, proj: Dictionary, seat_name: String) -> void:
	var t := _find_tile(proj, tile)
	_show()
	_content = UiTheme.vbox(10)
	var body := VBoxContainer.new()
	body.add_child(_heading("СТРОЙКА / ЗАЛОГ"))
	body.add_child(UiTheme.label("Тайл: «%s» (%d)" % [t.get("name", tile), tile], 14))
	body.add_child(UiTheme.label("Дом: %s  ·  стоимость дома $%s" % [
		str(t.get("houses", 0)), str(t.get("house_cost", 0))], 13, UiTheme.COL.text_dim))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var btn_build := UiTheme.button_accent("СТРОИТЬ", "Построить дом на этой клетке (нужна вся группа)")
	btn_build.connect("pressed", Callable(self, "_emit_build").bind(tile, "build_house"))
	row.add_child(btn_build)
	var btn_sell := UiTheme.button("ПРОДАТЬ дом", "Продать дом с этой клетки")
	btn_sell.connect("pressed", Callable(self, "_emit_build").bind(tile, "sell_house"))
	row.add_child(btn_sell)
	var btn_mort := UiTheme.button("ЗАЛОЖИТЬ", "Заложить клетку и получить 50% её стоимости")
	btn_mort.connect("pressed", Callable(self, "_emit_build").bind(tile, "mortgage_property"))
	row.add_child(btn_mort)
	var btn_unmort := UiTheme.button("ВЫКУПИТЬ", "Выкупить заложенную клетку (110% стоимости)")
	btn_unmort.connect("pressed", Callable(self, "_emit_build").bind(tile, "unmortgage_property"))
	row.add_child(btn_unmort)
	body.add_child(row)
	_panelize(body)

func open_trade(proj: Dictionary, seats: Array, proposer_pid: int) -> void:
	# proposer (the human) builds an offer to one other player.
	_show()
	var recipient: OptionButton = OptionButton.new()
	recipient.tooltip_text = "Кому вы предлагаете сделку."
	for s in seats:
		if int(s.pid) != proposer_pid:
			recipient.add_item(str(s.name), int(s.pid))

	var body := UiTheme.vbox(8)
	body.add_child(_heading("ТОРГ"))

	var to_row := HBoxContainer.new()
	to_row.add_theme_constant_override("separation", 8)
	to_row.add_child(UiTheme.label("Получатель:"))
	to_row.add_child(recipient)
	body.add_child(to_row)

	body.add_child(UiTheme.label("Даёте (ваши тайлы выбирайте кликом по доске):", 12, UiTheme.COL.text_dim))
	var give_list := UiTheme.label("— выберите:  [ СТРОЙКА/ЗАЛОГ выбирает тайл ]", 12)
	body.add_child(give_list)

	body.add_child(UiTheme.label("Просите (его тайлы):", 12, UiTheme.COL.text_dim))
	var want_list := UiTheme.label("— укажите тайлы / деньги ниже", 12)
	body.add_child(want_list)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	row.add_child(UiTheme.label("Даю $"))
	var give_cash := SpinBox.new()
	give_cash.min_value = 0; give_cash.max_value = 99999; give_cash.value = 0
	give_cash.tooltip_text = "Сколько денег вы отдаёте в сделке."
	row.add_child(give_cash)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	body.add_child(row2)
	row2.add_child(UiTheme.label("Хочу $"))
	var want_cash := SpinBox.new()
	want_cash.min_value = 0; want_cash.max_value = 99999; want_cash.value = 0
	want_cash.tooltip_text = "Сколько денег вы просите в сделке."
	row2.add_child(want_cash)

	# NOTE: MVP trade flow selects give_tiles from clicked tiles; want_tiles here
	# are simplified to cash + tiles selected while in trade mode. For the MVP
	# shell we propose with the selected give_tiles (tracked in game_view) and
	# want = cash + any want-tiles selected. Simpler path below:
	var give_tiles: Array = []
	var want_tiles: Array = []
	# (real multi-tile trade UI is a followup; MVP passes empty tile arrays and
	#  cash amounts — engine allows this.)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var ok := UiTheme.button_accent("ПРЕДЛОЖИТЬ", "Отправить это предложение выбранному игроку")
	ok.connect("pressed", Callable(self, "_emit_trade").bind(
		recipient, give_cash, want_cash, give_tiles, want_tiles))
	btn_row.add_child(ok)
	var cancel := UiTheme.button("Отмена", "Закрыть окно без отправки")
	cancel.connect("pressed", Callable(self, "close"))
	btn_row.add_child(cancel)
	body.add_child(btn_row)
	_panelize(body)

func open_trade_response(proj: Dictionary, seats: Array) -> void:
	_show()
	var pending: Dictionary = proj.get("pending", {})
	var proposer: int = int(pending.get("proposer", -1))
	var recipient: int = int(pending.get("recipient", -1))
	var give: Array = pending.get("give_tiles", [])
	var want: Array = pending.get("want_tiles", [])
	var gcash: int = int(pending.get("give_cash", 0))
	var wcash: int = int(pending.get("want_cash", 0))

	var pn := _name_of(seats, proposer)
	var rn := _name_of(seats, recipient)
	var body := UiTheme.vbox(8)
	body.add_child(_heading("ВХОДЯЩАЯ СДЕЛКА"))
	body.add_child(UiTheme.label("%s предлагает %s:" % [pn, rn], 14))
	body.add_child(UiTheme.label("Даёт: $%d + %d тайл(а)   ·   Просит: $%d + %d тайл(а)" % [
		gcash, give.size(), wcash, want.size()], 13, UiTheme.COL.text_dim))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var yes := UiTheme.button_accent("ПРИНЯТЬ", "Принять предложение — обмен выполнится")
	yes.connect("pressed", Callable(self, "_emit_trade_response").bind(true))
	row.add_child(yes)
	var no := UiTheme.button("ОТКЛОНИТЬ", "Отклонить предложение — сделка не состоится")
	no.connect("pressed", Callable(self, "_emit_trade_response").bind(false))
	row.add_child(no)
	body.add_child(row)
	_panelize(body)

func open_auction(proj: Dictionary, seats: Array) -> void:
	_show()
	var pending: Dictionary = proj.get("pending", {})
	var tile: int = int(pending.get("tile", -1))
	var high: int = int(pending.get("high", -1))
	var t := _find_tile(proj, tile)
	var body := UiTheme.vbox(8)
	body.add_child(_heading("АУКЦИОН"))
	body.add_child(UiTheme.label("Лот: «%s»" % t.get("name", tile), 14))
	body.add_child(UiTheme.label("Текущая ставка: $%d" % high if high > 0 else "Ставок ещё нет", 13, UiTheme.COL.text_dim))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.label("Ставка $"))
	var amt := SpinBox.new()
	amt.min_value = high + 1
	amt.max_value = 99999
	amt.value = high + 1
	amt.tooltip_text = "Ваша ставка. Должна быть выше текущей."
	row.add_child(amt)
	var bid := UiTheme.button_accent("СТАВКА", "Сделать ставку на эту клетку")
	bid.connect("pressed", Callable(self, "_emit_bid").bind(amt))
	row.add_child(bid)
	var apos := UiTheme.button("ПАСС", "Выйти из аукциона — больше не участвуете в этом лоте")
	apos.connect("pressed", Callable(self, "_emit_auction_pass"))
	row.add_child(apos)
	body.add_child(row)
	_panelize(body)

func show_message(title: String, msg: String) -> void:
	_show()
	var body := UiTheme.vbox(8)
	body.add_child(_heading(title))
	body.add_child(UiTheme.label(msg, 14))
	var ok := UiTheme.button("OK", "Закрыть это сообщение")
	ok.connect("pressed", Callable(self, "close"))
	body.add_child(ok)
	_panelize(body)

## In-game settings: per-category sound toggles + a rules button.
func open_settings(sound_cats: Array, rules_text: String) -> void:
	_show()
	var body := UiTheme.vbox(8)
	body.add_child(_heading("НАСТРОЙКИ"))

	body.add_child(UiTheme.label("ЗВУК", 13, UiTheme.COL.accent))
	for cat in sound_cats:
		var cb := CheckButton.new()
		cb.text = str(cat.get("label", ""))
		cb.button_pressed = bool(cat.get("on", true))
		cb.connect("toggled", Callable(self, "_on_sound_toggled").bind(str(cat.get("key", ""))))
		body.add_child(cb)

	var rules_btn := UiTheme.button("ПРАВИЛА", "Показать полные правила игры по текущим настройкам")
	rules_btn.connect("pressed", Callable(self, "_open_rules").bind(rules_text))
	body.add_child(rules_btn)

	var close_btn := UiTheme.button("ЗАКРЫТЬ", "Закрыть окно настроек")
	close_btn.connect("pressed", Callable(self, "close"))
	body.add_child(close_btn)
	_panelize(body)

func _on_sound_toggled(on: bool, key: String) -> void:
	sound_toggled.emit(key, on)

func _open_rules(rules_text: String) -> void:
	# replace the settings panel with the rules text
	if _panel != null and is_instance_valid(_panel):
		_panel.free()
	_panel = null
	var body := UiTheme.vbox(8)
	body.add_child(_heading("ПРАВИЛА"))
	var txt := UiTheme.label(rules_text, 13)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(420, 300)
	body.add_child(txt)
	var back := UiTheme.button("НАЗАД", "Вернуться к настройкам")
	back.connect("pressed", Callable(self, "close"))
	body.add_child(back)
	_panelize(body)

func _heading(txt: String) -> Label:
	var h := UiTheme.label(txt, 18, UiTheme.COL.gold)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return h

func _find_tile(proj: Dictionary, idx: int) -> Dictionary:
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) == idx:
			return t
	return {}

func _name_of(seats: Array, pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	return "P%d" % pid

func _panelize(content: Control) -> void:
	_panel = UiTheme.panel()
	_panel.custom_minimum_size = Vector2(460, 0)
	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 16)
	_panel.add_child(margin)
	margin.add_child(content)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

func _show() -> void:
	visible = true

func close() -> void:
	visible = false
	if _panel != null and is_instance_valid(_panel):
		_panel.free()
	_panel = null
	_content = null

func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _emit_build(tile: int, op: String) -> void:
	build_requested.emit(tile, op)

func _emit_trade(recipient: OptionButton, give_cash: SpinBox, want_cash: SpinBox, give: Array, want: Array) -> void:
	var to: int = recipient.get_item_id(recipient.selected)
	trade_proposed.emit(to, give, int(give_cash.value), want, int(want_cash.value))

func _emit_trade_response(accept: bool) -> void:
	trade_responded.emit(accept)

func _emit_bid(amt: SpinBox) -> void:
	auction_bid.emit(int(amt.value))

func _emit_auction_pass() -> void:
	auction_pass.emit()
