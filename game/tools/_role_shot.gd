extends Node
## Saves one frame of the REAL launcher. Used by tools/stage7_shots.gd, which
## launches this scene once per execution role.
const MainScript := preload("res://main.gd")
var _frames := 0
var _out := "user://shot.png"
var _launcher = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_frames += 1
	if _frames == 30 and _launcher != null:
		# start a match the way the smoke does, so the frame has a REAL board
		if _launcher.has_method("_autostart"):
			_launcher.call("_autostart")
		var ov = _launcher.get("_overlay")
		if ov != null and ov.has_method("_start_pressed"):
			ov.call("_start_pressed")
	if _frames == 120:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("SHOT %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
