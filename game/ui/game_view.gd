extends Control
## The game shell — the v3 interface assembled from the prototype's regions:
##   #top (header) · #seats (left dock) · #stage (board) + #act (console) · #rightcol
##   (toasts · #journal · #inspector) · #modal.
##
## Same outer contract as before the swap (signals + setup/apply_projection/...), so
## main.gd wiring is unchanged. Reads the spectator projection; submits intents through
## the seat manager — the engine still validates everything.

signal restart_requested
signal settings_requested
signal skin_requested(skin_id: String)

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const TopBar := preload("res://ui/top_bar.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const JournalPanel := preload("res://ui/journal_panel.gd")
const JournalLines := preload("res://ui/core/journal_lines.gd")
const TileInspector := preload("res://ui/tile_inspector.gd")
const ToastList := preload("res://ui/toast.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

const DOCK_L := 268.0
const DOCK_R := 344.0

var _profile = null
var _engine = null
var _mgr = null
var seats: Array = []
var _proj: Dictionary = {}
var _cold := true
var _observer := false
## WHO AM I ON THIS SCREEN. Was hardcoded to 0 (the audit: "на хосте работает случайно; у
## удалённого клиента кнопки не покажутся никогда, а интенты ушли бы за место 0"). Two
## sources: `setup()` derives it from the seat list (the LOCAL/ADMIN seat), and a client that
## joined over the wire is TOLD its pid by the host (`set_human_pid` on JOINED). -1 = nobody
## local plays here: the console offers no buttons, no intent can be sent for anyone.
var _human_pid := -1
## The wire, when this screen is a REMOTE client: buttons then submit through it instead of a
## local manager (a client owns no engine - main._submit used to hit `if _mgr == null: return`
## and the browser's presses went nowhere).
var _remote = null

var _top: Control
var _seats_panel: Control
var _board: Control
var _console: Control
var _journal: Control
var _inspector: Control
var _toasts: Control
var _modals: Control
var _seats_dock: Control
var _rightcol: Control
var _body_row: Control
## compact profile (design/regions.json): the docks collapse into 48px RAILS; a rail click
## opens the matching 320px DRAWER over the stage with the dock's content inside. The old
## compact profile only HID the docks - the audit's defect - which made the journal, the
## inspector and (through it) all tile management unreachable.
var _rail_left: Control
var _rail_right: Control
var _rail_r_journal: Control
var _rail_r_inspector: Control
var _drawers: Dictionary = {}
## SG-06: engine events -> readable journal lines (adapter spans + tile names).
var _journal_lines = JournalLines.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# the app paints its own background (proto `.app { background: var(--bg) }`) — without
	# this the window clear colour (grey) showed through every gap in the layout
	var bg := ColorRect.new()
	bg.color = UiTheme.COL().bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()


func _build() -> void:
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 8)   # `--gap`
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	var col := UiTheme.vbox(8)
	outer.add_child(col)

	_top = TopBar.new()
	_top.name = "top"
	_top.settings_requested.connect(func() -> void: settings_requested.emit())
	_top.restart_requested.connect(func() -> void: restart_requested.emit())
	_top.skin_requested.connect(func(id: String) -> void: skin_requested.emit(id))
	col.add_child(_top)

	var body := UiTheme.hbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_body_row = body

	_seats_panel = PlayersPanel.new()
	_seats_panel.name = "seats"
	_seats_panel.custom_minimum_size.x = DOCK_L
	_seats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_seats_panel)

	# centre column: the stage (board) with the console under it
	var centre := UiTheme.vbox(8)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(centre)
	_board = BoardScene.new()
	_board.name = "stage"
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.tile_clicked.connect(Callable(self, "_on_tile_clicked"))
	centre.add_child(_board)
	_console = ActionPanel.new()
	_console.name = "act"
	_console.action_requested.connect(Callable(self, "_on_action"))
	_console.start_requested.connect(func() -> void: settings_requested.emit())
	centre.add_child(_console)

	# right column: toasts, journal, inspector
	_rightcol = UiTheme.vbox(8)
	_rightcol.name = "rightcol"
	_rightcol.custom_minimum_size.x = DOCK_R
	_rightcol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_rightcol)
	_toasts = ToastList.new()
	_toasts.name = "toast"
	_rightcol.add_child(_toasts)
	_journal = JournalPanel.new()
	_journal.name = "journal"
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rightcol.add_child(_journal)
	_inspector = TileInspector.new()
	_inspector.name = "inspector"
	_inspector.action_requested.connect(Callable(self, "_on_inspector_action"))
	_rightcol.add_child(_inspector)

	_build_compact_shell(body)

	_modals = ModalHost.new()
	_modals.name = "modal"
	add_child(_modals)
	# the modals collect PARAMETERS the engine needs; the shell submits them like any button
	_modals.trade_submitted.connect(_on_trade_submitted)
	_modals.trade_answered.connect(_on_trade_answered)
	_modals.auction_bid.connect(_on_auction_bid)
	_modals.auction_pass.connect(_on_auction_pass)

	_apply_profile()
	# SG-08: one switch retranslates everything in place - no rebuild, no stale language
	if not I18n.inst().locale_changed.is_connected(Callable(self, "_on_locale_changed")):
		I18n.inst().locale_changed.connect(Callable(self, "_on_locale_changed"))


func set_profile(pr) -> void:
	_profile = pr
	_apply_profile()


func _apply_profile() -> void:
	# compact: the docks collapse into 48px rails whose content opens as 320px drawers over
	# the stage (the mockup's `data-profile="compact"`). The old version only HID the docks,
	# so the journal, the inspector and - through the inspector - every tile-management path
	# vanished on a small window (the audit's compact defect).
	var compact := _is_compact()
	if _seats_panel != null:
		_seats_panel.visible = not compact
	if _rightcol != null:
		_rightcol.visible = not compact
	if _rail_left != null:
		_rail_left.visible = compact
	if _rail_right != null:
		_rail_right.visible = compact
	if not compact:
		_close_all_drawers()
	else:
		_layout_drawers()


func _is_compact() -> bool:
	return size.x > 0.0 and (size.x < 1280.0 or size.y <= 700.0)


## SG-08 — live locale: static labels come back via their `i18n_key` metadata (I18n.relabel
## walks this subtree), state-driven panels re-render from the last state they were given, and
## the compact rails/drawers get their titles re-derived. Nothing here needs a match rebuild.
func _on_locale_changed(_loc: String) -> void:
	I18n.relabel(self)
	if _top != null and _top.has_method("retranslate"):
		_top.retranslate()
	if _seats_panel != null and _seats_panel.has_method("retranslate"):
		_seats_panel.retranslate()
	if _console != null and _console.has_method("retranslate"):
		_console.retranslate()
	if _inspector != null and _inspector.has_method("retranslate"):
		_inspector.retranslate()
	if _journal != null and _journal.has_method("retranslate"):
		_journal.retranslate()
	if _rail_left != null:
		(_rail_left as RailPanel).set_title(I18n.t("ui.players"))
	if _rail_r_journal != null:
		(_rail_r_journal as RailPanel).set_title(I18n.t("jrn.title"))
	if _rail_r_inspector != null:
		(_rail_r_inspector as RailPanel).set_title(I18n.t("ins.title"))


## The compact shell: two 48px rails replace the docks; each rail click opens the matching
## 320px drawer (DrawerPanel) that carries the dock's content over the stage. The rail itself
## never expands in place - on an 1100px window a 268px dock eats a third of the board, which
## is what the rails exist for.
func _build_compact_shell(body: Control) -> void:
	_rail_left = RailPanel.new()
	_rail_left.name = "rail-left"
	(_rail_left as RailPanel).setup(UiTheme.skin(), "ui.players", true)
	(_rail_left as RailPanel).set_title(I18n.t("ui.players"))
	(_rail_left as RailPanel).set_collapsed(true, false)
	(_rail_left as RailPanel).toggled.connect(
		func(_c: bool) -> void: _toggle_drawer("seats", _rail_left))
	body.add_child(_rail_left)
	body.move_child(_rail_left, 1)   # left of the stage

	_rail_right = UiTheme.panel()
	_rail_right.name = "rail-right"
	_rail_right.custom_minimum_size.x = 48.0
	var rail_col := UiTheme.vbox(4)
	_rail_right.add_child(rail_col)
	_rail_r_journal = RailPanel.new()
	(_rail_r_journal as RailPanel).name = "rail-right-journal"
	(_rail_r_journal as RailPanel).setup(UiTheme.skin(), "jrn.title", false)
	(_rail_r_journal as RailPanel).set_title(I18n.t("jrn.title"))
	(_rail_r_journal as RailPanel).set_collapsed(true, false)
	(_rail_r_journal as RailPanel).toggled.connect(
		func(_c: bool) -> void: _toggle_drawer("journal", _rail_r_journal))
	rail_col.add_child(_rail_r_journal)
	_rail_r_inspector = RailPanel.new()
	(_rail_r_inspector as RailPanel).name = "rail-right-inspector"
	(_rail_r_inspector as RailPanel).setup(UiTheme.skin(), "ins.title", false)
	(_rail_r_inspector as RailPanel).set_title(I18n.t("ins.title"))
	(_rail_r_inspector as RailPanel).set_collapsed(true, false)
	(_rail_r_inspector as RailPanel).toggled.connect(
		func(_c: bool) -> void: _toggle_drawer("inspector", _rail_r_inspector))
	rail_col.add_child(_rail_r_inspector)
	body.add_child(_rail_right)

	_rail_left.visible = false
	_rail_right.visible = false

	for spec in [["seats", "ui.players"], ["journal", "jrn.title"], ["inspector", "ins.title"]]:
		var d := DrawerPanel.new()
		d.name = "drawer-%s" % str(spec[0])
		d.set_title_key(str(spec[1]))
		d.visible = false
		d.closed.connect(func() -> void: _close_drawer(str(spec[0])))
		add_child(d)
		_drawers[str(spec[0])] = d


func _toggle_drawer(which: String, rail: Control) -> void:
	var d = _drawers.get(which)
	if d == null:
		return
	if (d as Control).visible:
		_close_drawer(which)
	else:
		_open_drawer(which)
	# the rail snaps back to its 48px strip; the drawer carries the content
	if rail is RailPanel:
		(rail as RailPanel).set_collapsed(true, false)


func _open_drawer(which: String) -> void:
	_close_all_drawers()
	var d = _drawers.get(which)
	if d == null:
		return
	match which:
		"seats":
			(d as DrawerPanel).put(_seats_panel)
		"journal":
			(d as DrawerPanel).put(_journal)
		"inspector":
			(d as DrawerPanel).put(_inspector)
	_layout_drawers()
	(d as Control).visible = true


## Return the content to its dock and hide the drawer. The dock's visibility follows the
## profile (hidden in compact), so returning a panel here must not flash it on screen.
func _close_drawer(which: String) -> void:
	var d = _drawers.get(which)
	if d == null or not (d as Control).visible:
		return
	var c := (d as DrawerPanel).take()
	if c != null:
		match which:
			"seats":
				_body_row.add_child(c)
				_body_row.move_child(c, 0)
				(c as Control).visible = not _is_compact()
			"journal":
				_rightcol.add_child(c)
				_rightcol.move_child(c, 1)
			"inspector":
				_rightcol.add_child(c)
				_rightcol.move_child(c, 2)
	(d as Control).visible = false


func _close_all_drawers() -> void:
	for which in _drawers.keys():
		_close_drawer(str(which))


## The drawers float over the stage: the seats drawer beside rail-left, the journal/inspector
## drawers beside rail-right.
func _layout_drawers() -> void:
	var w := 320.0
	var h := maxf(180.0, size.y - 96.0 - 120.0)
	for which in _drawers.keys():
		var d: Control = _drawers[which]
		d.custom_minimum_size = Vector2(w, h)
		d.size = Vector2(w, h)
		if str(which) == "seats":
			d.position = Vector2(8.0 + 48.0 + 8.0, 72.0)
		else:
			d.position = Vector2(maxf(0.0, size.x - 8.0 - 48.0 - 8.0 - w), 72.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_profile()


## Cold start: an empty board with the watermark and a console that says the match has
## not begun and offers START.
func setup_cold(launcher) -> void:
	_cold = true
	if _console != null and _console.has_method("set_cold"):
		_console.set_cold(true)
	if _board != null and _board.has_method("set_cold"):
		_board.set_cold()
	if _top != null and _top.has_method("set_cold"):
		_top.set_cold()
	_apply_profile()


func setup(eng, mgr, seat_list: Array, s) -> void:
	_engine = eng
	_mgr = mgr
	seats = seat_list
	_cold = false
	# a new match starts with an empty feed: the journal keeps raw events for its filters and
	# re-formats them on locale change (SG-06/SG-08), so it must not carry the last match's
	if _journal != null:
		_journal.clear_rows()
		if _journal.has_method("set_seats"):
			_journal.set_seats(seats)
	# WHO PLAYS HERE: the seat driven by a human (LOCAL/ADMIN), whoever that is. The old
	# `_human_pid = 0` was right only by convention, and only on the host: any other ordering
	# (or a client) got a screen whose buttons could never appear or played the wrong seat.
	_human_pid = -1
	for s2 in seats:
		if str(s2.input_driver) == "LOCAL" or str(s2.input_driver) == "ADMIN":
			_human_pid = int(s2.pid)
			break
	if _mgr != null and _mgr.has_signal("events_emitted"):
		if not _mgr.events_emitted.is_connected(Callable(self, "_on_events")):
			_mgr.events_emitted.connect(Callable(self, "_on_events"))
	# the manager pushes a fresh spectator projection on every state change; the shell
	# follows it (this is the wire the local match paints from)
	if _mgr != null and _mgr.has_signal("state_changed"):
		if not _mgr.state_changed.is_connected(Callable(self, "apply_projection")):
			_mgr.state_changed.connect(Callable(self, "apply_projection"))
	if _console != null:
		_console.set_cold(false)
		_console.set_observer(_observer)
	if _board != null:
		_board.set_watermark(false)
	_sync_all()


func on_game_started() -> void:
	_cold = false
	if _board != null:
		_board.set_watermark(false)
	if _console != null:
		_console.set_cold(false)
	_sync_all()


func on_overlay_closed() -> void:
	pass


## A client learned which seat it owns (the host answered JOINED). Buttons may now appear
## on this client's own turn.
func set_human_pid(pid: int) -> void:
	_human_pid = pid
	_sync_all()


## This screen is a REMOTE client: intents go over the wire (the host validates). Set on JOINED.
func set_remote_session(sess) -> void:
	_remote = sess


## The host refused an intent from this client. Say why in the player's language.
func show_rejection(reason: String) -> void:
	if _modals != null:
		_modals.show_message(I18n.t("gv.rejected_title"), I18n.t("gv.rejected_body", [reason]))


## Main pushes the spectator projection (local engine or the wire).
func apply_projection(proj: Dictionary) -> void:
	_proj = proj
	if _cold:
		_cold = false
		if _console != null:
			_console.set_cold(false)
		if _board != null:
			_board.set_watermark(false)
	_sync_all()


func _sync_all() -> void:
	if _proj.is_empty():
		return
	_sync_modals()
	if _top != null:
		_top.sync(_proj, seats)
	if _seats_panel != null:
		_seats_panel.sync(_proj, seats)
	var holder := -1
	var legal: Array = []
	if _engine != null:
		holder = SeatManager.find_decision_holder(_engine, _engine.player_count())
		if holder >= 0:
			legal = _engine.legal_actions(holder)
	else:
		holder = int(_proj.get("holder", -1))
		legal = _proj.get("legal", [])
	if _board != null:
		_board.sync(_proj, seats, _human_pid)
	if _console != null:
		_console.sync(holder, legal, holder == _human_pid and not _observer, _proj, seats)
	if _inspector != null:
		_inspector.sync(_proj, seats, legal, _human_pid)


func _on_tile_clicked(idx: int) -> void:
	if _inspector != null:
		_inspector.select(idx)
	if _board != null and _board.has_method("set_selected"):
		_board.set_selected(idx)


## Every console/board action funnels here. ACTIONS THAT NEED PARAMETERS OPEN A DIALOG —
## the audit's defect was exactly this: `action_requested(act, {})` sent an empty dict for
## all of them, and the engine refused six of thirteen buttons on every turn.
func _on_action(action: String, params: Dictionary) -> void:
	match action:
		"bid":
			_modals.show_auction(_proj, seats, _human_pid)
			return
		"propose_trade":
			_modals.show_trade_composer(_proj, seats, _human_pid)
			return
		"respond_trade":
			var pend: Dictionary = _proj.get("pending", {})
			if str(pend.get("type", "")) != "trade":
				return   # nothing to respond to (the button should not have been drawn)
			_modals.show_trade_response(_proj, seats)
			return
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			# tile-addressed actions: the inspector's selection is the address. With no tile
			# picked, say how to pick one instead of sending `{}` to be refused "tile required".
			var tile := int(_inspector.selected) if _inspector != null else -1
			var mine := false
			for t in (_proj.get("board", []) as Array):
				if int(t.get("index", -1)) == tile and int(t.get("owner", -1)) == _human_pid:
					mine = true
					break
			if tile < 0 or not mine:
				_modals.show_message(I18n.t("gv.select_tile"), I18n.t("gv.select_tile_body"))
				return
			_submit(_human_pid, action, {"tile": tile})
			return
	_submit(_human_pid, action, params)


func _on_trade_submitted(to: int, give_tiles: Array, give_cash: int, want_tiles: Array, want_cash: int) -> void:
	_submit(_human_pid, "propose_trade", {
		"to": to, "give_tiles": give_tiles, "give_cash": give_cash,
		"want_tiles": want_tiles, "want_cash": want_cash,
	})


func _on_trade_answered(accept: bool) -> void:
	_submit(_human_pid, "respond_trade", {"accept": accept})


func _on_auction_bid(amount: int) -> void:
	_submit(_human_pid, "bid", {"amount": amount})


func _on_auction_pass() -> void:
	_submit(_human_pid, "pass", {})


func _on_inspector_action(tile: int, op: String) -> void:
	_submit(_human_pid, op, {"tile": tile})


func _submit(pid: int, action: String, params: Dictionary) -> void:
	# A CLIENT SUBMITS OVER THE WIRE. It has no manager and no engine: `_mgr.push_intent` was
	# the only path, so in the joined browser every press died here — the audit's "консольные
	# кнопки" defect, one layer down. The host still validates everything; the verdict comes
	# back on the same socket (main -> show_rejection on refusal).
	if _remote != null and _remote.has_method("is_joined") and _remote.is_joined():
		_remote.act(action, params)
		return
	if _mgr == null:
		return
	if pid < 0:
		# nobody local plays on this screen (observer/no LOCAL seat): nothing may be sent
		return
	var res: Dictionary = _mgr.push_intent(pid, action, params)
	if not res.get("ok", false):
		show_rejection(str(res.get("reason", "?")))


## Engine/manager events → toasts, journal rows and board animations.
func _on_events(events: Array) -> void:
	for ev in events:
		var e: Dictionary = ev
		var kind: String = str(e.get("type", ""))
		if _toasts != null:
			_toasts.show_event_toast(e)
		var data: Dictionary = e.get("data", {})
		if _journal != null:
			# SG-06: the line comes from the ADAPTER + the projection's tile names - never from
			# the raw engine type ("free_parking") and never as "клетка N".
			var ctx := _journal_ctx()
			var line: Dictionary = _journal_lines.line_for(e, ctx)
			if not line.is_empty():
				_journal.append(e, ctx)
				if _console != null and _is_compact():
					# compact: the journal lives behind rail-right; the newest event shows as the
					# console's one-line ticker (the registry's own wording for the compact toast)
					var who_line := str(line.get("who", ""))
					var text_line := str(line.get("text", ""))
					_console.show_ticker(text_line if who_line == "" else "%s · %s" % [who_line, text_line],
						str(line.get("cat", "info")))
		if _board != null:
			# board animations: rolls tumble the tray, moves hop the tokens
			if kind == "roll":
				_board.play_event({"k": "roll", "a": int(data.get("d1", 1)), "b": int(data.get("d2", 1))})
			elif kind in ["move", "teleport"]:
				var pid := _pid_of(str(data.get("player", "")))
				_board.play_event({"k": "move", "p": pid, "ti": int(data.get("to", data.get("tile", -1)))})


func _pid_of(name: String) -> int:
	for s in seats:
		if str(s.name) == name:
			return int(s.pid)
	return -1


## SG-06 rendering context for one journal batch: seat names/colours and the projection's tile
## NAMES. Rebuilt per batch - seats and the board change while the match runs.
func _journal_ctx() -> Dictionary:
	var names := {}
	var colors := {}
	for s in seats:
		names[int(s.pid)] = str(s.name)
		colors[int(s.pid)] = s.color
	var tiles := {}
	for t in (_proj.get("board", []) as Array):
		tiles[int(t.get("index", -1))] = str(t.get("name", ""))
	return {"names": names, "colors": colors, "tiles": tiles, "dim": UiTheme.COL().text_dim}


## A modal that shows LIVE state must follow that state: a bid re-raised by the next player
## refreshes the auction sheet (keeping what was half-typed), and a dialog whose subject is
## gone (lot sold, trade resolved) closes itself instead of lying.
func _sync_modals() -> void:
	if _modals == null or not _modals.is_open():
		return
	var pend: Dictionary = _proj.get("pending", {})
	var ptype := str(pend.get("type", ""))
	if _modals.kind == "auction":
		if ptype != "auction":
			_modals.close()
		elif int(pend.get("high", -1)) != int(_modals.get("_a_high")):
			_modals.show_auction(_proj, seats, _human_pid)
	elif _modals.kind == "trade_response":
		if ptype != "trade":
			_modals.close()
	elif _modals.kind == "trade_composer":
		if ptype == "trade":
			_modals.close()   # a trade is already on the table: the composer is out of date


func show_game_over(winner_name: String) -> void:
	if _modals != null:
		# `modal.game_over` / `modal.winner` are the keys the v3 sheet declares for exactly this
		# message (they sat unused while the shell asked for `over.title`/`over.winner`, two keys
		# nobody had ever written - the game-over modal showed `{over.title}` to the player).
		_modals.show_message(I18n.t("modal.game_over"), I18n.t("modal.winner", [winner_name]))
	if _toasts != null:
		_toasts.show_event_toast({"type": "winner", "data": {"player": winner_name}})
