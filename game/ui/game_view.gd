class_name GameView
extends Control
## Full playable game screen: top bar + players panel (left) + board (center)
## + tile inspector + action panel (bottom) + modal host + journal (right).
## Wires the human LOCAL seat's clicks to seat_manager.push_intent. AI/CHAT
## seats self-drive in the manager. HUD reads the spectator projection;
## the human seat's legal actions come from engine.legal_actions. Shape-only
## UI (UiTheme) so art can replace shapes later without logic changes.
##
## v2 one-screen: the board is always the root. Before START the board is
## "cold" (no engine) and the action panel shows a single START button.

const UiTheme := preload("res://ui/theme.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const TopBar := preload("res://ui/top_bar.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const TileInspector := preload("res://ui/tile_inspector.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const ProjectionScript := preload("res://sdk/projection.gd")
const EventMessages := preload("res://visual/event_messages.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const ToastStack := preload("res://ui/toast.gd")
const JournalPanel := preload("res://ui/journal_panel.gd")

const _TOP_H := 34
const _ACTION_H := 64
const _MIN_PANEL_W := 150
const _MIN_JOURNAL_W := 180
const _OBSERVER_JOURNAL_W := 380   # spec §7: observer layout widens the journal

signal restart_requested
signal settings_requested

var engine
var manager
var seats: Array = []
var settings

var _launcher
var _human_pid := -1
var _board_scene
var _top
var _players
var _actions
var _inspector
var _modals
var _journal           # JournalPanel now (was a bare Label)
var _jpanel: PanelContainer
var _last_vp := Vector2.ZERO
var _center: HBoxContainer   # players | board | journal (ties the panels together)
var _cold := true
var _game_over_shown := false
var _toast_stack: ToastStack
var _observer := false         # spec §7: match has no LOCAL seat (host watches)
var _follow_pid := -1          # spectator follow target (clicked player row)
var _holder_name := ""         # current decision holder display name

## Cold setup: build the layout with no engine. The board renders empty and the
## action panel shows a single START button. Called once at launch.
func setup_cold(launcher) -> void:
	_launcher = launcher
	_cold = true
	_build_layout()
	_layout()
	# cold board: no engine, so just build the empty board scene
	_board_scene.setup(null, null)
	_top.set_cold(true)
	_actions.set_cold(true)
	_sync_cold()
	
	# P3: Create toast stack (always on top)
	_toast_stack = ToastStack.new()
	_toast_stack.name = "ToastStack"
	add_child(_toast_stack)

## Full setup after the engine is built (START / restart).
func setup(eng, mgr, seat_list: Array, s) -> void:
	# restart: this same GameView instance is re-setup, so disconnect any
	# previously-connected signals before reconnecting (avoids duplicate errors)
	if _board_scene != null and _board_scene.tile_clicked.is_connected(_on_tile_clicked):
		_board_scene.tile_clicked.disconnect(_on_tile_clicked)
	if _top != null and _top.settings_requested.is_connected(_on_settings_requested):
		_top.settings_requested.disconnect(_on_settings_requested)
	if _modals != null and _modals.sound_toggled.is_connected(_on_sound_toggled):
		_modals.sound_toggled.disconnect(_on_sound_toggled)
	if manager != null and manager.state_changed.is_connected(_on_state_changed):
		manager.state_changed.disconnect(_on_state_changed)
	# P3: disconnect toast stack events
	if manager != null and manager.events_emitted.is_connected(_on_events_emitted):
		manager.events_emitted.disconnect(_on_events_emitted)

	engine = eng
	manager = mgr
	seats = seat_list
	settings = s
	_cold = false
	_game_over_shown = false
	for seat in seats:
		if str(seat.input_driver) in ["LOCAL", "ADMIN"]:
			_human_pid = int(seat.pid)
			break
	# board fills the center region (between left panel, top bar, journal, action bar)
	_board_scene.setup(engine, settings, seats)
	_layout()
	var bs = _board_scene
	if bs.has_node("EventOverlay"):
		bs.get_node("EventOverlay").visible = false
	if _board_scene != null and _board_scene.tile_hovered.is_connected(_on_tile_hovered):
		_board_scene.tile_hovered.disconnect(_on_tile_hovered)
	_board_scene.tile_clicked.connect(_on_tile_clicked)
	_board_scene.tile_hovered.connect(_on_tile_hovered)
	# HUD refresh on every seat-manager tick
	manager.state_changed.connect(_on_state_changed)
	# P4 observer: click a player row to follow them
	if _players.player_clicked.is_connected(_on_player_row_clicked):
		_players.player_clicked.disconnect(_on_player_row_clicked)
	_players.player_clicked.connect(_on_player_row_clicked)
	# P3: connect events to toast stack
	manager.events_emitted.connect(_on_events_emitted)
	_top.settings_requested.connect(_on_settings_requested)
	if _top.observer_toggle_requested.is_connected(_on_eye_requested):
		_top.observer_toggle_requested.disconnect(_on_eye_requested)
	_top.observer_toggle_requested.connect(_on_eye_requested)
	_modals.sound_toggled.connect(_on_sound_toggled)
	_top.set_cold(false)
	_actions.set_cold(false)
	_refresh_journal()
	_sync_all()

## Called by main.gd after the engine is built and setup() ran.
func on_game_started() -> void:
	_sync_all()

## Called by main.gd when the overlay is closed without starting (ESC).
func on_overlay_closed() -> void:
	if _cold:
		_sync_cold()

## Show the game-over results banner (winner, turns, capital) with [Реванш]
## and [Настройки] buttons.
func show_game_over(winner_name: String) -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	var proj := ProjectionScript.new().for_spectator(engine)
	var players: Array = proj.get("players", [])
	var winner: Dictionary = {}
	for p in players:
		if str(p.get("name", "")) == winner_name:
			winner = p
			break
	var turns: int = _count_turns()
	var capital: int = int(winner.get("money", 0))
	_modals.show_game_over(winner_name, turns, capital, players.size())

func _count_turns() -> int:
	if engine == null or engine.log == null:
		return 0
	return engine.log.entries_of_type("roll").size()

## Proportional panel sizes derived from the current viewport, so the layout
## adapts to any resolution (A1). Left players panel and right journal are
## fractions of the width; the board fills the remaining center region.
func _panel_w() -> int:
	return maxi(_MIN_PANEL_W, int(size.x * 0.12))

func _journal_w() -> int:
	# observer layout (spec §7): the journal widens to carry 100+ lines
	if _observer:
		return _OBSERVER_JOURNAL_W
	return maxi(_MIN_JOURNAL_W, int(size.x * 0.14))

func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_rect()

	# top bar (anchored top-wide)
	_top = TopBar.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.anchor_right = 1.0
	_top.offset_bottom = 34
	add_child(_top)

	# CENTER ROW: players | board | journal — a single HBox so the three panels
	# are tied together and the board always fills the space between them.
	_center = HBoxContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.anchor_top = 0.0
	_center.offset_top = 34
	_center.offset_bottom = -_ACTION_H
	_center.add_theme_constant_override("separation", 8)
	add_child(_center)

	# left players panel (fixed proportional width)
	_players = PlayersPanel.new()
	_players.custom_minimum_size.x = _panel_w()
	_players.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_center.add_child(_players)

	# board (center) — expands to fill whatever the side panels leave
	_board_scene = BoardScene.new()
	_board_scene.name = "BoardScene"
	_board_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_scene.set_managed_by_container(true)
	_center.add_child(_board_scene)

	# right journal panel (fixed proportional width) — P4: full JournalPanel
	# (filters + export + auto-scroll), replaces the bare 10-line label.
	_jpanel = UiTheme.panel()
	_jpanel.custom_minimum_size.x = _journal_w()
	_jpanel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_center.add_child(_jpanel)
	_journal = JournalPanel.new()
	_journal.name = "JournalPanel"
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.exported.connect(_on_journal_exported)
	_jpanel.add_child(_journal)

	# modal host (above everything)
	_modals = ModalHost.new()
	_modals.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modals.visible = false
	add_child(_modals)
	_connect_modals()

	# bottom action panel
	_actions = ActionPanel.new()
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.anchor_top = 1.0
	_actions.offset_top = -_ACTION_H
	_actions.offset_bottom = 0
	_actions.anchor_right = 1.0
	_actions.offset_right = 0
	add_child(_actions)
	_actions.action_requested.connect(_on_action_requested)
	_actions.start_requested.connect(_on_start_requested)

	# tile inspector above the action panel (bottom-left), clear of the buttons
	_inspector = TileInspector.new()
	_inspector.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_inspector.offset_left = 8
	_inspector.offset_top = -(_ACTION_H + 8 + 90)   # above the action bar
	_inspector.offset_right = 360
	_inspector.offset_bottom = -(_ACTION_H + 8)
	add_child(_inspector)

## Recompute the proportional panel sizes + board frame. Called on setup and
## whenever the viewport size changes (A1). The HBox re-sizes the side panels
## and the board fills the remaining center region automatically.
func _layout() -> void:
	if _players == null or _jpanel == null or _board_scene == null:
		return
	var pw := _panel_w()
	var jw := _journal_w()
	_players.custom_minimum_size.x = pw
	_jpanel.custom_minimum_size.x = jw
	# the board scene fills the center region between the panels (HBox handles it)
	_board_scene.set_frame(Rect2(0, 0, 0, 0))   # signal it to re-fit its own rect

func _process(delta: float) -> void:
	# A1: re-layout when the viewport size changes (window resize / different screen)
	var vp := get_viewport()
	if vp != null:
		var v := vp.get_visible_rect().size
		if v != _last_vp:
			_last_vp = v
			_apply_rect()
			_layout()

func _apply_rect() -> void:
	var vp = get_viewport()
	var r := Rect2()
	if vp != null:
		r = vp.get_visible_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		r = Rect2(0, 0, 1152, 648)
	position = r.position
	size = r.size

func _sync_cold() -> void:
	_top.sync_cold()
	_players.sync_cold()
	_actions.set_cold(true)
	_inspector.clear()

func _on_state_changed(_proj: Dictionary) -> void:
	_sync_all()
	_refresh_journal()

func _sync_all() -> void:
	if engine == null:
		return
	var sp := ProjectionScript.new().for_spectator(engine)
	_sync_from_spectator(sp)

func _sync_from_spectator(proj: Dictionary) -> void:
	_top.sync(proj, seats)
	_players.sync(proj, seats)
	_inspector.sync(proj, seats)
	var holder: int = SeatManager.find_decision_holder(engine, engine.player_count())

	# P4 §7: observer mode = no LOCAL seat in the match. Detect from seats.
	var has_local := false
	for s in seats:
		if str(s.input_driver) == "LOCAL":
			has_local = true
			break
	_set_observer(not has_local)
	_top.set_observer(not has_local)

	var is_human: bool = (holder == _human_pid)
	var legal: Array = []
	if holder >= 0:
		legal = engine.legal_actions(holder)
	_actions.sync(holder, legal, is_human, proj, seats)

	# observer extras: decision-holder status + follow-highlight of tiles
	if _observer:
		_holder_name = _holder_display_name(holder, proj)
		# follow: highlight the followed player's tiles on the board
		var targets: Array = []
		if _follow_pid >= 0:
			var players: Array = proj.get("players", [])
			for p in players:
				if int(p.get("index", -1)) == _follow_pid:
					targets = (p.get("tiles", []) as Array).duplicate()
					break
		if _board_scene != null and _board_scene._board != null:
			_board_scene._board.set_target_tiles(targets)
	elif _board_scene != null and _board_scene._board != null:
		# clear stale follow-highlight when returning to a LOCAL match
		_board_scene._board.set_target_tiles([])

## Display name of the current decision holder (or an idle/waiting label).
func _holder_display_name(holder: int, proj: Dictionary) -> String:
	if holder < 0:
		return "—"
	var players: Array = proj.get("players", [])
	for p in players:
		if int(p.get("index", -1)) == holder:
			return str(p.get("name", "?"))
	return "P%d" % holder

## Spectator control: click a player row in the left panel to follow them
## (their tiles get the soft target highlight on the board).
func follow_player(pid: int) -> void:
	_follow_pid = pid
	_sync_all()

func _refresh_journal() -> void:
	if engine == null or _journal == null:
		return
	var names: Array = []
	for i in engine.player_count():
		names.append(str(engine.player(i).name))
	_journal.set_entries(engine.log.entries(), names)

func _on_journal_exported(path: String) -> void:
	if path == "":
		_modals.show_message("Экспорт журнала", "Не удалось записать файл.")
	else:
		_modals.show_message("Журнал экспортирован", "Файл: " + path)

## P4 spec §7: observer layout — the match has no LOCAL seat. The action panel
## collapses to a thin status bar (0 buttons), the journal widens, and the
## human seat list disables "your turn" affordances.
func _set_observer(v: bool) -> void:
	if _observer == v:
		return
	_observer = v
	_follow_pid = -1
	_layout()
	if _actions != null and _actions.has_method("set_observer"):
		_actions.set_observer(v)

func _on_tile_clicked(idx: int) -> void:
	_inspector.select(idx)
	_mark_selected_tile(idx)

## P4 observer: clicking a player row follows (or unfollows) that player.
func _on_player_row_clicked(pid: int) -> void:
	follow_player(-1 if _follow_pid == pid else pid)

## P4 §7: hover a tile → the inspector opens on it (observer layout; hover is
## also fine in a LOCAL match — it's a non-destructive preview).
func _on_tile_hovered(idx: int) -> void:
	if engine == null:
		return
	_inspector.select(idx)

## P3: Handle events from seat manager for toast/banner display
func _on_events_emitted(events: Array) -> void:
	for ev in events:
		var type: String = ev.get("type", "")
		var data: Dictionary = ev.get("data", {})
		var msg: String = ""
		
		# Generate user-friendly messages for common event types
		match type:
			"purchase":
				msg = "%s купил %s за %s" % [data.get("player", "Игрок"), data.get("tile", "клетку"), data.get("price", "0")]
			"rent":
				msg = "%s платит аренду %s: %s" % [data.get("player", "Игрок"), data.get("owner", "владельцу"), data.get("amount", "0")]
			"pass_go":
				msg = "%s проходит Старт и получает %s" % [data.get("player", "Игрок"), data.get("amount", "200")]
			"jail":
				msg = "%s попал в тюрьму" % [data.get("player", "Игрок")]
			"mortgage":
				msg = "%s заложил %s за %s" % [data.get("player", "Игрок"), data.get("tile", "клетку"), data.get("amount", "0")]
			"unmortgage":
				msg = "%s выкупил %s за %s" % [data.get("player", "Игрок"), data.get("tile", "клетку"), data.get("amount", "0")]
			"build_house":
				msg = "%s построил дом на %s" % [data.get("player", "Игрок"), data.get("tile", "клетке")]
			"trade":
				msg = "%s обменялся с %s" % [data.get("player", "Игрок"), data.get("other", "игроком")]
			"bankrupt":
				msg = "%s обанкротился" % [data.get("player", "Игрок")]
			"turn_start":
				msg = "Ход: %s" % [data.get("player", "Игрок")]
			"roll":
				msg = "%s бросает: %s + %s = %s" % [data.get("player", "Игрок"), data.get("d1", 1), data.get("d2", 1), data.get("sum", 2)]
			"_":
				if data.has("message"):
					msg = str(data["message"])
		
		if msg != "":
			_toast_stack.show_toast(msg, type)

## P2: mark the selected tile on the board with a dashed accent frame
func _mark_selected_tile(idx: int) -> void:
	if _board_scene != null and _board_scene._board != null:
		_board_scene._board.set_selected_tile(idx)

func _connect_modals() -> void:
	_modals.build_requested.connect(_on_build)
	_modals.trade_proposed.connect(_on_trade_proposed)
	_modals.trade_responded.connect(_on_trade_responded)
	_modals.auction_bid.connect(_on_auction_bid)
	_modals.auction_pass.connect(_on_auction_pass)
	_modals.restart_requested.connect(_on_restart_requested)
	_modals.settings_requested.connect(_on_settings_requested)

func _on_start_requested() -> void:
	# cold state: the single START button opens the settings overlay
	settings_requested.emit()

func _on_restart_requested() -> void:
	restart_requested.emit()

func _on_action_requested(act: String, _params: Dictionary) -> void:
	match act:
		"roll", "buy", "pass", "pay", "use_card":
			_submit(_human_pid, act, {})
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			if _inspector.selected >= 0:
				var sp := ProjectionScript.new().for_spectator(engine)
				_modals.open_build(_inspector.selected, sp, "")
			else:
				_modals.show_message("Выберите тайл", "Кликните по тайлу на доске, который хотите изменить.")
		"propose_trade":
			var sp2 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade(sp2, seats, _human_pid)
		"respond_trade":
			var sp3 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade_response(sp3, seats)
		"bid":
			var sp4 := ProjectionScript.new().for_spectator(engine)
			_modals.open_auction(sp4, seats)

func _on_build(tile: int, op: String) -> void:
	_submit(_human_pid, op, {"tile": tile})
	_modals.close()

func _on_trade_proposed(to: int, give: Array, gcash: int, want: Array, wcash: int) -> void:
	_submit(_human_pid, "propose_trade", {
		"to": to, "give_tiles": give, "give_cash": gcash,
		"want_tiles": want, "want_cash": wcash,
	})
	_modals.close()

func _on_trade_responded(accept: bool) -> void:
	_submit(_human_pid, "respond_trade", {"accept": accept})
	_modals.close()

func _on_auction_bid(amount: int) -> void:
	_submit(_human_pid, "bid", {"amount": amount})
	_modals.close()

func _on_auction_pass() -> void:
	_submit(_human_pid, "pass", {})
	_modals.close()

func _on_settings_requested() -> void:
	settings_requested.emit()

## P4 §7: 👁 in TopBar (observer match) → back to the settings overlay.
func _on_eye_requested() -> void:
	settings_requested.emit()

func _on_sound_toggled(key: String, on: bool) -> void:
	if key == "sfx":
		_sfx_enabled = on
		if _board_scene != null and _board_scene._sfx != null:
			_board_scene._sfx.set_enabled(on)

var _sfx_enabled := true

func _submit(pid: int, action: String, params: Dictionary) -> void:
	if manager == null:
		return
	var res: Dictionary = manager.push_intent(pid, action, params)
	if not res.get("ok", false):
		_modals.show_message("Действие отклонено", "Причина: " + str(res.get("reason", "?")))
