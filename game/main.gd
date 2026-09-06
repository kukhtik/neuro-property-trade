extends Node
## Phase 4 entry point. Hosts the seat manager, a default game, and a hidden
## (F12) admin panel wired to admin_controller. All admin edits route through
## engine.admin_override (fail-closed, same event log).

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const SeatManager := preload("res://seats/seat_manager.gd")
const AdminController := preload("res://admin/admin_controller.gd")
const AdminPanel := preload("res://admin/admin_panel.gd")
const BoardScene := preload("res://visual/board_scene.gd")

var _engine
var _manager
var _controller
var _panel
var _board_scene

func _ready() -> void:
	var s = Settings.new()
	var seats: Array = SeatConfig.from_settings(s)
	_engine = EngineScript.new()
	_engine.setup(s, _names(seats))
	_manager = SeatManager.new()
	_manager.name = "SeatManager"
	add_child(_manager)
	_manager.setup(_engine, seats)
	_controller = AdminController.new()
	_controller.setup(_engine, seats)
	_panel = AdminPanel.new()
	_panel.name = "AdminPanel"
	add_child(_panel)
	_panel.setup(_controller)
	_panel.visible = false
	_board_scene = BoardScene.new()
	_board_scene.name = "BoardScene"
	add_child(_board_scene)
	_board_scene.setup(_engine, s)
	print("Neuro Property Trade — ready. F12 toggles admin panel.")

func _names(seats: Array) -> Array:
	var out := []
	for s in seats:
		out.append(s.name)
	return out

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			if _panel != null:
				_panel.visible = not _panel.visible
