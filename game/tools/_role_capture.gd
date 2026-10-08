extends Node
## Saves one frame of the REAL launcher after it has drawn. Written by the smoke.
const MainScript := preload("res://main.gd")
var _n := 0
var _out := "user://role.png"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	add_child(MainScript.new())

func _process(_dt: float) -> void:
	_n += 1
	if _n == 600:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
