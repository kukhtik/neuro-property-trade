extends Control
## ZOOM-01 — the board camera: pan, zoom, and follow-the-turn (docs/program.md P1.4).
##
## WHY: the board is laid out with absolute positions on a square that fills the stage, so on a wide
## window the ring is small and the corners of the stage are dead space (the owner's report:
## "много пустого пространства используется нелогично"). A viewer also loses the token on a big
## board. A camera fixes both without touching the board's own layout.
##
## HOW GODOT WANTS IT: a Control cannot usefully scale ITSELF - its children keep hit-testing at the
## old rect and `position` fights the parent's layout. The pattern that works is a PARENT that
## carries `scale` and `position` with `clip_contents`, and a CHILD that keeps its own full-size
## layout inside it. That is exactly this node: the board is the child, laid out once at the
## container's size, and panning/zooming moves and scales the whole thing under it.
##
## WHAT THE PLAYER GETS (the order, in the owner's words):
##   * drag with the mouse to move the board;
##   * the wheel to zoom (around the cursor, so the thing under the pointer stays put);
##   * keyboard: arrows pan, +/- zoom, 0 resets, F follows the turn;
##   * AUTO-FOLLOW on a turn change and, when an auction opens, the camera holds still on the lot -
##     a viewer watching a bid must not be dragged away from it.
##
## It never reads the engine and never changes the board's own drawing: it is a window onto it.

signal zoom_changed(z: float)

const UiTheme := preload("res://ui/theme.gd")

## Zoom limits. 1.0 = the whole board exactly fits the stage (the board lays itself out at
## min(w, h)); below 1 there is nothing more to see, above ~3 the ring's own text starts to blur
## because it is drawn at its layout size.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12
## Keyboard pan, in px per step.
const PAN_STEP := 48.0
## Follow: how fast the camera eases to its target (px per second is not used - a tween is).
const FOLLOW_SEC := 0.35

## The board (set by the shell). Laid out at this container's size and then transformed.
var board: Control = null
var _zoom := 1.0
var _focus := Vector2.ZERO        # the point of the board under the stage centre, in board coords
## Follow state: -1 = the player is driving the camera, >=0 = following that pid.
var _follow := -1
## While an auction runs the camera holds still, whatever happens elsewhere.
var _hold := false
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_focus := Vector2.ZERO
var _tween: Tween = null


func setup(board_node: Control) -> void:
	board = board_node
	if board == null:
		return
	# THE CHILD LAYS OUT AT THE FULL STAGE SIZE and the camera transforms it, so the board keeps the
	# layout it already had (its `_layout()` reads its own `size`) and nothing inside it changes.
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.resized.connect(_on_board_resized)
	_apply()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_apply)


func _on_board_resized() -> void:
	# the board's own layout changed (a resize): keep the camera looking at the same place
	_apply()


## --- the camera transform ---------------------------------------------------------------------

## Put `board` under the camera. One place computes the transform, so pan, zoom, follow and reset
## cannot drift apart.
func _apply() -> void:
	if board == null:
		return
	var stage := size
	if stage.x <= 1.0 or stage.y <= 1.0:
		return
	# what the board looks like at zoom 1 (it is square, centred by its own layout)
	var board_side: float = minf(board.size.x, board.size.y)
	if board_side <= 1.0:
		return
	board.pivot_offset = Vector2.ZERO
	board.scale = Vector2(_zoom, _zoom)
	# The focus point (board coords) must land at the stage centre. The board's own top-left in
	# stage coords is (board.position), which does not move; only our scale does.
	var centre := stage * 0.5
	var want := centre - _focus * _zoom
	board.position = want


## The board point currently under the stage centre.
func focus_point() -> Vector2:
	return _focus


func zoom() -> float:
	return _zoom


func following() -> int:
	return _follow


func is_held() -> bool:
	return _hold


## --- zoom ------------------------------------------------------------------------------------

## Zoom about a stage-space point, so the board under the cursor stays under it.
func zoom_at(factor: float, at: Vector2) -> void:
	var before := _zoom
	var z := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(z, before):
		return
	# THE BOARD POINT UNDER `at` BEFORE THE ZOOM must stay under it after. Work out that point - the
	# same arithmetic `_apply` uses, so the two cannot disagree - then set the focus to it and let
	# `_apply` produce the transform. (The first version wrote `board.position` HERE instead, which
	# meant `_apply` was never called and the board's SCALE never followed the zoom: the camera's
	# number changed and the screen did not. The integration probe caught it; the unit probe could
	# not, because it only ever read the camera's own fields.)
	var board_pt := (at - board.position) / before
	_zoom = z
	_focus = board_pt + (size * 0.5 - at) / _zoom
	_apply()
	# a manual zoom takes the camera off follow: the viewer is looking where THEY put it
	_release_follow()
	zoom_changed.emit(_zoom)


## Reset to the whole board, centred. The camera's home position.
func reset_view() -> void:
	_zoom = ZOOM_MIN
	var side: float = minf(board.size.x, board.size.y) if board != null else 0.0
	_focus = Vector2(side, side) * 0.5
	_apply()
	_release_follow()
	zoom_changed.emit(_zoom)


## --- pan -------------------------------------------------------------------------------------

## Move the board by a stage-space delta (a drag). `_focus` moves the other way, because the board
## moving right means the camera is looking further left.
func pan_by(delta: Vector2) -> void:
	if board == null:
		return
	board.position += delta
	_focus = (size * 0.5 - board.position) / _zoom
	_release_follow()


## --- follow --------------------------------------------------------------------------------

## Follow a seat's token. Called by the shell on a turn change (the "auto-zoom on a move" the owner
## asked for), and by the F key.
func follow(pid: int) -> void:
	_follow = pid
	if _hold:
		return          # an auction is on: the camera has been told to stay
	_ease_to_target()


## Stop following (the player took the camera). Keeps the current view.
func _release_follow() -> void:
	_follow = -1


## HOLD the camera still - an auction is running. A viewer watching a bid must not be dragged to a
## token that happens to move while the bidding goes on.
func set_hold(on: bool) -> void:
	_hold = on
	if not on and _follow >= 0:
		_ease_to_target()


## Ask the shell where a token is, via a Callable that returns a board-space Vector2 (or null).
## The camera does not know about seats or projections - it is handed one function.
var token_pos_of: Callable = Callable()


func _ease_to_target() -> void:
	if not token_pos_of.is_valid():
		return
	var p = token_pos_of.call(_follow)
	if p == null:
		return
	var target: Vector2 = p
	# WHERE THE CAMERA MAY LOOK. The board is a square of `side` px inside a stage that may be wider
	# or taller. At zoom z the stage shows `size / z` board px, so the focus may run from half that
	# to (side - half that): any further and a strip of empty stage appears, which is the very
	# "dead space used illogically" this camera exists to remove. When the visible area is LARGER
	# than the board (a small zoom on a big stage) there is only one legal focus - the centre.
	var side: float = minf(board.size.x, board.size.y)
	var half: Vector2 = size * 0.5 / _zoom
	var lo := Vector2(
		clampf(half.x, 0.0, side * 0.5),
		clampf(half.y, 0.0, side * 0.5))
	var hi := Vector2(
		clampf(side - half.x, side * 0.5, side),
		clampf(side - half.y, side * 0.5, side))
	var want := Vector2(clampf(target.x, lo.x, hi.x), clampf(target.y, lo.y, hi.y))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var from := _focus
	_tween.tween_method(func(v: Vector2) -> void:
			_focus = v
			_apply(), from, want, FOLLOW_SEC)


## --- input ------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if board == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(ZOOM_STEP, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(1.0 / ZOOM_STEP, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_from = mb.position
				_drag_focus = _focus
				_release_follow()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			reset_view()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _drag_from
		board.position += d
		_focus = _drag_focus - d / _zoom
		accept_event()


## Keyboard: arrows pan, +/- zoom, 0 home, F follow. Returns true when it consumed the event, so
## the shell's own hotkeys are not stolen (one place decides who owns a key).
func handle_key(keycode: int) -> bool:
	if board == null:
		return false
	match keycode:
		KEY_LEFT:
			pan_by(Vector2(PAN_STEP, 0))
		KEY_RIGHT:
			pan_by(Vector2(-PAN_STEP, 0))
		KEY_UP:
			pan_by(Vector2(0, PAN_STEP))
		KEY_DOWN:
			pan_by(Vector2(0, -PAN_STEP))
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_at(ZOOM_STEP, size * 0.5)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_at(1.0 / ZOOM_STEP, size * 0.5)
		KEY_0, KEY_KP_0:
			reset_view()
		KEY_F:
			if _follow >= 0:
				_release_follow()
			else:
				follow(_follow_if_known())
		_:
			return false
	return true


## Which seat F should follow when none is set: the shell knows the turn; it stores it here.
var turn_pid := -1


func _follow_if_known() -> int:
	return turn_pid
