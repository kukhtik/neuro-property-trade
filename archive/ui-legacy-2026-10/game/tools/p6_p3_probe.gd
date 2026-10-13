extends Node
## Phase 3 probe: settings overlay lives on a top CanvasLayer (layer 50), and
## the tile_count setting is collected from the new SpinBox.

const MainScript := preload("res://main.gd")

var _had_fail := false
var _checks := 0

func _ready() -> void:
	await _check_overlay_layer()
	await _check_tile_count_collected()

	if _had_fail:
		quit(1)
	else:
		print("P6_P3_PROBE: ALL PASSED (%d checks)" % _checks)
		quit(0)

func _check_overlay_layer() -> void:
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	var overlay = launcher.get("_overlay")
	if overlay == null:
		_fail("no overlay")
		return
	var parent = overlay.get_parent()
	if not (parent is CanvasLayer):
		_fail("overlay parent is %s, expected CanvasLayer" % parent.get_class())
		return
	if int(parent.layer) != 50:
		_fail("overlay layer=%d, expected 50" % int(parent.layer))
		return
	_pass("overlay on CanvasLayer layer=50 (separated from GameView tree)")

func _check_tile_count_collected() -> void:
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	var overlay = launcher.get("_overlay")
	var tc = overlay.get("_tile_count")
	if tc == null:
		_fail("no tile_count SpinBox")
		return
	tc.value = 56
	var s = overlay.call("_collect_settings")
	if int(s.tile_count) != 56:
		_fail("collected tile_count=%d, expected 56" % int(s.tile_count))
		return
	_pass("tile_count SpinBox collected (56) into settings")

func _pass(label: String) -> void:
	_checks += 1
	print("PASS: " + label)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
