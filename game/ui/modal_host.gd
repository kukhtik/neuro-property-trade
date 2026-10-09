class_name ModalHost
extends Control
## The single modal host (spec §6). One instance for the whole game; `open()` is
## idempotent — asking for a modal that is already open UPDATES it instead of
## stacking a second one. That was defect #1 of the original brief ("стопки
## модалок"), so it is enforced structurally here rather than by convention.
##
## Closing rules (spec §6): clicking the dim closes only the INFORMATIONAL
## modals (rules, trade, message, settings). The auction and game-over are
## decisions / terminal states — a stray click must not dismiss them.
##
## Every modal is a `kind` + `data` pair, so the host can re-render the open
## modal from that pair alone. That is what makes the live locale switch work
## (re-render, never rebuild the tree) and what makes open() idempotent.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const Intents := preload("res://ui/core/intent_map.gd")
const MoneyFmt := preload("res://ui/core/money.gd")

signal build_requested(tile: int, op: String)
signal trade_proposed(to: int, give_tiles: Array, give_cash: int, want_tiles: Array, want_cash: int)
signal trade_responded(accept: bool)
signal auction_bid(amount: int)
signal auction_pass()
signal sound_toggled(category: String, on: bool)
signal restart_requested
signal settings_requested
## Emitted whenever the open modal changes (kind; "" when closed).
signal modal_changed(kind: String)

## Modals the dim may dismiss (spec §6). Auction and game-over are NOT here.
const DISMISSABLE := ["rules", "trade", "message", "settings"]

var _panel: Control
var _current_kind: String = ""
var _current_data: Dictionary = {}
var _dim: ColorRect
var _intent_map = Intents.new()


## The dialog's stack, re-centred whenever it or the host changes size.
var _centred: Control = null


## Centre the dialog. Called when it opens and when the host resizes.
##
## Doing this in `_process` did NOT run at all: the host adds this node but never enables
## processing on it, so the dialog sat in the corner while the code to centre it looked
## correct. An explicit call is one line and does not depend on who owns the tree.
func centre() -> void:
	if _centred == null or not is_instance_valid(_centred):
		return
	var s := size
	var w := _centred.size
	if w.x <= 1.0:
		w = _centred.get_combined_minimum_size()
	_centred.position = Vector2(maxf(0.0, (s.x - w.x) * 0.5), maxf(0.0, (s.y - w.y) * 0.5))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		centre()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_dim.gui_input.connect(_on_dim_input)
	# re-render (not rebuild) the open modal when the locale changes
	I18n.inst().locale_changed.connect(_on_locale_changed)


## The dim colour comes from a skin token, not a literal.
func _dress() -> void:
	var sc := UiTheme.skin().color("bg", Color(0, 0, 0))
	# `#mod` is the backdrop at 75% opacity over the page, with a 3px blur. Godot's ColorRect
	# cannot blur, so the same effect is reached with a slightly denser scrim — the point is
	# that the dialog sits ON something, not that the pixels behind it are unreadable.
	_dim.color = Color(sc.r, sc.g, sc.b, 0.75)


func open(kind: String, data: Dictionary = {}) -> void:
	_current_kind = kind
	_current_data = data
	_render()
	visible = true
	_dress()
	modal_changed.emit(kind)


func kind() -> String:
	return _current_kind


func close() -> void:
	if _current_kind == "":
		return
	_current_kind = ""
	_current_data = {}
	visible = false
	_free_panel()
	modal_changed.emit("")


func is_open() -> bool:
	return _current_kind != "" and visible


## Free the current dialog AND its wrapper. The wrapper carries the box's offset shadow, so
## freeing only the box leaves the shadow hanging on the screen.
func _free_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		_panel = null
		return
	var wrap = _panel.get_meta("wrap", null)
	if wrap != null and is_instance_valid(wrap):
		(wrap as Node).free()
	else:
		_panel.free()
	_panel = null


## How many modal panels currently exist as children. Used by the "no stacking"
## contract: it must be 0 or 1, never more.
func panel_count() -> int:
	var n := 0
	for c in get_children():
		if c != _dim:
			n += 1
	return n


# --- rendering ----------------------------------------------------------------

## Render the current kind+data. The ONLY place a modal's content is built, so a
## locale change is the same code path as opening it.
func _render() -> void:
	_free_panel()
	match _current_kind:
		"build": _build_build()
		"trade": _build_trade()
		"trade_response": _build_trade_response()
		"auction": _build_auction()
		"game_over": _build_game_over()
		"rules": _build_rules()
		"message": _build_message()
		"settings": _build_settings()
		_: _panel = null


func _on_locale_changed(_locale: String) -> void:
	if is_open():
		_render()


func _on_dim_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	# only the informational modals dismiss on a background click
	if _current_kind in DISMISSABLE:
		close()


# --- build / manage a tile ----------------------------------------------------

func open_build(tile: int, proj: Dictionary, seat_name: String, legal: Array = []) -> void:
	open("build", {"tile": tile, "proj": proj, "seat": seat_name, "legal": legal})


func _build_build() -> void:
	var tile: int = int(_current_data.get("tile", -1))
	var proj: Dictionary = _current_data.get("proj", {})
	var t := _find_tile(proj, tile)
	var body := UiTheme.vbox(10)
	body.add_child(_heading(I18n.t("modal.build_title")))
	body.add_child(UiTheme.label(I18n.t("modal.tile_header", [t.get("name", tile), tile]), 14))
	body.add_child(UiTheme.label_muted(I18n.t("modal.house_cost", [
		str(t.get("houses", 0)), str(t.get("house_cost", 0))]), 13))

	var legal: Array = _current_data.get("legal", [])
	var row := UiTheme.hbox(10)
	_add_action_button(row, "build", "act.build", "act.build_tip", {"tile": tile}, legal, true)
	_add_action_button(row, "sell", "act.sell", "act.sell_tip", {"tile": tile}, legal, false)
	_add_action_button(row, "mortgage", "act.mortgage", "act.mortgage_tip", {"tile": tile}, legal, false)
	_add_action_button(row, "unmortgage", "act.unmortgage", "act.unmortgage_tip", {"tile": tile}, legal, false)
	body.add_child(row)
	var close_btn := UiTheme.button(I18n.t("modal.close_btn"), I18n.t("modal.settings_panel_tip"))
	close_btn.connect("pressed", Callable(self, "close"))
	body.add_child(close_btn)
	_panelize(body)


## A button enabled only when the ENGINE offers the action (spec §6: buttons
## follow legal_actions; the UI never re-implements a rule). An empty `legal`
## means "no information" and leaves the button enabled — the engine still
## validates and rejects.
func _add_action_button(row: Control, ui_action: String, key: String, tip_key: String,
		params: Dictionary, legal: Array, primary: bool) -> Button:
	var b: Button = UiTheme.button_accent(I18n.t(key), I18n.t(tip_key)) if primary \
		else UiTheme.button(I18n.t(key), I18n.t(tip_key))
	if not legal.is_empty():
		b.disabled = not _intent_map.can(ui_action, legal, params)
	b.set_meta("i18n_key", key)
	b.set_meta("ui_action", ui_action)
	var mapped: Dictionary = _intent_map.to_engine(ui_action, params)
	b.connect("pressed", Callable(self, "_emit_build").bind(int(params.get("tile", -1)),
		str(mapped.get("action", ""))))
	row.add_child(b)
	return b


# --- trade --------------------------------------------------------------------

func open_trade(proj: Dictionary, seats: Array, proposer_pid: int, legal: Array = []) -> void:
	open("trade", {"proj": proj, "seats": seats, "pid": proposer_pid, "legal": legal})


## The proposer builds a REAL offer: tiles on both sides plus cash, validated by
## the engine (spec §6: propose with validation, not the old stub).
func _build_trade() -> void:
	var proj: Dictionary = _current_data.get("proj", {})
	var seats: Array = _current_data.get("seats", [])
	var proposer: int = int(_current_data.get("pid", -1))

	var body := UiTheme.vbox(8)
	body.add_child(_heading(I18n.t("modal.trade_title")))

	var recipient := OptionButton.new()
	recipient.tooltip_text = I18n.t("modal.recipient_tip")
	recipient.custom_minimum_size.x = 140
	for s in seats:
		if int(s.pid) != proposer:
			recipient.add_item(str(s.name), int(s.pid))
	var to_row := UiTheme.hbox(8)
	to_row.add_child(UiTheme.label(I18n.t("modal.recipient")))
	to_row.add_child(recipient)
	body.add_child(to_row)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)

	var give_box := VBoxContainer.new()
	give_box.add_child(UiTheme.label_muted(I18n.t("modal.give_hint"), 12))
	var give_list := _tile_checklist(proj, proposer, "give")
	give_box.add_child(give_list)
	var give_cash_row := _cash_spin("modal.give_cash", "modal.give_cash_tip")
	give_box.add_child(give_cash_row)
	cols.add_child(give_box)

	var first_recipient: int = _first_other(seats, proposer)
	var want_box := VBoxContainer.new()
	want_box.add_child(UiTheme.label_muted(I18n.t("modal.want_hint"), 12))
	var want_holder := VBoxContainer.new()
	want_holder.name = "WantHolder"
	_repopulate_want(want_holder, proj, first_recipient)
	want_box.add_child(want_holder)
	var want_cash_row := _cash_spin("modal.want_cash", "modal.want_cash_tip")
	want_box.add_child(want_cash_row)
	cols.add_child(want_box)
	body.add_child(cols)

	# the want side follows the chosen recipient
	recipient.item_selected.connect(func(idx: int) -> void:
		_repopulate_want(want_holder, proj, recipient.get_item_id(idx)))

	var err := UiTheme.label("", 12, UiTheme.skin().color("danger"))
	err.name = "Err"
	body.add_child(err)

	var btn_row := UiTheme.hbox(10)
	var ok := UiTheme.button_accent(I18n.t("modal.offer"), I18n.t("modal.offer_tip"))
	ok.connect("pressed", Callable(self, "_emit_trade").bind(
		recipient, _spin_in(give_cash_row), _spin_in(want_cash_row),
		give_list, want_holder, err))
	btn_row.add_child(ok)
	var cancel := UiTheme.button(I18n.t("ui.cancel"), I18n.t("modal.cancel_tip"))
	cancel.connect("pressed", Callable(self, "close"))
	btn_row.add_child(cancel)
	body.add_child(btn_row)
	_panelize(body)


func _repopulate_want(holder: Control, proj: Dictionary, pid: int) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()
	var list := _tile_checklist(proj, pid, "want")
	# move the checklist's children out of it — a node cannot have two parents
	for c in list.get_children():
		list.remove_child(c)
		holder.add_child(c)
	list.free()


## A checklist of the tiles a player OWNS and may trade (no houses on them) —
## exactly what the engine's propose_trade accepts.
func _tile_checklist(proj: Dictionary, pid: int, tag: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	for t in proj.get("board", []):
		if int(t.get("owner", -1)) != pid:
			continue
		if int(t.get("houses", 0)) > 0:
			continue   # the engine rejects trading a tile with houses
		var cb := CheckBox.new()
		cb.text = str(t.get("name", t.get("index", "")))
		cb.set_meta("tile", int(t.get("index", -1)))
		cb.set_meta("tag", tag)
		box.add_child(cb)
	if box.get_child_count() == 0:
		var lbl := UiTheme.label_muted(I18n.t("modal.no_tiles"), 12)
		lbl.set_meta("empty_hint", true)
		box.add_child(lbl)
	return box


## A cash row: "Даёте, $" + a spin box. Returns the ROW (callers add the row to
## their layout, not the bare spinbox).
func _cash_spin(label_key: String, tip_key: String) -> Control:
	var row := UiTheme.hbox(8)
	row.add_child(UiTheme.label(I18n.t(label_key)))
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 99999
	sp.value = 0
	sp.tooltip_text = I18n.t(tip_key)
	row.add_child(sp)
	return row


func open_trade_response(proj: Dictionary, seats: Array, legal: Array = []) -> void:
	open("trade_response", {"proj": proj, "seats": seats, "legal": legal})


func _build_trade_response() -> void:
	var proj: Dictionary = _current_data.get("proj", {})
	var seats: Array = _current_data.get("seats", [])
	var pending: Dictionary = proj.get("pending", {})
	var proposer: int = int(pending.get("proposer", -1))
	var recipient: int = int(pending.get("recipient", -1))

	var body := UiTheme.vbox(8)
	body.add_child(_heading(I18n.t("modal.trade_response")))
	body.add_child(UiTheme.label(I18n.t("modal.trade_offers", [
		_name_of(seats, proposer), _name_of(seats, recipient)]), 14))
	body.add_child(_offer_lines(proj, pending, "give", "modal.give_hint"))
	body.add_child(_offer_lines(proj, pending, "want", "modal.want_hint"))

	var row := UiTheme.hbox(10)
	var yes := UiTheme.button_accent(I18n.t("modal.accept"), I18n.t("modal.accept_tip"))
	yes.connect("pressed", Callable(self, "_emit_trade_response").bind(true))
	row.add_child(yes)
	var no := UiTheme.button(I18n.t("modal.decline"), I18n.t("modal.decline_tip"))
	no.connect("pressed", Callable(self, "_emit_trade_response").bind(false))
	row.add_child(no)
	body.add_child(row)
	_panelize(body)


## A real breakdown of one side of the offer: which tiles plus the cash amount.
func _offer_lines(proj: Dictionary, pending: Dictionary, tag: String, label_key: String) -> Control:
	var box := VBoxContainer.new()
	var tiles: Array = pending.get("%s_tiles" % tag, [])
	var cash: int = int(pending.get("%s_cash" % tag, 0))
	var names: Array = []
	for idx in tiles:
		names.append(str(_find_tile(proj, int(idx)).get("name", idx)))
	var line: String = "%s: %s" % [I18n.t(label_key),
		(", ".join(names) if names.size() > 0 else I18n.t("modal.no_tiles"))]
	if cash > 0:
		line += "   %s" % MoneyFmt.make("$").amount(cash)
	box.add_child(UiTheme.label(line, 13))
	return box


# --- auction ------------------------------------------------------------------

func open_auction(proj: Dictionary, seats: Array, legal: Array = []) -> void:
	open("auction", {"proj": proj, "seats": seats, "legal": legal})


## The auction modal (spec §6). Buttons appear ONLY for the player the engine is
## currently asking to bid — legal_actions returns [bid, pass] for them alone
## (see the stage-0 audit). Everyone else sees a spectator note, so no private
## information can leak and no one can bid out of turn.
func _build_auction() -> void:
	var proj: Dictionary = _current_data.get("proj", {})
	var seats: Array = _current_data.get("seats", [])
	var pending: Dictionary = proj.get("pending", {})
	var legal: Array = _current_data.get("legal", [])
	var tile: int = int(pending.get("tile", -1))
	var high: int = int(pending.get("high", -1))
	var leader: int = int(pending.get("high_player", -1))
	var t := _find_tile(proj, tile)

	var body := UiTheme.vbox(8)
	body.add_child(_heading(I18n.t("modal.auction_title")))
	body.add_child(UiTheme.label(I18n.t("modal.lot_name", [t.get("name", tile)]), 14))
	body.add_child(UiTheme.label_muted(
		I18n.t("modal.auction_high", [high]) if high > 0 else I18n.t("modal.auction_none"), 13))
	if leader >= 0:
		body.add_child(UiTheme.label_muted(I18n.t("modal.auction_leader", [_name_of(seats, leader)]), 13))

	if _intent_map.can("auction_bid", legal):
		var row := UiTheme.hbox(8)
		row.add_child(UiTheme.label(I18n.t("modal.bid_lbl")))
		var amt := SpinBox.new()
		amt.min_value = high + 1
		amt.max_value = 99999
		amt.value = high + 1
		amt.tooltip_text = I18n.t("modal.bid_tip")
		row.add_child(amt)
		var bid := UiTheme.button_accent(I18n.t("modal.bid_btn"), I18n.t("modal.bid_btn_tip"))
		bid.set_meta("i18n_key", "modal.bid_btn")
		bid.connect("pressed", Callable(self, "_emit_bid").bind(amt))
		row.add_child(bid)
		var apos := UiTheme.button(I18n.t("modal.pass_btn"), I18n.t("modal.pass_tip"))
		apos.set_meta("i18n_key", "modal.pass_btn")
		apos.connect("pressed", Callable(self, "_emit_auction_pass"))
		row.add_child(apos)
		body.add_child(row)
	else:
		# spectating: no buttons (public bids only, spec §6)
		body.add_child(UiTheme.label_muted(I18n.t("modal.auction_watch"), 13))
	_panelize(body)


# --- terminal / informational -------------------------------------------------

## Game-over. NOT dismissable by a background click (spec §6).
func show_game_over(winner_name: String, turns: int, capital: int, player_count: int) -> void:
	open("game_over", {"winner": winner_name, "turns": turns,
		"capital": capital, "players": player_count})


func _build_game_over() -> void:
	var body := UiTheme.vbox(10)
	body.add_child(_heading(I18n.t("modal.game_over")))
	body.add_child(UiTheme.label_money(I18n.t("modal.winner", [
		str(_current_data.get("winner", ""))]), 18))
	body.add_child(UiTheme.label_muted(I18n.t("modal.stats", [
		int(_current_data.get("turns", 0)), int(_current_data.get("players", 0)),
		int(_current_data.get("capital", 0))]), 14))
	var row := UiTheme.hbox(10)
	var rematch := UiTheme.button_accent(I18n.t("modal.rematch"), I18n.t("modal.rematch_tip"))
	rematch.connect("pressed", Callable(self, "_emit_restart"))
	row.add_child(rematch)
	var set := UiTheme.button(I18n.t("modal.settings"), I18n.t("modal.settings_tip"))
	set.connect("pressed", Callable(self, "_emit_settings"))
	row.add_child(set)
	body.add_child(row)
	_panelize(body)


func open_rules(text: String) -> void:
	open("rules", {"text": text})


func _build_rules() -> void:
	var body := UiTheme.vbox(8)
	body.add_child(_heading(I18n.t("modal.rules_btn")))
	var txt := UiTheme.label(str(_current_data.get("text", "")), 13)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(420, 300)
	body.add_child(txt)
	var close_btn := UiTheme.button(I18n.t("modal.close_btn"), I18n.t("modal.rules_back_tip"))
	close_btn.connect("pressed", Callable(self, "close"))
	body.add_child(close_btn)
	_panelize(body)


func show_message(title: String, msg: String) -> void:
	open("message", {"title": title, "msg": msg})


func _build_message() -> void:
	var body := UiTheme.vbox(8)
	body.add_child(_heading(str(_current_data.get("title", ""))))
	body.add_child(UiTheme.label(str(_current_data.get("msg", "")), 14))
	var ok := UiTheme.button("OK", I18n.t("modal.msg_ok_tip"))
	ok.connect("pressed", Callable(self, "close"))
	body.add_child(ok)
	_panelize(body)


func open_settings(sound_cats: Array, rules_text: String) -> void:
	open("settings", {"cats": sound_cats, "text": rules_text})


func _build_settings() -> void:
	var body := UiTheme.vbox(8)
	body.add_child(_heading(I18n.t("modal.settings")))
	body.add_child(UiTheme.label(I18n.t("modal.sound_title"), 13, UiTheme.skin().color("accent")))
	for cat in _current_data.get("cats", []):
		var cb := CheckButton.new()
		cb.text = str(cat.get("label", ""))
		cb.button_pressed = bool(cat.get("on", true))
		cb.tooltip_text = I18n.t("modal.sound_tip", [str(cat.get("label", ""))])
		cb.connect("toggled", Callable(self, "_on_sound_toggled").bind(str(cat.get("key", ""))))
		body.add_child(cb)
	var rules_btn := UiTheme.button(I18n.t("modal.rules_btn"), I18n.t("modal.rules_tip"))
	rules_btn.connect("pressed", Callable(self, "_open_rules_from_settings"))
	body.add_child(rules_btn)
	var close_btn := UiTheme.button(I18n.t("modal.close_btn"), I18n.t("modal.settings_panel_tip"))
	close_btn.connect("pressed", Callable(self, "close"))
	body.add_child(close_btn)
	_panelize(body)


func _open_rules_from_settings() -> void:
	open_rules(str(_current_data.get("text", "")))


func _on_sound_toggled(on: bool, key: String) -> void:
	sound_toggled.emit(key, on)


# --- helpers ------------------------------------------------------------------

func _heading(txt: String) -> Label:
	var h := UiTheme.label(txt, 18, UiTheme.skin().color("money"))
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


func _first_other(seats: Array, pid: int) -> int:
	for s in seats:
		if int(s.pid) != pid:
			return int(s.pid)
	return -1


func _panelize(content: Control) -> void:
	# THE DIALOG BOX, to the mockup's spec.
	#
	# `#mbox` is: 440px wide, a 2px ACCENT border, `box-shadow: 10px 10px 0 var(--line)` — an
	# offset hard shadow, not a soft one — over a scrim at 75%. Ours was a 460px chamfer with a
	# 1px line border and no shadow, which is why our dialogs looked like plain boxes.
	var wrap := Control.new()
	wrap.name = "ModalWrap"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# the offset shadow: its own flat panel BEHIND the box, shifted 10px right and down
	var stack := MarginContainer.new()
	stack.name = "ModalBox"
	stack.custom_minimum_size = Vector2(440, 0)
	stack.add_theme_constant_override("margin_left", 0)
	stack.add_theme_constant_override("margin_right", 0)
	stack.add_theme_constant_override("margin_top", 0)
	stack.add_theme_constant_override("margin_bottom", 0)
	# A CenterContainer only centres what does NOT stretch to fill it. The default flags are
	# FILL, so the stack took the whole screen and "centring" did nothing.
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# positioned by `_process`, so it lives directly under the full-rect wrapper
	wrap.add_child(stack)
	_centred = stack

	var shadow := Panel.new()
	shadow.name = "Shadow"
	shadow.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().border, Color.TRANSPARENT, 0, 0))
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = 10
	shadow.offset_top = 10
	shadow.offset_right = 10
	shadow.offset_bottom = 10
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(shadow)

	_panel = UiTheme.chamfer_panel("tr")
	(_panel as Control).name = "Box"
	(_panel as Control).fill_token = "surface.1"
	# the border is the ACCENT at 2px, as `#mbox` draws it
	(_panel as Control).border_token = "accent"
	(_panel as Control).border_bonus = int(UiTheme.skin().shape("line_active", 2.0)) - 1
	(_panel as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_panel)

	var margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 16)
	_panel.add_child(margin)
	margin.add_child(content)

	# the stack follows the box: the box's own height decides the stack's
	stack.custom_minimum_size.y = 0
	add_child(wrap)
	_centred = stack
	call_deferred("centre")
	_panel.set_meta("wrap", wrap)


func _emit_build(tile: int, op: String) -> void:
	if op == "":
		return
	build_requested.emit(tile, op)


## Gather the offer from the real widget tree and hand it over; the engine
## validates it.
func _emit_trade(recipient: OptionButton, give_cash: SpinBox, want_cash: SpinBox,
		give_list: Control, want_holder: Control, err: Label) -> void:
	var to: int = recipient.get_item_id(recipient.selected)
	var give: Array = _checked_tiles(give_list, "give")
	var want: Array = _checked_tiles(want_holder, "want")
	var gc: int = int(give_cash.value)
	var wc: int = int(want_cash.value)
	# a strictly empty offer is meaningless — the engine rejects it
	if give.is_empty() and want.is_empty() and gc == 0 and wc == 0:
		if err != null:
			err.text = I18n.t("modal.empty_offer")
		return
	trade_proposed.emit(to, give, gc, want, wc)


func _checked_tiles(box: Control, tag: String) -> Array:
	var out: Array = []
	_walk(box, func(n: Node) -> void:
		if n is CheckBox and bool((n as CheckBox).button_pressed) \
				and str(n.get_meta("tag", "")) == tag:
			out.append(int(n.get_meta("tile", -1))))
	return out


func _walk(node: Node, fn: Callable) -> void:
	fn.call(node)
	for c in node.get_children():
		_walk(c, fn)


func _emit_trade_response(accept: bool) -> void:
	trade_responded.emit(accept)


func _emit_bid(amt: SpinBox) -> void:
	auction_bid.emit(int(amt.value))


func _emit_auction_pass() -> void:
	auction_pass.emit()


func _emit_restart() -> void:
	restart_requested.emit()


func _emit_settings() -> void:
	settings_requested.emit()


# --- test/inspection helpers --------------------------------------------------

## Depth-first walk over this host's nodes.
func _walk_all(node: Node, out: Array) -> void:
	out.append(node)
	for c in node.get_children():
		_walk_all(c, out)


func nodes() -> Array:
	var out: Array = []
	_walk_all(self, out)
	return out


## The recipient dropdown in an open trade modal.
func _find_recipient() -> OptionButton:
	for n in nodes():
		if n is OptionButton:
			return n
	return null


## The first SpinBox inside a control (a cash row wraps its spinbox).
func _spin_in(c: Control) -> SpinBox:
	if c == null:
		return null
	for n in nodes():
		if n is SpinBox and c.is_ancestor_of(n):
			return n
	return null


## The n-th SpinBox in the open modal (0 = give cash, 1 = want cash).
func _find_spin(index: int) -> SpinBox:
	var seen := 0
	for n in nodes():
		if n is SpinBox:
			if seen == index:
				return n
			seen += 1
	return null


## The first container whose checkboxes carry the given tag.
func _find_by_tag(tag: String) -> Control:
	for n in nodes():
		if n is Control and not (n is CheckBox):
			for c in n.get_children():
				if c is CheckBox and str(c.get_meta("tag", "")) == tag:
					return n
	return null


## The inline error label in the trade modal.
func _find_err() -> Label:
	for n in nodes():
		if n is Label and n.name == "Err":
			return n
	return null
