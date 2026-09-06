class_name BoardScene
extends Control
## The assembled visual layer: board + tokens + spectacle camera + overlay + sfx.
## Reads the engine (spectator-safe projection) and event log. Read-only
## downstream consumer — never mutates engine state.

const Projection := preload("res://sdk/projection.gd")
const MarkdownRenderer := preload("res://sdk/markdown_renderer.gd")
const TL := preload("res://visual/tile_layout.gd")
const BoardView := preload("res://visual/board_view.gd")
const Spectacle := preload("res://visual/spectacle.gd")
const EventOverlay := preload("res://visual/event_overlay.gd")
const Sfx := preload("res://visual/sfx.gd")

const CELL := 64
const BOARD_TILES := 40

var _engine
var _settings
var _board: BoardView
var _viewport: SubViewportContainer
var _viewport_node: SubViewport
var _spectacle: Spectacle
var _overlay: EventOverlay
var _sfx: Sfx
var _timer := 0.0

func setup(engine, settings) -> void:
	_engine = engine
	_settings = settings
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# background
	var bg = ColorRect.new()
	bg.color = Color("101820")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# "camera" viewport: SubViewportContainer (clips) >= SubViewport >= board,
	# panned by the spectacle controller.
	_viewport_node = SubViewport.new()
	_viewport_node.name = "CamViewport"
	_viewport_node.size = Vector2(1024, 768)
	_viewport_node.disable_3d = true

	_viewport = SubViewportContainer.new()
	_viewport.name = "CamContainer"
	_viewport.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.stretch = true
	_viewport.stretch_shrink = 1
	_viewport.add_child(_viewport_node)
	add_child(_viewport)

	# board inside the viewport
	_board = BoardView.new()
	_board.name = "BoardView"
	_board.build(BOARD_TILES, CELL)
	_viewport_node.add_child(_board)
	_board.position = Vector2.ZERO

	# spectacle pans the viewport container to focus on the action
	_spectacle = Spectacle.new()
	_spectacle.setup(_viewport, _board, CELL, BOARD_TILES)
	_spectacle.set_animations(_settings.animations)
	add_child(_spectacle)

	# overlay + sfx are outside the camera so they stay fixed on screen
	_overlay = EventOverlay.new()
	_overlay.name = "EventOverlay"
	_overlay.visible = _settings.event_overlay
	add_child(_overlay)

	_sfx = Sfx.new()
	_sfx.set_enabled(true)
	add_child(_sfx)

	# subscribe to the engine event log (signal up: engine -> us)
	_engine.log.event_appended.connect(_on_engine_event)

	# initial paint
	_paint(_settings.animations)

func _on_engine_event(entry: Dictionary) -> void:
	_sfx.play_type(entry.get("type", ""))
	_overlay.append(entry)
	_spectacle.on_event(entry)
	_paint(true)

func _paint(animate: bool) -> void:
	if _engine == null: return
	var proj := Projection.new().for_spectator(_engine)
	_board.refresh_state(proj)
	_board.refresh_tokens(proj.get("players", []))
	if not animate:
		_board.update_highlight(proj)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		if _engine != null:
			_paint(false)   # safety slow refresh (catches non-event changes)
