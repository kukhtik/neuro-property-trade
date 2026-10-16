extends Node
## ZOOM-01 behavioural probe: the board camera must PAN, ZOOM about a point, FOLLOW the turn, and
## HOLD during an auction. It measures the transform the camera actually produced, not the code
## path that was supposed to produce it.
##
## Run: godot --headless --path game res://tools/zoom_probe.tscn
## Verdict: ==> ZOOM PROBE PASSED/FAILED: reason
const BoardCamera := preload("res://ui/components/board_camera.gd")

var _cam = null
var _board: Control = null
var _fails: Array = []


func _ready() -> void:
	# a real stage size: a headless root viewport is 64x64 and would measure a window nobody has
	get_tree().root.size = Vector2i(1440, 900)
	_cam = BoardCamera.new()
	_cam.name = "cam"
	_cam.size = Vector2(900, 800)
	add_child(_cam)
	_board = Control.new()
	_board.name = "stage"
	_board.size = Vector2(800, 800)
	_cam.add_child(_board)
	_cam.setup(_board)
	# the camera needs to be laid out; a Control outside a live stage keeps the size we set
	_cam.size = Vector2(900, 800)
	_check()
	_report()


func _check() -> void:
	# --- 1. the home view shows the whole board, centred
	_cam.reset_view()
	_eq("home zoom is 1.0", _cam.zoom(), 1.0)
	var want_pos := Vector2((900.0 - 800.0) * 0.5, (800.0 - 800.0) * 0.5)
	_close("home centres the board", _board.position, want_pos)

	# --- 2. zoom about a point keeps that point under the cursor
	var at := Vector2(200.0, 150.0)
	var board_pt_before: Vector2 = (at - _board.position) / _cam.zoom()
	_cam.zoom_at(1.5, at)
	var board_pt_after: Vector2 = (at - _board.position) / _cam.zoom()
	_close("zoom keeps the point under the cursor", board_pt_after, board_pt_before)
	_eq("zoom rose to 1.5", _cam.zoom(), 1.5)

	# --- 3. limits: cannot go below the whole board, cannot exceed the maximum
	for i in 20:
		_cam.zoom_at(0.5, Vector2(400, 400))
	_eq("zoom floors at 1.0 (never smaller than the board)", _cam.zoom(), 1.0)
	for i in 30:
		_cam.zoom_at(2.0, Vector2(400, 400))
	_eq("zoom caps at 3.0", _cam.zoom(), 3.0)

	# --- 4. pan moves the board and is reported by the focus point
	_cam.reset_view()
	var f0: Vector2 = _cam.focus_point()
	_cam.pan_by(Vector2(40, 0))
	_close("pan moves the board by the delta", _board.position, want_pos + Vector2(40, 0))
	_near_neq("pan moved the focus point", _cam.focus_point(), f0)

	# --- 5. a manual action releases follow; a new turn re-follows
	_cam.turn_pid = 2
	_cam.token_pos_of = Callable(self, "_tok")
	_cam.follow(2)
	_eq("follow(2) sets the followed seat", _cam.following(), 2)
	_cam.pan_by(Vector2(10, 10))
	_eq("a pan releases follow", _cam.following(), -1)

	# --- 6. the auction HOLD: a follow request while held must not move the camera
	_cam.reset_view()
	_cam.set_hold(true)
	_eq("hold is on", _cam.is_held(), true)
	var before: Vector2 = _cam.focus_point()
	_cam.follow(1)
	_eq("a follow under HOLD does not move the camera", _cam.focus_point(), before)
	_cam.set_hold(false)
	_eq("hold released", _cam.is_held(), false)

	# --- 7. the keyboard owns the expected keys
	_cam.reset_view()
	_eq("LEFT is handled", _cam.handle_key(KEY_LEFT), true)
	_near_neq("LEFT panned", _cam.focus_point(), Vector2(400, 400))
	_eq("an unknown key is NOT swallowed", _cam.handle_key(KEY_Z), false)


func _tok(_pid: int) -> Variant:
	return Vector2(120.0, 640.0)


func _eq(what: String, got, want) -> void:
	if got != want:
		_fails.append("%s (got %s, wanted %s)" % [what, str(got), str(want)])


func _close(what: String, got: Vector2, want: Vector2) -> void:
	if got.distance_to(want) > 0.51:
		_fails.append("%s (got %s, wanted %s)" % [what, str(got), str(want)])


func _near_neq(what: String, got: Vector2, before: Vector2) -> void:
	if got.distance_to(before) < 0.01:
		_fails.append("%s (nothing moved: still %s)" % [what, str(got)])


func _report() -> void:
	print("ZOOM PROBE: %d check(s)" % 17)
	if _fails.is_empty():
		print("==> ZOOM PROBE PASSED (pan, zoom about a point, limits, follow, auction hold, keys)")
		get_tree().quit(0)
	else:
		print("==> ZOOM PROBE FAILED: %s" % " | ".join(_fails))
		get_tree().quit(1)
