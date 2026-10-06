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
const SkinManager := preload("res://visual/skin_manager.gd")
const TL := preload("res://visual/tile_layout.gd")
const BL := preload("res://visual/board_layout.gd")
const BoardView := preload("res://visual/board_view.gd")
const Spectacle := preload("res://visual/spectacle.gd")
const EventOverlay := preload("res://visual/event_overlay.gd")
const Sfx := preload("res://visual/sfx.gd")
const DiceStage := preload("res://ui/dice_stage.gd")
const BoardCenterScript := preload("res://visual/board_center.gd")
const EffectLayerScript := preload("res://visual/effect_layer.gd")
const EventAdapterScript := preload("res://ui/core/event_adapter.gd")
const EventPresenterScript := preload("res://ui/core/event_presenter.gd")
const UiStoreScript := preload("res://ui/core/ui_store.gd")

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
var _effects                 # EffectLayer: tokens/particles above the ring
var _center                  # BoardCenterV2: the interactive centre
var _skin                    # SkinManager, shared by the centre and the effects
var _presenter               # EventPresenter: the presentation queue (stage 5)
var _adapter                 # EventAdapter: engine event -> UI schema
var _store                   # UiStore: the view model the presenter feeds
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
	bg.color = _skin.color("board.bg2", Color("101820"))
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

	# P3: board center — now the interactive centre built from skin tokens
	_skin = SkinManager.new()
	_skin.load_skin()
	_add_board_center()

	# effects overlay ABOVE the ring (tokens, floats, particles) — spec 5.6
	_effects = EffectLayerScript.new()
	_effects.name = "EffectLayer"
	_effects.setup(_skin, _settings.animations if _settings != null else true)
	_camera.add_child(_effects)

	# the presentation queue (stage 5): events are shown in order, not all at once
	_adapter = EventAdapterScript.new()
	_store = UiStoreScript.new()
	_presenter = EventPresenterScript.new()
	_presenter.animations = _settings.animations if _settings != null else true
	_presenter.name = "EventPresenter"
	add_child(_presenter)
	_presenter.set_sink({
		"play": Callable(self, "_play_event"),
		"apply": Callable(self, "_play_event"),
		"on_drained": Callable(self, "_resync_store"),
	})
	_presenter.set_resync(Callable(self, "_resync_store"))

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
	# the camera is created after the first viewport-rect pass; without it there
	# is nothing to size (`_process` calls this every frame from the start)
	if _camera == null or not is_instance_valid(_camera):
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
	# _resize_children() can run before the camera exists (the viewport rect is
	# applied on the first _process), so guard instead of touching a null node.
	if _camera == null or not is_instance_valid(_camera):
		return
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
	# the effects overlay sits ABOVE the ring; it takes the board's own geometry
	# so tokens ride the real tile rects for any tile count (spec 5.6)
	_sync_effect_layer()


## Feed the effect layer the board's geometry and current tokens.
func _sync_effect_layer() -> void:
	if _effects == null or _board == null:
		return
	_effects.set_layout(_board._layout, float(_cell))
	_effects.position = _board.position
	_effects.size = _board.size


## The interactive centre (spec 5.7) built from skin tokens, replacing the old
## decorative SVG. It sheds the mini-log, card and subtitle as the centre shrinks.
func _add_board_center() -> void:
	_center = BoardCenterScript.new()
	_center.name = "BoardCenterV2"
	_center.setup(_skin)
	_camera.add_child(_center)
	_place_board_center()

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
	# immediate, non-animated reactions stay direct: sound, the spectator feed
	# and the camera should not wait behind the presentation queue.
	_sfx.play_type(entry.get("type", ""))
	_overlay.append(entry)
	_spectacle.on_event(entry)

	# the VISUAL playback goes through the queue (spec 8.1), so several events
	# from one engine call are shown in order instead of all at once.
	if _presenter == null:
		_paint(true)
		return
	var ev = _adapter.adapt(entry)
	if not ev.is_empty() or entry.get("type", "") == "roll":
		# `roll` is a board effect with no journal line, but it still needs the
		# dice animation, so it reaches the presenter too
		if not ev.is_empty():
			_presenter.push(ev)
		else:
			_play_local(entry, false)


## Play one event's own animation (dice, walk, effects). Called by the presenter
## when it is wired, or directly when it is not.
func _play_event(ev: Dictionary, instant: bool) -> void:
	# apply the deltas so the view model keeps up with the animation
	if _store != null:
		_store.apply_delta(ev.get("d", []))
	var k: String = str(ev.get("k", ""))
	if k == "roll" and not instant:
		if _dice_stage != null:
			_dice_stage.roll(int(ev.get("a", 1)), int(ev.get("b", 1)))
	elif k == "move" and not instant:
		if _effects != null:
			_effects.move_player(int(ev.get("p", -1)), [int(ev.get("ti", 0))])
	elif k == "buy" and not instant:
		if _effects != null:
			_effects.burst(int(ev.get("ti", -1)), _skin.color("accent"))
	elif k in ["rent", "tax", "go", "park"] and not instant:
		if _effects != null:
			var positive: bool = k in ["go", "park"]
			_effects.float_over_tile(int(ev.get("ti", -1)),
				str(ev.get("a", 0)), positive)
	# the board is repainted from the store/projection after each step
	if instant:
		_paint(false)
	else:
		_paint(true)


## Fall back to the legacy one-shot path for events the adapter drops.
func _play_local(entry: Dictionary, instant: bool) -> void:
	if entry.get("type", "") == "roll":
		var d: Dictionary = entry.get("data", {})
		if _dice_stage != null and not instant:
			_dice_stage.roll(int(d.get("d1", 1)), int(d.get("d2", 1)))
	_paint(not instant)
	# the projection is the truth: resync the view model once we are done
	_resync_store()


## The presenter finished its queue — reconcile the view with the projection.
func _resync_store() -> void:
	if _store == null or _engine == null:
		_paint(false)
		return
	_store.resync(ProjectionScript.new().for_spectator(_engine))
	_paint(false)

## Skip the animation queue and jump to the truth (spec 8.1: Space / click).
func skip_all_animations() -> void:
	if _presenter != null:
		_presenter.skip_all()

## Set the animations master toggle (settings.animations).
func set_animations(on: bool) -> void:
	if _presenter != null:
		_presenter.animations = on
	if _effects != null:
		_effects.animations = on
	if _dice_stage != null:
		_dice_stage.set_animations(on)

func _paint(animate: bool) -> void:
	if _engine == null: return
	var proj := ProjectionScript.new().for_spectator(_engine)
	_board.refresh_state(proj)
	_board.refresh_tokens(proj.get("players", []))
	if not animate:
		_board.update_highlight(proj)
	# the effects overlay owns the tokens now, and the centre mirrors the turn
	if _effects != null:
		_effects.sync_tokens(_token_vms(proj))
	if _center != null:
		var players: Array = proj.get("players", [])
		var tp: int = int(proj.get("turn_player", -1))
		var pname := ""
		if tp >= 0 and tp < players.size():
			pname = str(players[tp].get("name", ""))
		var board: Array = proj.get("board", [])
		var tile_name := ""
		if tp >= 0 and tp < players.size():
			var pos: int = int(players[tp].get("position", -1))
			if pos >= 0 and pos < board.size():
				tile_name = str(board[pos].get("name", ""))
		_center.set_turn(pname, str(proj.get("phase", "")), tile_name)
		if int(proj.get("dice", [0, 0])[0]) > 0:
			var d: Array = proj.get("dice", [0, 0])
			_center.set_dice(int(d[0]), int(d[1]))


## Player view models for the effect layer's tokens (id/name/pos/colour).
func _token_vms(proj: Dictionary) -> Array:
	var out: Array = []
	var players: Array = proj.get("players", [])
	for p in players:
		out.append({
			"id": int(p.get("index", -1)),
			"name": str(p.get("name", "")),
			"pos": int(p.get("position", 0)),
			"color_idx": int(p.get("index", 0)),
			"bankrupt": bool(p.get("bankrupt", false)),
		})
	return out

## Position/size the interactive centre inside the board's inner area (between
## the tile ring). Called after every layout pass. Uses BoardLayout's real
## centre rect so it works for any tile count, not just 40.
func _place_board_center() -> void:
	if _center == null or _board == null or not is_instance_valid(_camera):
		return
	var side: float = float(board_px())
	var inner: Rect2 = BL.center_rect(_tile_count, side,
		_skin.metric("corner_ratio", 1.4), _skin.metric("board_gap", 2.0))
	_center.position = _board.position + inner.position
	_center.size = inner.size
	_center.fit(Rect2(Vector2.ZERO, inner.size))

func board_px() -> int:
	return TL.grid_cells(_tile_count) * _cell

## P3: dice stage finished presenting — nothing to do engine-side (the engine
## already advanced); kept as the presentation-completion hook.
func _on_dice_rolled(d1: int, d2: int, sum: int) -> void:
	pass  # presentation-completion hook
