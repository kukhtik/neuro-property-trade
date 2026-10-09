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
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	# The mockup's bar is one ROW: buttons at 46px (`#act button`), the primary at 50px with
	# 26px of padding (`#act button.pri`), and a 72px band overall. Ours stacked a status line
	# and a hint above a 40px row, which is why it read as a form rather than a control bar.
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 14)
	outer.add_theme_constant_override("margin_right", 14)
	outer.add_theme_constant_override("margin_top", 0)
	outer.add_theme_constant_override("margin_bottom", 0)
	add_child(outer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_child(row)

	# button row: the buttons come first, as in the mockup
	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 10)
	_btn_row.custom_minimum_size.y = 46   # `#act button`
	row.add_child(_btn_row)

	# status line (which seat + phase hint) sits to the RIGHT of the controls
	_status = UiTheme.label("", 12, UiTheme.COL().text_dim)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_status)

	_v = UiTheme.vbox(6)
	_hint = UiTheme.label("", 11, UiTheme.COL().text_dim)
	_hint.visible = false   # the mockup's hint lives in the status area, not on its own line

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
		start.custom_minimum_size.y = 50   # `#act button.pri`
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
	_legal_now = legal
	_human_now = human

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
		# CS-3: localize the phase name (phase.* keys), fall back to the raw enum.
		var ph: String = str(proj.get("phase", ""))
		var ph_lbl: String = I18n.t("phase." + ph)
		if ph_lbl.begins_with("{phase."):
			ph_lbl = ph
		_status.text = I18n.t("act.observer_status", [
			ph_lbl, holder_txt, drv_txt, timer_txt])
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

	# THE BAR ALWAYS SHOWS EVERY CONTROL, greyed out when it does not apply.
	#
	# The mockup never hides a button: it renders all eight and sets `disabled` on the ones
	# the current state forbids (`B[0].disabled = !ok("roll")`). That is a different language
	# from ours — we built only the legal actions, so at an AI seat the bar went completely
	# empty and the whole strip read as broken. A control that is visibly THERE but unusable
	# tells the player what the game is; a missing one tells them nothing.
	_sync_buttons(pid, legal, human, proj)

	# contextual hint
	_hint.text = _context_hint(proj)


## The mockup's control set, in its own order.
const BAR_ACTIONS := [
	"roll", "buy", "pass", "build_house", "sell_house", "mortgage_property",
	"propose_trade", "end_turn",
]

## Rebuild the bar so every action is present, enabled only when legal.
##
## Rebuilt only when the ENABLED SET changes, so hovering does not flicker.
func _sync_buttons(pid: int, legal: Array, human: bool, proj: Dictionary) -> void:
	if _btn_row == null or _observer:
		return
	var enabled := {}
	for a in legal:
		enabled[str(a)] = true
	# a trade response only makes sense while a trade is actually pending
	if str(proj.get("pending", {}).get("type", "")) != "trade":
		enabled.erase("respond_trade")

	var want := BAR_ACTIONS.duplicate()
	if enabled.has("respond_trade"):
		want.insert(2, "respond_trade")

	if not human:
		# at an AI seat nothing is pressable, but the controls stay visible
		enabled.clear()

	var key := []
	for a in want:
		key.append(a if enabled.has(a) else "-")
	if key == _last_legal and _btn_row.get_child_count() > 0:
		return
	_last_legal = key
	_clear_buttons()

	for act in want:
		var live: bool = enabled.has(act)
		var btn = _make_button(act, proj, pid, live)
		if btn == null:
			continue
		if live:
			btn.connect("pressed", Callable(self, "_on_pressed").bind(act))
		_btn_row.add_child(btn)

func _legal_changed(legal: Array) -> bool:
	if legal.size() != _last_legal.size():
		return true
	for i in legal.size():
		if legal[i] != _last_legal[i]:
			return true
	return false

## The mockup prints the hotkey inside the button (`Купить B`, `Конец хода N`).
const HOTKEY := {"buy": "B", "end_turn": "N"}

## The keys the player can actually press right now, and whether this seat is the human one.
## A hotkey must honour the SAME gate as the button: firing `buy` while it is greyed would send
## an intent the engine rejects, and the player sees nothing happen at all.
var _legal_now: Array = []
var _human_now := false

func _make_button(act: String, proj: Dictionary, pid: int, live: bool = true) -> Button:
	var b := _button_for(act, proj, pid)
	# THE KEY HINT IS ALWAYS SHOWN, even on a disabled button: the mockup prints `Купить B` on
	# the control whether or not it is pressable, and a player who can see the key on a greyed
	# button knows what it will do once the turn allows it.
	if b != null:
		var key: String = str(HOTKEY.get(act, ""))
		if key != "" and b.get_node_or_null("Hotkey") == null:
			b.add_child(_hotkey_badge(key))
	if b != null and not live:
		# present but not pressable: the mockup sets `disabled`, it does not remove the
		# control, so the player can see what exists and what is currently open to them
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
	return b


func _button_for(act: String, proj: Dictionary, pid: int) -> Button:
	match act:
		"end_turn":
			return UiTheme.button(I18n.t("act.end_turn"), I18n.t("act.end_turn_tip"))
		"roll":
			return UiTheme.button_accent(I18n.t("act.roll"), I18n.t("act.roll_tip"))
		"buy":
			# THE MOCKUP PUTS THE PRICE ON THE BUTTON (`a.buy|Купить ¤{a}`). "Купить" alone makes
			# the player look elsewhere for a number they are about to commit to.
			var buy_lbl := I18n.t("act.buy")
			var pend: Dictionary = proj.get("pending", {})
			if str(pend.get("type", "")) == "purchase":
				var tinf: Dictionary = _tile_info(proj, int(pend.get("tile", -1)))
				var price: int = int(tinf.get("cost", 0))
				if price > 0:
					buy_lbl = I18n.t("act.buy_price", [price])
			return UiTheme.button_accent(buy_lbl, I18n.t("act.buy_tip"))
		"pass":
			var label := I18n.t("act.pass")
			# `str(a == b)` compares FIRST and then stringifies the bool, so this read "False", and a
			# non-empty string is TRUE in GDScript — the button was relabelled "don't buy" on every
			# single turn, whatever the pending action actually was. `str()` belongs around the value.
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


## A small key hint tucked into the button's right edge.
func _hotkey_badge(key: String) -> Label:
	var l := UiTheme.label(key, 10, UiTheme.COL().text_dim)
	l.name = "Hotkey"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -20.0
	l.offset_right = -7.0
	l.offset_top = 0.0
	l.offset_bottom = 0.0
	l.anchor_top = 0.0
	l.anchor_bottom = 1.0
	return l


## Hotkeys: B buys, N ends the turn — the two the mockup marks. F12 (admin) lives in main.gd.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var act := ""
	match (event as InputEventKey).keycode:
		KEY_B:
			act = "buy"
		KEY_N, KEY_END:
			act = "end_turn"
	if act == "":
		return
	if not _human_now or not _legal_now.has(act):
		return
	accept_event()
	action_requested.emit(act, {})
