extends Control
## The modal host (`#modal`): a dim scrim and one centred sheet.
##
## The v3 swap left it able to do exactly one thing — `show_message`. F-40..F-43 (build,
## trade compose, incoming trade, auction) live here now, because the audit's console buttons
## ("стройка/торг/ставка") had no other possible home: every one of them needs PARAMETERS, and
## a parameter can only come from a dialog.
##
## Contract with the shell: the host never touches the engine. It collects intent parameters
## and emits them; game_view submits through the manager/wire, exactly like every other button.

signal trade_submitted(to: int, give_tiles: Array, give_cash: int, want_tiles: Array, want_cash: int)
signal trade_answered(accept: bool)
signal auction_bid(amount: int)
signal auction_pass

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

var _scrim: ColorRect
var _sheet: PanelContainer
var _title: Label
var _body: VBoxContainer
## What this sheet is showing right now ("" = message). The shell refreshes/closes by kind.
var kind := ""

# --- trade composer state ---
var _c_recipients: Array = []      # pids in the OptionButton, same order as items
var _c_to: OptionButton
var _c_give: Array = []            # [[CheckBox, tile_index], ...]
var _c_want_box: VBoxContainer
var _c_want: Array = []
var _c_give_cash: LineEdit
var _c_want_cash: LineEdit
var _c_err: Label
var _c_proj: Dictionary = {}
var _c_seats: Array = []
var _c_human := -1

# --- auction state ---
var _a_high := -1
var _a_bid: LineEdit
var _a_err: Label
var _a_proj: Dictionary = {}
var _a_seats: Array = []
var _a_human := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	visible = false

	_scrim = ColorRect.new()
	_scrim.color = Color(UiTheme.COL().bg.r, UiTheme.COL().bg.g, UiTheme.COL().bg.b, 0.72)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_sheet = PanelContainer.new()
	_sheet.custom_minimum_size = Vector2(0, 0)
	_sheet.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.anchor_left = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left = -300
	_sheet.offset_right = 300
	_sheet.offset_top = -120
	_sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_sheet)
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 16)
	_sheet.add_child(m)
	var v := UiTheme.vbox(10)
	m.add_child(v)
	var head := UiTheme.hbox(8)
	_title = UiTheme.label("", 16, UiTheme.COL().text)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiTheme.button("✕", "")
	x.custom_minimum_size = Vector2(26, 26)
	x.connect("pressed", Callable(self, "close"))
	head.add_child(x)
	v.add_child(head)
	_body = UiTheme.vbox(8)
	v.add_child(_body)


func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func show_message(title: String, text: String) -> void:
	kind = ""
	_title.text = title
	_clear_body()
	_body.add_child(UiTheme.label_wrap(text, 13, UiTheme.COL().text))
	visible = true


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	kind = ""


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		accept_event()


# --- small helpers ---------------------------------------------------------------------------

func _tiles_of(proj: Dictionary, pid: int) -> Array:
	var out: Array = []
	for t in (proj.get("board", []) as Array):
		if int(t.get("owner", -1)) == pid:
			out.append(t)
	return out


func _seat_name(seats: Array, pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	return "P%d" % pid


## E-1/D8: ONE side of a deal in words - the tile NAMES (from the projection's board, the same
## source the board draws from) plus the cash. A side with neither reads "ничего", not "$0 + 0".
##
## The names are wrapped, not clipped: a long deal must grow the sheet, not truncate the property
## list, because a truncated list is exactly the "unanswerable offer" this replaces.
func _terms_block(cash: int, tiles: Array, proj: Dictionary) -> Label:
	var names: Array = []
	for t in tiles:
		names.append(_tile_name(proj, int(t)))
	var parts: Array = []
	if not names.is_empty():
		parts.append(", ".join(names))
	if cash > 0:
		parts.append("$%d" % cash)
	var text: String = " + ".join(parts) if not parts.is_empty() else I18n.t("trade.nothing")
	var l := UiTheme.label_wrap(text, 13, UiTheme.COL().text)
	l.name = "trade-terms"
	return l


## A tile name from the projection board; an index the board does not carry degrades to the index
## itself rather than to a blank, so the reader always sees SOMETHING to identify the tile by.
func _tile_name(proj: Dictionary, idx: int) -> String:
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) == idx:
			return str(t.get("short", t.get("name", "#%d" % idx)))
	return "#%d" % idx


## A checkbox row for one tile, inside a scrollable list capped in height (a 28-tile offer
## must not stretch the sheet past the window).
func _tile_check_row(box: VBoxContainer, t: Dictionary) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = "%s  ($%d)" % [str(t.get("name", "?")), int(t.get("cost", 0))]
	cb.add_theme_font_size_override("font_size", 12)
	cb.add_theme_color_override("font_color", UiTheme.COL().text)
	box.add_child(cb)
	return cb


func _scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := UiTheme.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _cash_row(label_key: String, tip_key: String) -> LineEdit:
	var row := UiTheme.hbox(8)
	var l := UiTheme.label(I18n.t(label_key), 12, UiTheme.COL().text_dim)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = "0"
	e.custom_minimum_size.x = 90
	e.add_theme_stylebox_override("normal",
		UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	if tip_key != "":
		e.tooltip_text = I18n.t(tip_key)
	row.add_child(e)
	# the row lives inside the body; the caller keeps the LineEdit reference
	_body.add_child(row)
	return e


# --- F-41: the trade composer ----------------------------------------------------------------

## Compose an offer: recipient, your tiles + cash, their tiles + cash. Every number the engine
## validates (ownership, funds) is pre-checked here so a refusal stays the engine's business,
## not a round trip the player did not need.
func show_trade_composer(proj: Dictionary, seats: Array, human_pid: int) -> void:
	kind = "trade_composer"
	_c_proj = proj
	_c_seats = seats
	_c_human = human_pid
	_title.text = I18n.t("modal.trade_title")
	_clear_body()

	var rrow := UiTheme.hbox(8)
	rrow.add_child(UiTheme.label(I18n.t("modal.recipient"), 12, UiTheme.COL().text_dim))
	_c_to = OptionButton.new()
	# fit_to_longest_item sizes the dropdown by its widest ENTRY and can widen the sheet
	_c_to.fit_to_longest_item = false
	_c_recipients.clear()
	for s in seats:
		if int(s.pid) == human_pid:
			continue
		_c_to.add_item(str(s.name))
		_c_recipients.append(int(s.pid))
	_c_to.tooltip_text = I18n.t("modal.recipient_tip")
	rrow.add_child(_c_to)
	_body.add_child(rrow)

	_body.add_child(UiTheme.label(I18n.t("modal.give_hint"), 11, UiTheme.COL().text_dim))
	var give_box := _scroll_list()
	_c_give.clear()
	for t in _tiles_of(proj, human_pid):
		_c_give.append([_tile_check_row(give_box, t), int(t.get("index", -1))])
	_body.add_child(give_box.get_parent())

	_c_give_cash = _cash_row("modal.give_cash", "modal.give_cash_tip")

	_body.add_child(UiTheme.label(I18n.t("modal.want_hint"), 11, UiTheme.COL().text_dim))
	_c_want_box = _scroll_list()
	_body.add_child(_c_want_box.get_parent())
	_rebuild_want()

	_c_want_cash = _cash_row("modal.want_cash", "modal.want_cash_tip")

	_c_err = UiTheme.label("", 11, UiTheme.COL().danger)
	_body.add_child(_c_err)

	var foot := UiTheme.hbox(8)
	var cancel := UiTheme.button(I18n.t("ui.cancel"), I18n.t("modal.cancel_tip"))
	cancel.connect("pressed", Callable(self, "close"))
	foot.add_child(cancel)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var send := UiTheme.button_accent(I18n.t("modal.offer"), I18n.t("modal.offer_tip"))
	send.connect("pressed", Callable(self, "_submit_trade"))
	foot.add_child(send)
	_body.add_child(foot)
	_c_to.item_selected.connect(func(_i: int) -> void: _rebuild_want())
	visible = true


## The want-list depends on WHO receives the offer: rebuild it on recipient change.
func _rebuild_want() -> void:
	if _c_want_box == null or _c_to == null or _c_recipients.is_empty():
		return
	for c in _c_want_box.get_children():
		_c_want_box.remove_child(c)
		c.queue_free()
	_c_want.clear()
	var idx: int = _c_to.selected
	if idx < 0 or idx >= _c_recipients.size():
		return
	for t in _tiles_of(_c_proj, int(_c_recipients[idx])):
		_c_want.append([_tile_check_row(_c_want_box, t), int(t.get("index", -1))])


func _checked_tiles(list: Array) -> Array:
	var out: Array = []
	for pair in list:
		if (pair[0] as CheckBox).button_pressed:
			out.append(int(pair[1]))
	return out


func _int_of(e: LineEdit) -> int:
	var s := e.text.strip_edges()
	return int(s) if s.is_valid_int() else -1


func _submit_trade() -> void:
	if _c_to == null or _c_recipients.is_empty():
		_c_err.text = I18n.t("modal.trade_bad_recipient")
		return
	var to: int = int(_c_recipients[_c_to.selected])
	var give_tiles := _checked_tiles(_c_give)
	var want_tiles := _checked_tiles(_c_want)
	var give_cash := _int_of(_c_give_cash)
	var want_cash := _int_of(_c_want_cash)
	if give_cash < 0 or want_cash < 0:
		_c_err.text = I18n.t("modal.empty_offer")
		return
	if give_tiles.is_empty() and want_tiles.is_empty() and give_cash == 0 and want_cash == 0:
		_c_err.text = I18n.t("modal.empty_offer")
		return
	# my funds: the engine would refuse "insufficient cash for offer" - say it before the
	# round trip, in the same words the player would have read after it
	var my_money := 0
	for p in (_c_proj.get("players", []) as Array):
		if int(p.get("index", -1)) == _c_human:
			my_money = int(p.get("money", 0))
	if give_cash > my_money:
		_c_err.text = I18n.t("modal.trade_no_funds")
		return
	trade_submitted.emit(to, give_tiles, give_cash, want_tiles, want_cash)
	close()


# --- F-42: an incoming offer ----------------------------------------------------------------

func show_trade_response(proj: Dictionary, seats: Array) -> void:
	kind = "trade_response"
	_title.text = I18n.t("modal.trade_response")
	_clear_body()
	var pend: Dictionary = proj.get("pending", {})
	var proposer := _seat_name(seats, int(pend.get("proposer", -1)))
	var recipient := _seat_name(seats, int(pend.get("recipient", -1)))
	_body.add_child(UiTheme.label_wrap(I18n.t("modal.trade_offers", [proposer, recipient]), 13,
		UiTheme.COL().text))
	var give_tiles: Array = pend.get("give_tiles", [])
	var want_tiles: Array = pend.get("want_tiles", [])
	# E-1/D8: the composition was rendered as a COUNT of tiles - "Даёт: $200 + 2 тайл(а)" - so the
	# player was asked to accept or decline a deal without being told which properties changed
	# hands. That is unanswerable: tiles are not interchangeable, and "2 tiles" is the same sentence
	# for a brown and a dark-blue. The names come from the projection's board, the same source the
	# board itself draws from.
	_body.add_child(UiTheme.label(I18n.t("modal.trade_gives"), 12, UiTheme.COL().text_dim))
	_body.add_child(_terms_block(int(pend.get("give_cash", 0)), give_tiles, proj))
	_body.add_child(UiTheme.label(I18n.t("modal.trade_asks"), 12, UiTheme.COL().text_dim))
	_body.add_child(_terms_block(int(pend.get("want_cash", 0)), want_tiles, proj))
	var foot := UiTheme.hbox(8)
	var decline := UiTheme.button(I18n.t("modal.decline"), I18n.t("modal.decline_tip"))
	decline.connect("pressed", func() -> void:
		trade_answered.emit(false)
		close())
	foot.add_child(decline)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var accept := UiTheme.button_accent(I18n.t("modal.accept"), I18n.t("modal.accept_tip"))
	accept.connect("pressed", func() -> void:
		trade_answered.emit(true)
		close())
	foot.add_child(accept)
	_body.add_child(foot)
	visible = true


# --- F-43: the auction ------------------------------------------------------------------------

## The lot, the current bid and who leads it, plus — for the CURRENT bidder only — an amount
## field, BID and PASS. A spectator sees the numbers (bids are public) and no controls.
func show_auction(proj: Dictionary, seats: Array, human_pid: int) -> void:
	kind = "auction"
	_a_proj = proj
	_a_seats = seats
	_a_human = human_pid
	var pend: Dictionary = proj.get("pending", {})
	var tile: int = int(pend.get("tile", -1))
	var tile_name := "?"
	for t in (proj.get("board", []) as Array):
		if int(t.get("index", -1)) == tile:
			tile_name = str(t.get("name", "?"))
	var typed := ""
	if _a_bid != null and is_instance_valid(_a_bid):
		typed = _a_bid.text     # a state push must not wipe a half-typed bid
	_a_high = int(pend.get("high", -1))
	_title.text = I18n.t("modal.auction_title")
	_clear_body()
	_body.add_child(UiTheme.label(I18n.t("modal.lot_name", [tile_name]), 13, UiTheme.COL().text))
	if _a_high > 0:
		_body.add_child(UiTheme.label(I18n.t("modal.auction_high", [_a_high]), 12, UiTheme.COL().money))
		var lead := _seat_name(seats, int(pend.get("high_player", -1)))
		_body.add_child(UiTheme.label(I18n.t("modal.auction_leader", [lead]), 12, UiTheme.COL().text_dim))
	else:
		_body.add_child(UiTheme.label(I18n.t("modal.auction_none"), 12, UiTheme.COL().text_dim))
	var bidder: int = int(pend.get("bidder", -1))
	if human_pid < 0 or human_pid != bidder:
		_body.add_child(UiTheme.label_wrap(I18n.t("modal.auction_watch"), 11, UiTheme.COL().text_dim))
		visible = true
		return
	var row := UiTheme.hbox(8)
	row.add_child(UiTheme.label(I18n.t("modal.bid_lbl"), 12, UiTheme.COL().text_dim))
	_a_bid = LineEdit.new()
	_a_bid.name = "bid_input"
	_a_bid.text = typed if typed != "" else str(maxi(1, _a_high + 5))
	_a_bid.custom_minimum_size.x = 110
	_a_bid.tooltip_text = I18n.t("modal.bid_tip")
	_a_bid.add_theme_stylebox_override("normal",
		UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	row.add_child(_a_bid)
	var send := UiTheme.button_accent(I18n.t("modal.bid_btn"), I18n.t("modal.bid_btn_tip"))
	send.connect("pressed", Callable(self, "_submit_bid"))
	row.add_child(send)
	var passb := UiTheme.button(I18n.t("modal.pass_btn"), I18n.t("modal.pass_tip"))
	passb.connect("pressed", func() -> void:
		auction_pass.emit()
		close())
	row.add_child(passb)
	_body.add_child(row)
	_a_err = UiTheme.label("", 11, UiTheme.COL().danger)
	_body.add_child(_a_err)
	visible = true


## Pre-check what the engine would refuse anyway: a bid at or below the high, or beyond the
## bidder's cash. The engine stays the authority; the player just does not have to earn a
## refusal first.
func _submit_bid() -> void:
	if _a_bid == null or not is_instance_valid(_a_bid):
		return
	var amount := _int_of(_a_bid)
	if amount < 0:
		_a_err.text = I18n.t("modal.bid_too_low", [maxi(0, _a_high)])
		return
	if _a_high != -1 and amount <= _a_high:
		_a_err.text = I18n.t("modal.bid_too_low", [_a_high])
		return
	var my_money := 0
	for p in (_a_proj.get("players", []) as Array):
		if int(p.get("index", -1)) == _a_human:
			my_money = int(p.get("money", 0))
	if amount > my_money:
		_a_err.text = I18n.t("modal.bid_no_funds")
		return
	auction_bid.emit(amount)
	close()
