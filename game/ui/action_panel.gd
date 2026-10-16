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
## `end_turn` is NOT here: engine.legal_actions never lists it - turns advance by
## themselves (_end_turn_or_continue). The badge promised a button that never appears;
## the handler still supports it if the engine ever grows the action (HG-13).
const HOTKEY := {"buy": "B"}

var _ticker: Label
var _hint: Label
var _lastroll: Label
var _btn_row: HFlowContainer
var _status: Label
var _cold := false
var _observer := false
var _last_legal: Array = []
var _human_now := false
## last sync() arguments - a locale switch re-renders the console from them (SG-08)
var _last_args: Array = []
## The width the full management row needs on one line (measured in RU, the longer language). Above
## this the strip reserves it; below it the row wraps by itself rather than widening the window.
const ROW_WANTS := 660.0


## Keep the strip one line WHEN THERE IS ROOM, and let it wrap when there is not - without ever
## pushing the window wider.
##
## WHY THE WINDOW AND NOT `size.x`: this panel's own width is already inflated by the minimum it is
## about to set - measuring it is circular, and it reported 949 and granted a 660px row that then
## forced the whole frame to 1577 (SG-02). The FRAME is the one honest number here: it is what the
## user actually has.
func _fit_row_min() -> void:
	if _btn_row == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var frame_w: float = vp.get_visible_rect().size.x
	if frame_w <= 1.0:
		return          # not laid out yet: leave the default, do not guess
	# the room the row may claim: the frame, minus both side docks and the gaps/margins around them,
	# minus the strip's own chrome. The chrome is MEASURED, not invented: with the button row freed
	# the console still asked for 869px before the prompt/last-roll/status labels were allowed to
	# shrink (a previous revision of this line guessed "160" and the strip pushed the frame to
	# 1593px in a 1440px window). Now that those labels may clip, the console's own chrome is small
	# and this number is the docks' share only.
	var chrome: float = 268.0 + 344.0 + 8.0 + 8.0 + 16.0 + 12.0 + 60.0
	var room: float = frame_w - chrome
	_btn_row.custom_minimum_size.x = clampf(room, 0.0, ROW_WANTS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_row_min()


func _init() -> void:
	# THE CONSOLE IS A FLOATING STRIP, NOT A PANEL (owner's relayout, 16.10 evening).
	#
	# It used to be a 96px `--cons-h` box that GREW to 362px, because its prompt is a wrapping
	# paragraph with EXPAND_FILL - and that 362px came straight out of the board's height. Measured
	# on the live tree: header 56 + console 362 = 418px of 900, leaving the board 796x449 (not even
	# square), every cell 41px, names dropped, 12 cells blank. The owner's report ("панели абсурдно
	# огромные", "клетки пустые") is that arithmetic.
	#
	# Now it is one line: the prompt does not wrap and does not take vertical slack, so the strip is
	# as tall as its own text. The board gets the height back.
	custom_minimum_size.y = 44
	add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	add_child(m)
	var col := UiTheme.vbox(0)
	m.add_child(col)

	var row1 := UiTheme.hbox(10)
	_ticker = UiTheme.label("", 12, UiTheme.COL().accent)
	_ticker.visible = false
	row1.add_child(_ticker)
	# THE CONTROLS COME FIRST, THE PROMPT TAKES WHAT IS LEFT. The first version of this strip put the
	# EXPAND_FILL prompt first, so it ate the whole row and squeezed the button container to 132px -
	# the buttons then WRAPPED VERTICALLY and the "one-line strip" stood 300px tall, exactly the
	# waste this relayout is meant to remove. Order in an HBox is a decision, not cosmetics.
	_btn_row = HFlowContainer.new()
	_btn_row.add_theme_constant_override("h_separation", 8)
	_btn_row.add_theme_constant_override("v_separation", 4)
	# THE BUTTONS KEEP THEIR ROOM *WITHOUT* PUSHING THE WINDOW. A fixed
	# `custom_minimum_size.x = 660` propagates all the way up: the console's minimum made the centre
	# column the widest child, and the whole frame grew to 1577px in a 1440px window (SG-02). The
	# strip must give way instead - the row wraps, the strip gets taller, the WINDOW does not change.
	#
	# So NO minimum is set here: one would be in force before the first resize, which is the very
	# moment it does the damage. `_fit_row_min()` grants the room once the strip knows its own
	# width - one line when there is room, honest wrapping when there is not.
	_btn_row.custom_minimum_size.x = 0.0
	row1.add_child(_btn_row)
	# ONE LINE, NO WRAP, AND IT MUST BE ABLE TO VANISH. `label` (not `label_wrap`) is the value role -
	# it sizes to its content and cannot inflate the panel height. But a Label's minimum WIDTH is its
	# text, and beside a 660px control row that made the whole strip 1593px in a 1440px window
	# (SG-02). `clip_text` plus a zero minimum lets it be the LAST thing to yield: the controls stay
	# whole, and the prompt takes whatever is left (its full text is in the tooltip and the journal).
	_hint = UiTheme.label("", 13, UiTheme.COL().text)
	_hint.name = "Prompt"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.clip_text = true
	_hint.custom_minimum_size.x = 0.0
	row1.add_child(_hint)
	_lastroll = UiTheme.label("", 12, UiTheme.COL().money)
	_lastroll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lastroll.custom_minimum_size.x = 0.0
	_lastroll.clip_text = true
	row1.add_child(_lastroll)
	# THE STATUS LABEL MAY NOT HOLD THE STRIP OPEN. It carries the same sentence as the prompt (the
	# live tree showed `_status` min=231 with the prompt's own text repeated in it), and its minimum
	# width plus the 652px button row made the console's chrome 869px - wider than the 784px the
	# frame can give it at 1440. It is now free to clip to nothing: the controls keep their room and
	# the message is still on the prompt beside it (and in full in the journal).
	_status = UiTheme.label("", 12, UiTheme.COL().text_dim)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.clip_text = true
	_status.custom_minimum_size.x = 0.0
	_status.size_flags_horizontal = Control.SIZE_SHRINK_END
	row1.add_child(_status)
	col.add_child(row1)


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
	_last_args = [pid, legal, human, proj, seats]
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
	b.set_meta("act", act)   # hotkeys B/N press THIS button (HG-13)
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


## HG-13: press the REAL button for `act` (same path as a click). False when the action is
## not offered right now - the badge is a promise only where it works.
func press_action(act: String) -> bool:
	for c in _btn_row.get_children():
		if c is Button and str((c as Button).get_meta("act", "")) == act:
			(c as Button).emit_signal("pressed")
			return true
	return false


func retranslate() -> void:
	# the console is state-driven: re-render from the last sync (a locale switch mid-match must
	# not wait for the next event); cold shows the START button in the new language
	if _cold:
		set_cold(true)
	elif _last_args.size() == 5:
		sync(_last_args[0], _last_args[1], _last_args[2], _last_args[3], _last_args[4])
	else:
		_status.text = ""
