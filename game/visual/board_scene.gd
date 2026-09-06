class_name BoardScene
extends Control
## The assembled visual layer: board + tokens + spectacle camera + overlay + sfx.
## Reads the engine (spectator-safe projection) and event log. Read-only
## downstream consumer — never mutates engine state.
##
## The "camera" is a clip_contents Control that pans the board inside the root
## viewport (so it is physically rendered/capturable — no SubViewport, which
## would be a separate render target and show black in a root-viewport grab).

const ProjectionScript := preload("res://sdk/projection.gd")
const MarkdownRenderer := preload("res://sdk/markdown_renderer.gd")
const TL := preload("res://visual/tile_layout.gd")
const BoardView := preload("res://visual/board_view.gd")
const Spectacle := preload("res://visual/spectacle.gd")
const EventOverlay := preload("res://visual/event_overlay.gd")
const Sfx := preload("res://visual/sfx.gd")

const CELL := 48
const BOARD_TILES := 40

var _engine
var _settings
var _board: BoardView
var _camera: Control          # clip_contents frustum holding the board
var _spectacle: Spectacle
var _overlay: EventOverlay
var _sfx: Sfx
var _timer := 0.0
var _frame_override: Rect2 = Rect2(-1, -1, -1, -1)   # when set, fill this rect instead of the viewport

## Optional: constrain this scene to a sub-rect (e.g. the center board region
## of a larger HUD). Leave unset to fill the whole viewport (plain Node parent).
func set_frame(r: Rect2) -> void:
	_frame_override = r
	_apply_viewport_rect()

func setup(engine, settings) -> void:
	_engine = engine
	_settings = settings
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_viewport_rect()

	# background fills the whole scene
	var bg = ColorRect.new()
	bg.color = Color("101820")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# camera frustum: clips to our rect, pans the board child
	_camera = Control.new()
	_camera.name = "Camera"
	_camera.clip_contents = true
	_camera.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_camera)

	# board fills the whole board plane, centered; panned by the camera
	_board = BoardView.new()
	_board.name = "BoardView"
	_board.build(BOARD_TILES, CELL)
	_camera.add_child(_board)

	# spectacle pans the camera (frustum) to follow the action
	_spectacle = Spectacle.new()
	_spectacle.setup(_camera, _board, CELL, BOARD_TILES)
	_spectacle.set_animations(_settings.animations)
	add_child(_spectacle)

	# overlay + sfx are siblings of the camera so they stay fixed on screen
	_overlay = EventOverlay.new()
	_overlay.name = "EventOverlay"
	_overlay.visible = _settings.event_overlay
	add_child(_overlay)

	_sfx = Sfx.new()
	_sfx.set_enabled(true)
	add_child(_sfx)

	_engine.log.event_appended.connect(_on_engine_event)

	# size children now that we know our rect
	_resize_children()

	_paint(false)

## Set this control's rect to the root viewport's visible rect (works even
## when parented under a plain Node, where anchors have no parent to size from).
func _apply_viewport_rect() -> void:
	var r := _frame_override
	if r.size.x < 0 or r.size.y < 0:
		r = Rect2()
		if get_viewport() != null:
			r = get_viewport().get_visible_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			r = Rect2(0, 0, 1152, 648)
	position = r.position
	size = r.size

func _resize_children() -> void:
	var w := size.x
	var h := size.y
	var grid := TL.grid_cells(BOARD_TILES)
	var board_px := grid * CELL
	var bx := 48.0
	var by := 48.0
	# camera frustum: leave room for the overlay (bottom-right) when event_overlay
	_camera.position = Vector2(bx, by)
	_camera.size = Vector2(w - bx - 24.0, h - by - 24.0)
	# center the board inside the frustum, clamped so tiles stay in view
	var cx := maxf(0.0, (_camera.size.x - board_px) * 0.5)
	var cy := maxf(0.0, (_camera.size.y - board_px) * 0.5)
	_board.position = Vector2(cx, cy)
	# background covers our rect
	for child in get_children():
		if child is ColorRect and child != _board:   # our bg
			var b := child as ColorRect
			b.position = Vector2.ZERO
			b.size = Vector2(w, h)
			b.set_anchors_preset(Control.PRESET_FULL_RECT)
			b.anchor_left = 0; b.anchor_top = 0
			b.anchor_right = 1; b.anchor_bottom = 1
			b.offset_left = 0; b.offset_top = 0
			b.offset_right = 0; b.offset_bottom = 0

func _process(delta: float) -> void:
	# keep our rect synced to the viewport (root is a plain Node)
	_apply_viewport_rect()
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		if _engine != null:
			_paint(false)   # safety slow refresh (catches non-event changes)

func _on_engine_event(entry: Dictionary) -> void:
	_sfx.play_type(entry.get("type", ""))
	_overlay.append(entry)
	_spectacle.on_event(entry)
	_paint(true)

func _paint(animate: bool) -> void:
	if _engine == null: return
	var proj := ProjectionScript.new().for_spectator(_engine)
	_board.refresh_state(proj)
	_board.refresh_tokens(proj.get("players", []))
	if not animate:
		_board.update_highlight(proj)
