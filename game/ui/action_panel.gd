class_name ActionPanel
extends PanelContainer
## Bottom action bar: shows ONLY the legal actions for the current seat
## (engine.legal_actions), as buttons that call seat_manager.push_intent.
## For a human LOCAL seat it waits for these clicks; AI/CHAT seats self-drive
## in the manager and show read-only "AI..." status. Also hosts a small
## live event-feed on the right (the stream overlay moved here from mid-screen).

signal action_requested(action: String, params: Dictionary)

const UiTheme := preload("res://ui/theme.gd")

var _btn_row: HBoxContainer
var _hint: Label
var _status: Label
var _current_pid := -1
var _last_legal: Array = []   # cache so we only rebuild buttons when the set changes

func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL.panel, UiTheme.COL.border, 1, 0))
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 10)
	add_child(outer)
	_v = UiTheme.vbox(6)
	outer.add_child(_v)

	# status line (which seat + phase hint)
	_status = UiTheme.label("", 13, UiTheme.COL.text_dim)
	_v.add_child(_status)

	# button row
	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 8)
	_btn_row.custom_minimum_size.y = 40
	_v.add_child(_btn_row)

	_hint = UiTheme.label("", 12, UiTheme.COL.text_dim)
	_v.add_child(_hint)

var _v: VBoxContainer

## Rebuild buttons for the given legal action names of a seat. `pid` is the
## seat whose decisions these resolve. `human` true => interactive; false =>
## read-only status (AI/CHAT auto-drive). `extra` is a dict describing the
## decision context (pending purchase/auction/etc) for richer buttons.
func sync(pid: int, legal: Array, human: bool, proj: Dictionary, seats: Array) -> void:
	_current_pid = pid

	var seat = null
	for s in seats:
		if int(s.pid) == pid:
			seat = s
	var nm: String = str(seat.name if seat != null else ("P%d" % pid))

	if not human:
		_status.text = "%s: управляется ИИ — ход выполняется автоматически" % nm
		_hint.text = ""
		# clear buttons when control passes to an AI seat
		if _btn_row.get_child_count() > 0:
			for c in _btn_row.get_children():
				_btn_row.remove_child(c); c.queue_free()
		return

	var drv: String = str(seat.input_driver if seat != null else "AI")
	_status.text = "%s  ·  ваш ход — выберите действие" % nm

	# only rebuild buttons when the legal set actually changed (avoids hover lag)
	if _legal_changed(legal):
		for c in _btn_row.get_children():
			_btn_row.remove_child(c); c.queue_free()
		for act in legal:
			var btn = _make_button(act, proj, pid)
			if btn != null:
				btn.connect("pressed", Callable(self, "_on_pressed").bind(act))
				_btn_row.add_child(btn)
		_last_legal = legal.duplicate()

	# contextual hint
	_hint.text = _context_hint(proj)

func _legal_changed(legal: Array) -> bool:
	if legal.size() != _last_legal.size():
		return true
	for i in legal.size():
		if legal[i] != _last_legal[i]:
			return true
	return false

func _make_button(act: String, proj: Dictionary, pid: int) -> Button:
	match act:
		"roll":
			return UiTheme.button_accent("БРОСИТЬ КУБ", "Бросить кубики и передвинуть фишку на выпавшее число клеток")
		"buy":
			return UiTheme.button_accent("КУПИТЬ", "Купить эту клетку за указанную цену")
		"pass":
			var label := "ПАСС"
			if str(proj.get("pending", {}).get("type", "") == "purchase"):
				label = "НЕ покупать"
			return UiTheme.button(label, "Не покупать клетку — она уйдёт на аукцион")
		"bid":
			return UiTheme.button_accent("СТАВКА", "Сделать ставку на аукционе за эту клетку")
		"pay":
			return UiTheme.button("ОПЛАТИТЬ $%d" % int(proj.get("pending", {}).get("fine", 50)), "Заплатить штраф и выйти из тюрьмы")
		"use_card":
			return UiTheme.button("КАРТА выхода", "Использовать карту «Выход из тюрьмы»")
		"build_house":
			return UiTheme.button("СТРОИТЬ", "Построить дом на выбранной клетке (нужна вся группа)")
		"sell_house":
			return UiTheme.button("ПРОДАТЬ дом", "Продать дом с выбранной клетки")
		"mortgage_property":
			return UiTheme.button("ЗАЛОЖИТЬ", "Заложить клетку и получить 50% её стоимости")
		"unmortgage_property":
			return UiTheme.button("ВЫКУПИТЬ", "Выкупить заложенную клетку (110% стоимости)")
		"propose_trade":
			return UiTheme.button("ТОРГ", "Предложить сделку другому игроку (тайлы и/или деньги)")
		"respond_trade":
			return UiTheme.button_accent("ОТВЕТИТЬ на сделку", "Принять или отклонить входящее предложение сделки")
	return null

func _context_hint(proj: Dictionary) -> String:
	var ph: String = str(proj.get("phase", ""))
	var pending: Dictionary = proj.get("pending", {})
	if ph == "PURCHASE_WAIT" and str(pending.get("type", "")) == "purchase":
		var tile: int = int(pending.get("tile", -1))
		var t: Dictionary = _tile_info(proj, tile)
		return "Можно купить «%s» за $%d или не покупать" % [t.get("name", "тайл %d" % tile), int(t.get("cost", 0))]
	if ph == "AUCTION":
		var high: int = int(pending.get("high", -1))
		return "Аукцион — текущая ставка $%d" % high if high > 0 else "Аукцион — сделайте первую ставку"
	if pending.get("type", "") == "trade":
		return "Входящее предложение — принять или отклонить"
	return ""

func _tile_info(proj: Dictionary, idx: int) -> Dictionary:
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) == idx:
			return t
	return {}

func _on_pressed(act: String) -> void:
	match act:
		"roll", "buy", "pass", "pay", "use_card":
			action_requested.emit(act, {})
		"respond_trade":
			# open a small responder modal handled by game_view
			action_requested.emit("respond_trade", {})
		"build_house", "sell_house", "mortgage_property", "unmortgage_property", "propose_trade", "bid":
			# these need a tile/params selection — open the relevant modal
			action_requested.emit(act, {})
