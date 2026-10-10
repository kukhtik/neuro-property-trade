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
const Layout := preload("res://ui/core/layout_profile.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const RailPanel := preload("res://ui/components/rail_panel.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
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
const I18n := preload("res://i18n/i18n.gd")

const _TOP_H := 46   # body grid in the mockup: 46px header
const _ACTION_H := 72   # body grid in the mockup: 72px control bar
const _MIN_PANEL_W := 150
const _MIN_JOURNAL_W := 180
const _OBSERVER_JOURNAL_W := 380   # spec §7: observer layout widens the journal

signal restart_requested
signal settings_requested
signal skin_requested(skin_id: String)

var engine
var manager
var seats: Array = []
var settings

var _launcher
var _human_pid := -1
## The execution role for this process (player/stream/admin). Set by the
## launcher BEFORE setup_cold and kept across restarts, so a run never changes
## role mid-game. Components read it; none of them test it for game logic.
var _profile = UiProfileScript.for_id(UiProfileScript.PLAYER)
var _board_scene
var _top
var _players
var _actions
var _inspector
var _modals
var _journal           # JournalPanel now (was a bare Label)
var _players_rail           # RailPanel around the players panel
var _jpanel_rail            # RailPanel around the journal
var _skin                   # SkinManager shared by the rails
var _last_vp := Vector2.ZERO
var _center: HBoxContainer   # players | board | journal (ties the panels together)
var _cold := true
var _game_over_shown := false
var _toast_stack: ToastStack
var _event_overlay: Control   # P6 Phase 5: reparented stream feed (in the journal column)
var _overlay_wanted := false  # the user's event_overlay setting, kept across fits
var _observer := false         # spec §7: match has no LOCAL seat (host watches)
var _follow_pid := -1          # spectator follow target (clicked player row)

## Cold setup: build the layout with no engine. The board renders empty and the
## action panel shows a single START button. Called once at launch.
func setup_cold(launcher) -> void:
	_launcher = launcher
	_cold = true
	_skin = SkinManager.new()
	_skin.load_skin()
	UiTheme.use_skin(_skin)
	_build_layout()
	_apply_profile()
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


## Apply the execution role to the COLD screen.
##
## Without this the launcher looked identical for every role: `setup_cold` built the
## layout and never read `_profile`, so admin and the OBS window produced byte-identical
## frames. The role is chosen at launch, and the launch screen is the very first thing a
## person sees — it has to show which one they started.
func _apply_profile() -> void:
	if _profile == null:
		return
	if _actions != null:
		_actions.visible = _profile.shows_actions
	if _journal != null:
		_journal.visible = _profile.shows_journal
	# the stream wants bigger type: it is read from a video, at a distance
	if _profile.text_scale != 1.0 and _top != null and _top.has_method("scale_text"):
		_top.scale_text(_profile.text_scale)
	if _top != null and _top.has_method("set_profile"):
		_top.set_profile(_profile)

## Choose the execution role. Called by the launcher before the first frame, so
## the UI is built for the role from the start rather than switched into it.
func set_profile(pr) -> void:
	if pr == null:
		return
	_profile = pr
	if _top != null and _top.has_method("set_profile"):
		_top.set_profile(_profile)
	# the human seat only exists when this execution accepts input at all
	if not _profile.input_enabled:
		_human_pid = -1
	_layout()


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
	# P6 Phase 5: free a previously-reparented event overlay before the board
	# scene builds a fresh one (restart path), so we don't leak duplicates.
	if _event_overlay != null and is_instance_valid(_event_overlay):
		_event_overlay.queue_free()
		_event_overlay = null
	_human_pid = -1
	if _profile.input_enabled:
		for seat in seats:
			if str(seat.input_driver) in ["LOCAL", "ADMIN"]:
				_human_pid = int(seat.pid)
				break
	# board fills the center region (between left panel, top bar, journal, action bar)
	_board_scene.setup(engine, settings, seats)
	if _toast_stack != null and _board_scene != null and _board_scene._sfx != null:
		_toast_stack.set_sfx(_board_scene._sfx)
	# C3: toasts must sit BELOW the top row of board tiles (never cover the board).
	# The board scene's top edge is at _TOP_H (top bar) + its own margin; the
	# toast stack is a full-viewport CanvasLayer, so offset by the board's top.
	if _toast_stack != null and _board_scene != null:
		var bs_top: float = float(_TOP_H) + 8.0   # top bar + board margin
		var cell: float = float(_board_scene._cell)
		_toast_stack.set_board_top(bs_top, cell)
	_layout()
	# P6 Phase 5: the event overlay must NOT float over the board center. It is
	# reparented to the full viewport and anchored bottom-right (over the
	# journal), so it reads as a stream feed, not a board artifact. Visibility
	# is gated by settings.event_overlay (not unconditionally hidden).
	var bs = _board_scene
	if bs != null and bs.has_node("EventOverlay"):
		var ov = bs.get_node("EventOverlay")
		bs.remove_child(ov)
		add_child(ov)
		# Inside the journal column, never over the board: this is a stream feed,
		# and the board must stay whole (spec §6 / brief defect #4).
		ov.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_overlay_wanted = bool(settings.event_overlay) if settings != null else false
		ov.visible = _overlay_wanted
		_event_overlay = ov
		_fit_event_overlay()
		# keep it glued to the column on every relayout
		var jc = _jpanel_rail
		if jc != null and not resized.is_connected(_fit_event_overlay):
			resized.connect(_fit_event_overlay)
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
	if _top.skin_requested.is_connected(_on_skin_requested):
		_top.skin_requested.disconnect(_on_skin_requested)
	_top.skin_requested.connect(_on_skin_requested)
	if _top.observer_toggle_requested.is_connected(_on_eye_requested):
		_top.observer_toggle_requested.disconnect(_on_eye_requested)
	_top.observer_toggle_requested.connect(_on_eye_requested)
	_modals.sound_toggled.connect(_on_sound_toggled)
	_top.set_cold(false)
	_actions.set_cold(false)
	_refresh_journal()
	_sync_all()
	# P5: re-sync the persistent HUD when the interface language changes (the
	# panels re-run their I18n.t() calls on the next sync).
	if _locale_hooked and I18n.inst().locale_changed.is_connected(_on_locale_changed):
		I18n.inst().locale_changed.disconnect(_on_locale_changed)
	I18n.inst().locale_changed.connect(_on_locale_changed)
	_locale_hooked = true

var _locale_hooked := false

## P5: interface language changed → retranslate static HUD labels + resync.
func _on_locale_changed(_locale: String) -> void:
	I18n.relabel(self)
	if _top != null and _top.has_method("retranslate"):
		_top.retranslate()
	if _journal != null and _journal.has_method("retranslate"):
		_journal.retranslate()
	# CR-5: the tile inspector's placeholder is localized too
	if _inspector != null and _inspector.has_method("retranslate"):
		_inspector.retranslate()
	if engine != null:
		_sync_all()
		_refresh_journal()

## Called by main.gd after the engine is built and setup() ran.
## A networked client has no engine: the host sends the truth. Forward it to the board
## so the player SEES the match it is playing.
##
## The FIRST projection also means a match is running — a networked client never runs a
## local start, so without this it stays on the launcher for the entire match, playing
## correctly and showing nothing.
func apply_projection(proj: Dictionary) -> void:
	if _cold:
		_cold = false
		# hide the launcher overlay exactly as a local start does, then let the view
		# sync itself to the match it is now part of
		if _launcher != null and _launcher.get("_overlay") != null:
			_launcher.get("_overlay").visible = false
		on_game_started()
	if _board_scene != null and _board_scene.has_method("apply_projection"):
		_board_scene.apply_projection(proj)
	if _actions != null and _actions.has_method("set_legal"):
		_actions.set_legal(proj.get("legal", []))


func on_game_started() -> void:
	_sync_all()

## Called by main.gd when the overlay is closed without starting (ESC).
## Park the stream feed at the bottom of the journal column. Called on every
## relayout, so it tracks rail collapse and window resizes.
func _fit_event_overlay() -> void:
	if _event_overlay == null or not is_instance_valid(_event_overlay):
		return
	var col: Control = _jpanel_rail
	if col == null:
		return
	# Prefer the journal panel's own rect (settled once the container sorts); fall
	# back to the board's right edge plus the profile's column width.
	var r: Rect2
	if _journal != null and is_instance_valid(_journal) and _journal.size.x > 1.0:
		r = Rect2(_journal.global_position - global_position, _journal.size)
	elif _board_scene != null and _board_scene.size.x > 1.0:
		var bw: float = float(_bpl().right)
		var x0: float = _board_scene.global_position.x - global_position.x 			+ _board_scene.size.x
		r = Rect2(Vector2(minf(x0, size.x - bw), 0.0), Vector2(bw, size.y))
	else:
		return
	# A rail is only ~46 px wide; stacking the feed there would clip it to
	# nothing, so hide it while the journal is collapsed (the rail already
	# carries the event count).
	if r.size.x < 160.0:
		(_event_overlay as Control).visible = false
		return
	if _event_overlay.visible != _overlay_wanted:
		(_event_overlay as Control).visible = _overlay_wanted
	var w: float = maxf(160.0, r.size.x - 16.0)
	var h: float = minf(202.0, maxf(90.0, r.size.y * 0.34))
	(_event_overlay as Control).position = Vector2(r.position.x + 8.0,
		r.position.y + r.size.y - h - 8.0)
	(_event_overlay as Control).size = Vector2(w, h)


## Deferred re-fit: containers sort at the end of the frame, so the rects are
## only valid on the next one. `_fits_left` gives the first paint a couple of
## frames to settle, since a rail collapse moves the column again.
var _fit_event_overlay_pending := false
var _fits_left := 0


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
## adapts to any resolution (A1 + P5 §10 breakpoints). Left players panel and
## right journal are width-based per the §3.4 breakpoint table; the board fills
## the remaining center region.
func _panel_w() -> int:
	return _bpl().left

func _journal_w() -> int:
	# observer layout (spec §7): the journal widens to carry 100+ lines
	if _observer:
		return _OBSERVER_JOURNAL_W
	return _bpl().right

## Breakpoints come from LayoutProfile (stage 2), not inline numbers, so the
## thresholds live in one place and a skin/profile can move them.
func _bpl() -> Dictionary:
	var lp = Layout.for_screen(Vector2i(int(size.x), int(size.y)))
	return {"left": lp.left_width(), "right": lp.right_width(), "profile": lp.id}

func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_rect()

	# top bar (anchored top-wide)
	_top = TopBar.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.anchor_right = 1.0
	_top.offset_bottom = _TOP_H
	add_child(_top)

	# CENTER ROW: players | board | journal — a single HBox so the three panels
	# are tied together and the board always fills the space between them.
	_center = HBoxContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.anchor_top = 0.0
	_center.offset_top = _TOP_H
	_center.offset_bottom = -_ACTION_H
	_center.add_theme_constant_override("separation", 8)
	add_child(_center)

	# left players panel — wrapped in a rail so it can collapse to a 46px strip
	# with a vertical title instead of becoming an empty band (spec §5.2)
	_players_rail = RailPanel.new()
	_players_rail.name = "PlayersRail"
	_players_rail.setup(_skin, "ui.players", true)
	_players_rail.set_expanded_width(_panel_w())
	_players_rail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_center.add_child(_players_rail)
	_players = PlayersPanel.new()
	_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players.set_rail(_players_rail)
	_players_rail.set_content(_players)

	# board (center) — expands to fill whatever the side panels leave
	_board_scene = BoardScene.new()
	_board_scene.name = "BoardScene"
	_board_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_scene.set_managed_by_container(true)
	_center.add_child(_board_scene)

	# right journal panel — also railed (spec §5.2)
	_jpanel_rail = RailPanel.new()
	_jpanel_rail.name = "JournalRail"
	_jpanel_rail.setup(_skin, "ui.journal", false)
	_jpanel_rail.set_expanded_width(_journal_w())
	_jpanel_rail.size_flags_horizontal = Control.SIZE_SHRINK_END
	_center.add_child(_jpanel_rail)
	_journal = JournalPanel.new()
	_journal.name = "JournalPanel"
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.exported.connect(_on_journal_exported)
	_journal.set_rail(_jpanel_rail)
	_jpanel_rail.set_content(_journal)

	# modal host (above everything)
	_modals = ModalHost.new()
	_modals.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modals.visible = false
	# IT SAID "above everything" AND WAS NOT. Children added later paint on top, and both the
	# action panel and the tile inspector are added AFTER this — so the dialog's own pixels were
	# covered wherever those panels reach. The node reported a correct rect and `visible=true`
	# while nothing of it appeared on screen. An explicit z_index does not depend on the order
	# somebody happened to write `add_child` in.
	_modals.z_index = 100
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
	if _players == null or _jpanel_rail == null or _board_scene == null:
		return
	# auto-collapse by the profile, unless the user set the state by hand
	# (spec §5.2: a manual collapse survives until the profile threshold moves)
	var lp = Layout.for_screen(Vector2i(int(size.x), int(size.y)))
	if _players_rail != null:
		if not _players_rail.is_manual():
			_players_rail.set_collapsed(lp.rail_left(), false)
		_players_rail.set_count(str(_player_count()))
	if _jpanel_rail != null:
		if not _jpanel_rail.is_manual():
			_jpanel_rail.set_collapsed(lp.rail_right() and not _observer, false)
		_jpanel_rail.set_count(str(_journal_count()))
	if not _players_rail.is_collapsed():
		_players_rail.set_expanded_width(_panel_w())
	if not _jpanel_rail.is_collapsed():
		_jpanel_rail.set_expanded_width(_journal_w())
	_fits_left = 3
	# the board scene fills the center region between the panels (HBox handles it)
	_board_scene.set_frame(Rect2(0, 0, 0, 0))   # signal it to re-fit its own rect
	# the stream feed must follow the column: collapsing a rail changes its width
	# without any window resize. The container has NOT sorted yet at this point,
	# so re-fit over the next few frames instead.
	_fit_event_overlay_pending = true


## Compact status shown in the players rail so it is never an empty strip.
func _player_count() -> int:
	var n := 0
	if seats != null:
		for s in seats:
			if not bool(s.get("bankrupt")) if s is Dictionary else true:
				n += 1
	return n


## Compact status for the journal rail: the number of logged events.
func _journal_count() -> int:
	if engine == null or engine.log == null:
		return 0
	return engine.log.size()

func _process(delta: float) -> void:
	if _fit_event_overlay_pending or _fits_left > 0:
		if _fits_left > 0:
			_fits_left -= 1
		_fit_event_overlay_pending = false
		_fit_event_overlay()
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
		_modals.show_message(I18n.t("gv.journal_export_fail_title"), I18n.t("gv.journal_export_fail_body"))
	else:
		_modals.show_message(I18n.t("gv.journal_export_ok_title"), I18n.t("gv.journal_export_ok_body", [path]))

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

## P3: Handle events from seat manager for toast/banner display. P5: wording
## is centralized + localized in ToastStack.show_event_toast (same I18n dict
## as the journal via EventMessages), so journal / overlay / toasts agree.
func _on_events_emitted(events: Array) -> void:
	for ev in events:
		_toast_stack.show_event_toast(ev)
	# THE JOURNAL IS FED BY EVENTS, NOT BY STATE CHANGES.
	#
	# It was refreshed only from `_on_state_changed`, which fires when the state settles —
	# so the log held exactly one entry (`setup`) while a whole match played out. A toast
	# appeared and vanished; the written record of what happened never grew.
	if not events.is_empty():
		_refresh_journal()

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
				# pass legal_actions so the modal's buttons follow the engine
				_modals.open_build(_inspector.selected, sp, _name_of_pid(_human_pid),
					engine.legal_actions(_human_pid))
			else:
				_modals.show_message(I18n.t("gv.select_tile"), I18n.t("gv.select_tile_body"))
		"propose_trade":
			var sp2 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade(sp2, seats, _human_pid)
		"respond_trade":
			var sp3 := ProjectionScript.new().for_spectator(engine)
			_modals.open_trade_response(sp3, seats, engine.legal_actions(_human_pid))
		"bid":
			var sp4 := ProjectionScript.new().for_spectator(engine)
			_modals.open_auction(sp4, seats, engine.legal_actions(_human_pid))

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

## A seat's display name (for the modal headers).
func _name_of_pid(pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	return ""


func _submit(pid: int, action: String, params: Dictionary) -> void:
	if manager == null:
		return
	var res: Dictionary = manager.push_intent(pid, action, params)
	if not res.get("ok", false):
		_modals.show_message(I18n.t("gv.rejected_title"), I18n.t("gv.rejected_body", [str(res.get("reason", "?"))]))


## The header asked for a different skin. Wearing it means rebuilding every widget — styles are
## built in `_init`/`setup` from the active skin, so nothing already on screen would change.
func _on_skin_requested(skin_id: String) -> void:
	skin_requested.emit(skin_id)
