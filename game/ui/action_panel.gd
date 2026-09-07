class_name ActionPanel
extends PanelContainer
## Bottom action bar: shows ONLY the legal actions for the current seat
## (engine.legal_actions), as buttons that call seat_manager.push_intent.
## For a human LOCAL seat it waits for these clicks; AI/CHAT seats self-drive
## in the manager and show read-only "AI..." status. Also hosts a small
## live event-feed on the right (the stream overlay moved here from mid-screen).

signal action_requested(action: String, params: Dictionary)
signal start_requested

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

var _btn_row: HBoxContainer
var _hint: Label
var _status: Label
var _current_pid := -1
var _last_legal: Array = []   # cache so we only rebuild buttons when the set changes
var _cold := false
var _observer := false        # P4 §7: thin status bar, no buttons

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

## Cold state (pre-game): show a single START button that opens the settings
## overlay. No engine yet.
func set_cold(v: bool) -> void:
	_cold = v
	if _btn_row == null:
		return
	# clear any existing buttons
	for c in _btn_row.get_children():
		_btn_row.remove_child(c); c.queue_free()
	_last_legal = []
	if v:
		_status.text = I18n.t("act.cold_status")
		_hint.text = ""
		var start := UiTheme.button_accent(I18n.t("act.start_btn"), I18n.t("act.start_tip"))
		start.custom_minimum_size.y = 40
		start.connect("pressed", Callable(self, "_on_start"))
		_btn_row.add_child(start)
	else:
		_status.text = ""

func _on_start() -> void:
	start_requested.emit()

## P4 §7: observer mode — the panel collapses to a thin status bar: no buttons,
## the hint line is hidden, and the status line shows the current decision
## holder (fed by game_view through sync's holder name in proj-like data).
func set_observer(v: bool) -> void:
	_observer = v
	if v:
		_clear_buttons()
		_last_legal = []
	_hint.visible = not v

func _clear_buttons() -> void:
	if _btn_row == null:
		return
	for c in _btn_row.get_children():
		_btn_row.remove_child(c); c.queue_free()

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

	if _observer:
		# thin spectator status bar: whose decision is pending + timer hint
		var holder_txt: String = nm if pid >= 0 else "—"
		var window := float(proj.get("timer_window", 0.0))
		var elapsed := float(proj.get("timer_elapsed", 0.0))
		var timer_txt := ""
		if window > 0.0:
			timer_txt = I18n.t("act.observer_timer", [maxi(0, int(window - elapsed))])
		var drv: String = str(seat.input_driver if seat != null else "")
		var drv_txt := ""
		if drv == "SDK":
			drv_txt = I18n.t("act.observer_sdk")
		_status.text = I18n.t("act.observer_status", [
			str(proj.get("phase", "")), holder_txt, drv_txt, timer_txt])
		_clear_buttons()
		return

	if not human:
		_status.text = I18n.t("act.ai_status", [nm])
		_hint.text = ""
		# clear buttons when control passes to an AI seat
		_clear_buttons()
		return

	var drv: String = str(seat.input_driver if seat != null else "AI")
	_status.text = I18n.t("act.human_status", [nm])

	# only rebuild buttons when the legal set actually changed (avoids hover lag)
	if _legal_changed(legal):
		_clear_buttons()
		for act in legal:
			# risk-table fix: legal_actions always lists respond_trade on a
			# TURN_START — show the button only when a trade is really pending
			# for ANY recipient (a LOCAL player may be asked to respond during
			# another player's turn).
			if act == "respond_trade" and str(proj.get("pending", {}).get("type", "")) != "trade":
				continue
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
			return UiTheme.button_accent(I18n.t("act.roll"), I18n.t("act.roll_tip"))
		"buy":
			return UiTheme.button_accent(I18n.t("act.buy"), I18n.t("act.buy_tip"))
		"pass":
			var label := I18n.t("act.pass")
			if str(proj.get("pending", {}).get("type", "") == "purchase"):
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
	if pending.get("type", "") == "trade":
		return I18n.t("act.hint_trade")
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
