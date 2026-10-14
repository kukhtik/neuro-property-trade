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
var _human_pid := 0

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

	_modals = ModalHost.new()
	_modals.name = "modal"
	add_child(_modals)

	_apply_profile()


func set_profile(pr) -> void:
	_profile = pr
	_apply_profile()


func _apply_profile() -> void:
	# compact: the docks collapse, the board keeps the room (proto data-profile="compact")
	var compact := size.x > 0.0 and (size.x < 1280.0 or size.y <= 700.0)
	if _seats_panel != null:
		_seats_panel.visible = not compact
	if _rightcol != null:
		_rightcol.visible = not compact


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
	_human_pid = 0
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


func _on_action(action: String, params: Dictionary) -> void:
	_submit(_human_pid, action, params)


func _on_inspector_action(tile: int, op: String) -> void:
	_submit(_human_pid, op, {"tile": tile})


func _submit(pid: int, action: String, params: Dictionary) -> void:
	if _mgr == null:
		return
	var res: Dictionary = _mgr.push_intent(pid, action, params)
	if not res.get("ok", false):
		if _modals != null:
			_modals.show_message(I18n.t("gv.rejected_title"), I18n.t("gv.rejected_body", [str(res.get("reason", "?"))]))


## Engine/manager events → toasts, journal rows and board animations.
func _on_events(events: Array) -> void:
	for ev in events:
		var e: Dictionary = ev
		var kind: String = str(e.get("type", ""))
		if _toasts != null:
			_toasts.show_event_toast(e)
		var data: Dictionary = e.get("data", {})
		if _journal != null:
			var who := str(data.get("player", ""))
			var who_col: Color = UiTheme.COL().text
			for s in seats:
				if str(s.name) == who:
					who_col = s.color
			var key := "event_type." + kind
			var text: String = I18n.t(key) if I18n.has(key) else kind
			if data.has("amount"):
				text += "  $%d" % int(data.get("amount", 0))
			_journal.append({"who": who, "who_color": who_col, "text": text, "tag": kind})
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


func show_game_over(winner_name: String) -> void:
	if _modals != null:
		# `modal.game_over` / `modal.winner` are the keys the v3 sheet declares for exactly this
		# message (they sat unused while the shell asked for `over.title`/`over.winner`, two keys
		# nobody had ever written - the game-over modal showed `{over.title}` to the player).
		_modals.show_message(I18n.t("modal.game_over"), I18n.t("modal.winner", [winner_name]))
	if _toasts != null:
		_toasts.show_event_toast({"type": "winner", "data": {"player": winner_name}})
