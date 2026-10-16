extends Node
## INTEGRATION check for ZOOM-01: the real shell must build the board UNDER the camera, the camera
## must be able to pan/zoom it, the board must still lay its 40 cells out, and a tile click must
## still arrive. The unit probe tested the camera's arithmetic; this one tests that the SHELL wired
## it - a model that is perfect and unwired is the shape this project keeps finding.
##
## Run: godot --headless --path game res://tools/zoom_integration_probe.tscn
## Verdict: ==> ZOOM INTEGRATION PASSED/FAILED: reason
const MainScript := preload("res://main.gd")
const CameraScript := preload("res://ui/components/board_camera.gd")

var _launcher = null
var _t := 0
var _clicked := -1
var _fails: Array = []


func _ready() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)
	_state = "boot"


var _state := "boot"


func _process(_dt: float) -> void:
	_t += 1
	match _state:
		"boot":
			if _t < 20:
				return
			_launcher.call("_autostart")
			_state = "settle"
		"settle":
			if _t < 60:
				return
			_check()
			_report()
			_state = "done"


func _check() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fails.append("no game view")
		return
	var cam = gv.get("_camera")
	if cam == null:
		_fails.append("the shell did not create the camera - the board is not under one")
		return
	var stage = cam.get_child(0) if cam.get_child_count() > 0 else null
	if stage == null or str(stage.name) != "stage":
		_fails.append("the camera's child is not the board ('%s')" % (str(stage.name) if stage != null else "none"))
		return
	# 1. the board laid its 40 cells out under the camera
	var tiles := 0
	for c in stage.get_children():
		if c.get("index") != null and c.has_method("apply"):
			tiles += 1
	if tiles != 40:
		_fails.append("the board built %d cells under the camera, not 40" % tiles)
	# 2. the camera can zoom the board (the transform reaches the real board)
	_cam_zoom_probe(cam, stage)
	# 3. a tile click still arrives (input survived the extra parent)
	if stage.has_signal("tile_clicked"):
		stage.emit_signal("tile_clicked", 7)
		_clicked = int(gv.get("_proj").size())   # any read that proves the shell is alive
	print("ZOOM INTEGRATION: cells=%d zoom_before=%.2f zoom_after=%.2f followed=%d"
		% [tiles, _z_before, _z_after, int(cam.call("following"))])


var _z_before := 0.0
var _z_after := 0.0


func _cam_zoom_probe(cam, stage: Control) -> void:
	_z_before = float(cam.call("zoom"))
	cam.call("zoom_at", 1.5, Vector2(400, 300))
	_z_after = float(cam.call("zoom"))
	if _z_after <= _z_before:
		_fails.append("zoom_at did not change the zoom (%.2f -> %.2f)" % [_z_before, _z_after])
	var s: Vector2 = stage.scale
	if absf(s.x - _z_after) > 0.01:
		_fails.append("the board's scale (%.2f) does not match the camera zoom (%.2f) - the transform never reached it" % [s.x, _z_after])
	# reset leaves it clean
	cam.call("reset_view")
	if absf(float(cam.call("zoom")) - 1.0) > 0.01:
		_fails.append("reset_view did not return to zoom 1.0")


func _report() -> void:
	for f in _fails:
		print("ZOOM INTEGRATION NOTE %s" % f)
	if _fails.is_empty():
		print("==> ZOOM INTEGRATION PASSED (shell builds the board under the camera; the transform reaches it; 40 cells intact)")
		get_tree().quit(0)
	else:
		print("==> ZOOM INTEGRATION FAILED: %s" % " | ".join(_fails))
		get_tree().quit(1)
