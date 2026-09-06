extends Node
## Entry point / single launcher. Shows the Lobby first; on START builds the
## engine + seat manager + full game view (board, HUD, action panel, journal).
## F12 toggles the host-local admin panel (engine-authoritative, token-guarded).

const EngineScript := preload("res://core/engine.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const AdminController := preload("res://admin/admin_controller.gd")
const AdminGate := preload("res://admin/admin_gate.gd")
const AdminPanel := preload("res://admin/admin_panel.gd")
const Lobby := preload("res://ui/lobby.gd")
const GameView := preload("res://ui/game_view.gd")

var _engine
var _manager
var _controller
var _gate
var _panel
var _game_view
var _lobby

func _ready() -> void:
	# set window size for the playable shell
	var vp = get_viewport()
	if vp != null:
		# 1280x720 readable playable layout
		DisplayServer.window_set_size(Vector2i(1280, 720))
	_lobby = Lobby.new()
	add_child(_lobby)
	_lobby.started.connect(_on_started)

func _on_started(settings, seats: Array) -> void:
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
	_panel = AdminPanel.new()
	_panel.name = "AdminPanel"
	add_child(_panel)
	_panel.setup(_gate)
	_panel.visible = false

	# swap lobby for the game view
	_lobby.visible = false
	_game_view = GameView.new()
	add_child(_game_view)
	_game_view.setup(_engine, _manager, seats, settings)
	print("Neuro Property Trade — ready. F12 toggles admin panel. Human seat: " + str(_human_names(seats)))

func _human_names(seats: Array) -> String:
	var out: Array = []
	for s in seats:
		if str(s.input_driver) in ["LOCAL", "ADMIN"]:
			out.append(str(s.name))
	return ", ".join(out)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			if _panel != null:
				_panel.visible = not _panel.visible
				# keep the admin panel above any modal overlays
				if _panel.visible:
					_panel.move_to_front()
