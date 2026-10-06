extends Node
## Entry point / single launcher (v2 one-screen). Builds GameView immediately
## (the board is always the root visual layer). The engine is created lazily on
## START. The SettingsOverlay (ex-lobby) opens on first run and via ⚙/F1.
## F12 toggles the host-local admin panel (engine-authoritative, token-guarded);
## on WebGL / --spectator the panel is NOT created at all (is_host gate).

const EngineScript := preload("res://core/engine.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const AdminController := preload("res://admin/admin_controller.gd")
const AdminGate := preload("res://admin/admin_gate.gd")
const AdminPanel := preload("res://admin/admin_panel.gd")
const SettingsOverlay := preload("res://ui/settings_overlay.gd")
const GameView := preload("res://ui/game_view.gd")

var _engine
var _manager
var _controller
var _gate
var _panel
var _game_view
var _overlay
var _is_host := true
var _profile
## Test/embedding hook: force the role instead of inferring it from argv. Must be
## set BEFORE the node enters the tree (i.e. before _ready).
var _force_profile = null
var _game_started := false

func _ready() -> void:
	# set window size for the playable shell (1440x900 gives the board room to
	# render larger, more readable tiles; the layout adapts to any size)
	var vp = get_viewport()
	if vp != null:
		DisplayServer.window_set_size(Vector2i(1440, 900))

	# The execution role is chosen at LAUNCH, never toggled in the UI
	# (docs/ui_migration_notes §9). UiProfile is the single source of that.
	#   --admin   : the host application (admin tools available; default on desktop)
	#   --stream  : the OBS window (spectator data, no input, large type)
	#   web       : the player WebUI
	_profile = _force_profile if _force_profile != null 		else UiProfileScript.infer(OS.has_feature("web"), OS.get_cmdline_user_args())
	_is_host = _profile.shows_admin_tools

	# one screen: build the game view immediately (cold board, no engine yet)
	_game_view = GameView.new()
	add_child(_game_view)
	_game_view.set_profile(_profile)
	_game_view.setup_cold(self)
	_game_view.restart_requested.connect(_on_restart_requested)
	_game_view.settings_requested.connect(_open_overlay)

	# settings overlay (ex-lobby) opens on first run, pre-game mode. It lives
	# on its own top CanvasLayer (layer 50) so it is cleanly separated from the
	# GameView tree — no white-frame/collapse artifacts from being a sibling of
	# the board (P6 Phase 3).
	var _overlay_layer := CanvasLayer.new()
	_overlay_layer.name = "OverlayLayer"
	_overlay_layer.layer = 50
	add_child(_overlay_layer)
	_overlay = SettingsOverlay.new()
	_overlay_layer.add_child(_overlay)
	_overlay.set_mode(true)
	_overlay.started.connect(_on_started)
	_overlay.apply_requested.connect(_on_apply)
	_overlay.closed.connect(_on_overlay_closed)

	# host-only admin panel (created only when is_host)
	if _is_host:
		_panel = AdminPanel.new()
		_panel.name = "AdminPanel"
		add_child(_panel)
		_panel.visible = false
		_panel.game_rebuilt.connect(_on_admin_rebuilt)

	print("Neuro Property Trade — ready. is_host=%s" % str(_is_host))

func _has_cli_flag(flag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false

## Pre-game START: build engine + seats + manager, then start the game.
func _on_started(settings, seats: Array) -> void:
	_build_game(settings, seats)
	_overlay.visible = false
	_game_started = true
	_game_view.on_game_started()

## In-game restart (ПРИМЕНИТЬ): rebuild the engine with a new seed.
func _on_apply(settings, seats: Array) -> void:
	_build_game(settings, seats)
	_overlay.visible = false
	_game_started = true
	_game_view.on_game_started()

func _build_game(settings, seats: Array) -> void:
	# tear down any previous engine/manager
	if _manager != null and is_instance_valid(_manager):
		_manager.queue_free()
	# the engine is a RefCounted (not a Node) — dropping the reference lets GC
	# reclaim it; do NOT call .free() on it.
	_engine = null

	_engine = EngineScript.new()
	var names: Array = []
	for s in seats:
		names.append(str(s.name))
	_engine.setup(settings, names)

	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, seats)

	# admin (host-local, token-guarded) wired after seats exist
	_controller = AdminController.new()
	_controller.setup(_engine, seats)
	_gate = AdminGate.new()
	_gate.setup(_controller, settings.admin_token)
	if _panel != null:
		_panel.setup(_gate)
		_panel.visible = false

	_game_view.setup(_engine, _manager, seats, settings)
	# game-over banner: seat_manager emits game_over when the engine reaches END_GAME
	if _manager.game_over.is_connected(_on_game_over):
		_manager.game_over.disconnect(_on_game_over)
	_manager.game_over.connect(_on_game_over)

func _on_game_over(winner_name: String) -> void:
	_game_view.show_game_over(winner_name)

## P4: admin snapshot load — the panel hot-swapped the engine in the
## controller; re-wire the seat manager + game view to the restored engine.
func _on_admin_rebuilt(eng) -> void:
	_engine = eng
	if _manager != null and is_instance_valid(_manager):
		_manager.queue_free()
	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, _controller.seats)
	_game_view.setup(_engine, _manager, _controller.seats, _engine.settings)
	if _manager.game_over.is_connected(_on_game_over):
		_manager.game_over.disconnect(_on_game_over)
	_manager.game_over.connect(_on_game_over)

func _on_overlay_closed() -> void:
	# ESC closes the overlay without starting: the board stays "cold" with a
	# single START button in the action panel.
	_overlay.visible = false
	_game_view.on_overlay_closed()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			if _panel != null:
				_panel.visible = not _panel.visible
				if _panel.visible:
					_panel.move_to_front()
		elif event.keycode == KEY_F1:
			_open_overlay()
		elif event.keycode == KEY_ESCAPE:
			if _overlay.visible:
				_on_overlay_closed()

func _open_overlay() -> void:
	_overlay.set_mode(not _game_started)
	_overlay.visible = true
	_overlay.move_to_front()

## Game-over "РЕВАНШ" or TopBar "↻": reopen the settings overlay in apply mode
## so the host can restart with a new seed.
func _on_restart_requested() -> void:
	_open_overlay()
