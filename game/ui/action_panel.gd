extends PanelContainer
## The console (`#act`) under the board: the ticker / prompt / last-roll line and the
## control row. v3 rebuild from the prototype; buttons submit intents through the shell.

signal action_requested(action: String, params: Dictionary)
signal start_requested

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const MoneyFmt := preload("res://ui/core/money.gd")

## The mockup's control set, in its own order.
const BAR_ACTIONS := [
	"roll", "buy", "pass", "bid", "pay", "use_card", "build_house", "sell_house",
	"mortgage_property", "unmortgage_property", "propose_trade", "respond_trade", "end_turn",
]
const HOTKEY := {"buy": "B", "end_turn": "N"}

var _ticker: Label
var _hint: Label
var _lastroll: Label
var _btn_row: HBoxContainer
var _status: Label
var _cold := false
var _observer := false
var _last_legal: Array = []
var _human_now := false


func _init() -> void:
	custom_minimum_size.y = 96   # `--cons-h`
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 12)
	add_child(m)
	var col := UiTheme.vbox(8)
	m.add_child(col)

	var row1 := UiTheme.hbox(10)
	row1.custom_minimum_size.y = 22
	_ticker = UiTheme.label("", 12, UiTheme.COL().accent)
	_ticker.visible = false
	row1.add_child(_ticker)
	_hint = UiTheme.label_wrap("", 13, UiTheme.COL().text)
	_hint.name = "Prompt"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(_hint)
	_lastroll = UiTheme.label("", 12, UiTheme.COL().money)
	_lastroll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(_lastroll)
	col.add_child(row1)

	var row2 := UiTheme.hbox(8)
	row2.alignment = BoxContainer.ALIGNMENT_BEGIN
	_btn_row = UiTheme.hbox(8)
	_btn_row.custom_minimum_size.y = 44
	row2.add_child(_btn_row)
	_status = UiTheme.label("", 12, UiTheme.COL().text_dim)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row2.add_child(_status)
	col.add_child(row2)


func set_cold(v: bool) -> void:
	_cold = v
	_clear_buttons()
	if v:
		_status.text = ""
		_hint.text = I18n.t("act.cold_status")
		var start := UiTheme.button_accent(I18n.t("act.start_btn"), I18n.t("act.start_tip"))
		start.custom_minimum_size.y = 50
		start.connect("pressed", func() -> void: start_requested.emit())
		_btn_row.add_child(start)
	else:
		_status.text = ""


func set_observer(v: bool) -> void:
	_observer = v
	if v:
		_clear_buttons()
		_hint.visible = false


## One live line of the newest notification (replaces the prompt while it shows).
func show_ticker(text: String, kind: String = "info") -> void:
	_ticker.text = text
	_ticker.add_theme_color_override("font_color", UiTheme.COL().accent)
	_ticker.visible = true
	_hint.visible = false


func set_last_roll(d1: int, d2: int, doubles: bool) -> void:
	var suffix := " · " + I18n.t("die.doubles") if doubles else ""
	_lastroll.text = "%d + %d = %d%s" % [d1, d2, d1 + d2, suffix]


## Paint the console for the seat that must decide. `legal` = engine legal actions.
func sync(pid: int, legal: Array, human: bool, proj: Dictionary, seats: Array) -> void:
	if _cold:
		return
	_last_legal = legal
	_human_now = human
	var nm := "P%d" % pid
	for s in seats:
		if int(s.pid) == pid:
			nm = str(s.name)
	_clear_buttons()
	if _observer:
		_status.text = I18n.t("act.observer_status", [str(proj.get("phase", "")), nm, "", ""])
		return
	if not human:
		_status.text = I18n.t("act.ai_status", [nm])
		_hint.text = I18n.t("act.ai_status", [nm])
		return
	_status.text = I18n.t("act.human_status", [nm])
	# the compact ticker (notification line) steps aside for the player's own prompt
	_ticker.visible = false
	# the console shows the control SET for what is being decided: the engine's legal
	# actions, in the mockup's order. It used to render all thirteen at once — a 1320-px
	# minimum that pushed the whole layout past the window.
	for act in BAR_ACTIONS:
		if not legal.has(act):
			continue
		if act == "respond_trade":
			# THE ENGINE LISTS respond_trade FOR THE PROPOSER TOO, but only the RECIPIENT can
			# answer: for anyone else pressing it is a guaranteed refusal ("you are not the
			# trade recipient" / "no pending trade" - the audit measured both). Draw it only
			# where it can work.
			var pend: Dictionary = proj.get("pending", {})
			if str(pend.get("type", "")) != "trade" or int(pend.get("recipient", -1)) != pid:
				continue
		var b := _make_button(act, proj, pid, true)
		if b != null:
			_btn_row.add_child(b)
	# prompt: contexts first, then the state sentence — never empty while a match runs
	var prompt := _context_hint(proj)
	if prompt == "":
		prompt = I18n.t("act.human_status", [nm])
	_hint.text = prompt
	_hint.visible = not _ticker.visible


func _clear_buttons() -> void:
	for c in _btn_row.get_children():
		_btn_row.remove_child(c)
		c.queue_free()


func _make_button(act: String, proj: Dictionary, pid: int, live: bool) -> Button:
	var b := _button_for(act, proj, pid)
	if b == null:
		return null
	var key: String = str(HOTKEY.get(act, ""))
	if key != "":
		b.text = "%s  %s" % [b.text, key]
	if not live:
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", func() -> void: _on_pressed(act))
	return b


func _button_for(act: String, proj: Dictionary, pid: int) -> Button:
	match act:
		"end_turn":
			return UiTheme.button(I18n.t("act.end_turn"), I18n.t("act.end_turn_tip"))
		"roll":
			return UiTheme.button_accent(I18n.t("act.roll"), I18n.t("act.roll_tip"))
		"buy":
			var lbl := I18n.t("act.buy")
			var pend: Dictionary = proj.get("pending", {})
			if str(pend.get("type", "")) == "purchase":
				var t: Dictionary = _tile_info(proj, int(pend.get("tile", -1)))
				var price: int = int(t.get("cost", 0))
				if price > 0:
					lbl = I18n.t("act.buy_price", [price])
			return UiTheme.button_accent(lbl, I18n.t("act.buy_tip"))
		"pass":
			var label := I18n.t("act.pass")
			if str(proj.get("pending", {}).get("type", "")) == "purchase":
				label = I18n.t("act.no_buy")
			return UiTheme.button(label, I18n.t("act.pass_tip"))
		"bid":
			return UiTheme.button_accent(I18n.t("act.bid"), I18n.t("act.bid_tip"))
		"pay":
			return UiTheme.button(I18n.t("act.pay", [int(proj.get("pending", {}).get("fine", 50))]), I18n.t("act.pay_tip"))
		"use_card":
			return UiTheme.button(I18n.t("act.use_card"), I18n.t("act.use_card_tip"))
		"build_house":
			return UiTheme.button(I18n.t("act.build"), I18n.t("act.build_tip"))
		"sell_house":
			return UiTheme.button(I18n.t("act.sell"), I18n.t("act.sell_tip"))
		"mortgage_property":
			return UiTheme.button(I18n.t("act.mortgage"), I18n.t("act.mortgage_tip"))
		"unmortgage_property":
			return UiTheme.button(I18n.t("act.unmortgage"), I18n.t("act.unmortgage_tip"))
		"propose_trade":
			return UiTheme.button(I18n.t("act.trade"), I18n.t("act.trade_tip"))
		"respond_trade":
			return UiTheme.button_accent(I18n.t("act.respond_trade"), I18n.t("act.respond_trade_tip"))
	return null


func _context_hint(proj: Dictionary) -> String:
	var ph: String = str(proj.get("phase", ""))
	var pending: Dictionary = proj.get("pending", {})
	if ph == "PURCHASE_WAIT" and str(pending.get("type", "")) == "purchase":
		var tile: int = int(pending.get("tile", -1))
		var t: Dictionary = _tile_info(proj, tile)
		return I18n.t("act.hint_purchase", [t.get("name", I18n.t("event.tile_name", [tile])), int(t.get("cost", 0))])
	if ph == "AUCTION":
		var high: int = int(pending.get("high", -1))
		return I18n.t("act.hint_auction", [high]) if high > 0 else I18n.t("act.hint_auction_first")
	if str(pending.get("type", "")) == "trade":
		return I18n.t("act.hint_trade")
	return ""


func _tile_info(proj: Dictionary, idx: int) -> Dictionary:
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) == idx:
			return t
	return {}


func _on_pressed(act: String) -> void:
	action_requested.emit(act, {})


func retranslate() -> void:
	_status.text = ""
