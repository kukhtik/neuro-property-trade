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

const _TOP_H := 34
const _ACTION_H := 64
const _MIN_PANEL_W := 150
const _MIN_JOURNAL_W := 180

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
var _journal
var _jpanel: PanelContainer
var _last_vp := Vector2.ZERO
var _center: HBoxContainer   # players | board | journal (ties the panels together)
var _cold := true
var _game_over_shown := false

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
	_board_scene.tile_clicked.connect(_on_tile_clicked)
	# HUD refresh on every seat-manager tick
	manager.state_changed.connect(_on_state_changed)
	_top.settings_requested.connect(_on_settings_requested)
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

	# right journal panel (fixed proportional width)
	_jpanel = UiTheme.panel()
	_jpanel.custom_minimum_size.x = _journal_w()
	_jpanel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_center.add_child(_jpanel)
	var jm := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		jm.add_theme_constant_override(edge, 8)
	_jpanel.add_child(jm)
	var jv := UiTheme.vbox(4)
	jm.add_child(jv)
	jv.add_child(UiTheme.label("◆ ХОД СОБЫТИЙ", 12, UiTheme.COL.accent))
	_journal = UiTheme.label("", 12)
	_journal.custom_minimum_size.y = 0
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jv.add_child(_journal)

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
	var is_human: bool = (holder == _human_pid)
	var legal: Array = []
	if holder >= 0:
		legal = engine.legal_actions(holder)
	_actions.sync(holder, legal, is_human, proj, seats)

func _refresh_journal() -> void:
	if engine == null or _journal == null:
		return
	var entries: Array = engine.log.entries()
	var start: int = maxi(0, entries.size() - 10)
	var lines: Array[String] = []
	for i in range(start, entries.size()):
		lines.append(EventMessages.describe(entries[i]))
	_journal.text = "\n".join(lines)

func _on_tile_clicked(idx: int) -> void:
	_inspector.select(idx)
	if engine == null:
		return
	var sp := ProjectionScript.new().for_spectator(engine)
	_inspector.sync(sp, seats)

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
