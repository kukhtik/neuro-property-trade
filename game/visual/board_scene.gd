class_name BoardScene
extends Control
## The assembled visual layer: board + tokens + spectacle camera + overlay + sfx.
## Reads the engine (spectator-safe projection) and event log. Read-only
## downstream consumer — never mutates engine state.
##
## The "camera" is a clip_contents Control that pans the board inside the root
## viewport (so it is physically rendered/capturable — no SubViewport, which
## would be a separate render target and show black in a root-viewport grab).
##
## A1: the board SCALES to fit the available frame. The cell size is recomputed
## from the frame each layout pass; when it changes the board is rebuilt at the
## new cell size (so it never clips — it always fits the center region).

const ProjectionScript := preload("res://sdk/projection.gd")
const MarkdownRenderer := preload("res://sdk/markdown_renderer.gd")
const TL := preload("res://visual/tile_layout.gd")
const BoardView := preload("res://visual/board_view.gd")
const Spectacle := preload("res://visual/spectacle.gd")
const EventOverlay := preload("res://visual/event_overlay.gd")
const Sfx := preload("res://visual/sfx.gd")
const DiceStage := preload("res://ui/dice_stage.gd")

const MIN_CELL := 24
const MAX_CELL := 72
const BOARD_TILES := 40   # default; overridden by settings.tile_count in setup()

var _engine
var _settings
var _seats: Array = []
var _board: BoardView
var _camera: Control          # clip_contents frustum holding the board
var _spectacle: Spectacle
var _overlay: EventOverlay
var _sfx: Sfx
var _dice_stage: DiceStage
var _timer := 0.0
var _cell := 0
var _tile_count := BOARD_TILES
var _frame_override: Rect2 = Rect2(-1, -1, -1, -1)   # when set, fill this rect instead of the viewport
var _managed_by_container := false   # when true, a parent container sets our size

## Optional: constrain this scene to a sub-rect (e.g. the center board region
## of a larger HUD). Leave unset to fill the whole viewport (plain Node parent).
func set_frame(r: Rect2) -> void:
	_frame_override = r
	_apply_viewport_rect()

## When the scene is a child of a container (HBox/VBox), the container manages
## our size — call this so we don't fight it with the viewport rect.
func set_managed_by_container(v: bool) -> void:
	_managed_by_container = v

func setup(engine, settings, seats: Array = []) -> void:
	_engine = engine
	_settings = settings
	_seats = seats
	# parametric board: read the tile count from settings (default 40)
	if settings != null and "tile_count" in settings:
		_tile_count = int(settings.tile_count)
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

	# spectacle pans the camera (frustum) to follow the action. P6 CS-7: it is
	# gated by settings.spectacle (off by default — the board is always whole).
	_spectacle = Spectacle.new()
	_spectacle.set_animations(_settings.animations if _settings != null else true)
	_spectacle.set_enabled(_settings.spectacle if _settings != null else false)
	add_child(_spectacle)

	# overlay + sfx + dice are siblings of the camera so they stay fixed on screen
	_overlay = EventOverlay.new()
	_overlay.name = "EventOverlay"
	_overlay.visible = _settings.event_overlay if _settings != null else true
	add_child(_overlay)

	_sfx = Sfx.new()
	_sfx.set_enabled(true)
	add_child(_sfx)

	# P3: dice stage (center-screen BG3 dice)
	_dice_stage = DiceStage.new()
	_dice_stage.name = "DiceStage"
	_dice_stage.set_animations(_settings.animations if _settings != null else true)
	_dice_stage.set_sfx(_sfx)
	_dice_stage.dice_rolled.connect(_on_dice_rolled)
	add_child(_dice_stage)

	# P3: board center SVG background (shown behind the board when empty)
	_add_board_center()

	if _engine != null:
		_engine.log.event_appended.connect(_on_engine_event)

	# build the board now (default cell) so it's never null; _resize_children
	# will rebuild at the correct size once the container lays us out
	_cell = MAX_CELL
	_rebuild_board()

	# size children now that we know our rect
	_resize_children()

	_paint(false)

## Set this control's rect to the root viewport's visible rect (works even
## when parented under a plain Node, where anchors have no parent to size from).
func _apply_viewport_rect() -> void:
	if _managed_by_container:
		return   # the parent container sets our size; don't fight it
	var r := _frame_override
	if r.size.x < 0 or r.size.y < 0:
		r = Rect2()
		if get_viewport() != null:
			r = get_viewport().get_visible_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			r = Rect2(0, 0, 1152, 648)
	position = r.position
	size = r.size

## Recompute the cell size to fit the frame, rebuild the board if it changed,
## and position the camera + board. This is what makes the board ADAPT to the
## window instead of clipping (A1).
func _resize_children() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	var grid := TL.grid_cells(_tile_count)
	var bx := 8.0
	var by := 8.0
	var frustum_w := w - bx - 8.0
	var frustum_h := h - by - 8.0
	# cell size that fits the frustum (integer so tiles stay crisp)
	var cell := int(minf(frustum_w / grid, frustum_h / grid))
	cell = clampi(cell, MIN_CELL, MAX_CELL)
	if cell != _cell:
		_cell = cell
		_rebuild_board()
		if _engine != null:
			_paint(false)   # fill the fresh board right away
	# camera frustum: leave room for the overlay (bottom-right) when event_overlay
	_camera.position = Vector2(bx, by)
	_camera.size = Vector2(frustum_w, frustum_h)
	# center the board inside the frustum, clamped so tiles stay in view
	var board_px := grid * _cell
	var cx := maxf(0.0, (frustum_w - board_px) * 0.5)
	var cy := maxf(0.0, (frustum_h - board_px) * 0.5)
	_board.position = Vector2(cx, cy)
	_place_board_center()
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

## (Re)build the board at the current `_cell`. Frees the old board and creates
## a fresh one, reconnecting the tile-click signal.
func _rebuild_board() -> void:
	if _board != null and is_instance_valid(_board):
		_board.queue_free()
	_board = BoardView.new()
	_board.name = "BoardView"
	_board.build(_tile_count, _cell)
	_board.set_seats(_seats)
	_camera.add_child(_board)
	_board.tile_clicked.connect(_on_tile_clicked)
	_board.tile_hovered.connect(func(i: int) -> void: tile_hovered.emit(i))
	_spectacle.setup(_camera, _board, _cell, _tile_count)

func _on_tile_clicked(idx: int) -> void:
	tile_clicked.emit(idx)

signal tile_clicked(index: int)
signal tile_hovered(index: int)   # P4 §7: observer inspector on hover

func _process(delta: float) -> void:
	# keep our rect synced to the viewport (root is a plain Node)
	_apply_viewport_rect()
	_resize_children()
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		if _engine != null:
			_paint(false)   # safety slow refresh (catches non-event changes)

func _on_engine_event(entry: Dictionary) -> void:
	_sfx.play_type(entry.get("type", ""))
	_overlay.append(entry)
	_spectacle.on_event(entry)
	
	# P3: Trigger dice animation on roll events
	if entry.get("type", "") == "roll":
		var d: Dictionary = entry.get("data", {})
		var d1: int = int(d.get("d1", 1))
		var d2: int = int(d.get("d2", 1))
		if _dice_stage != null:
			_dice_stage.roll(d1, d2)
	
	_paint(true)

func _paint(animate: bool) -> void:
	if _engine == null: return
	var proj := ProjectionScript.new().for_spectator(_engine)
	_board.refresh_state(proj)
	_board.refresh_tokens(proj.get("players", []))
	if not animate:
		_board.update_highlight(proj)

## P3: Add board center SVG background (behind the board tiles — decorative
## fill of the 6×6 interior so the middle doesn't look empty)
func _add_board_center() -> void:
	var center := TextureRect.new()
	center.name = "BoardCenter"
	center.texture = load("res://assets/board_center.svg")
	center.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	center.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera.add_child(center)
	_place_board_center()

## Position/size the center art inside the board's inner area (between the
## tile ring). Called after every layout pass.
func _place_board_center() -> void:
	if not is_instance_valid(_camera):
		return
	var center = _camera.get_node_or_null("BoardCenter")
	if center == null or _board == null:
		return
	var grid := TL.grid_cells(_tile_count)
	var inner := float(grid - 2) * float(_cell)   # interior ring area
	var art := inner * 0.92   # small margin from the ring
	center.size = Vector2(art, art)
	center.position = (Vector2(float(board_px()), float(board_px())) - Vector2(art, art)) * 0.5

func board_px() -> int:
	return TL.grid_cells(_tile_count) * _cell

## P3: dice stage finished presenting — nothing to do engine-side (the engine
## already advanced); kept as the presentation-completion hook.
func _on_dice_rolled(d1: int, d2: int, sum: int) -> void:
	pass  # presentation-completion hook
