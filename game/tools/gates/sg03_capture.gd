extends Node
## SG-03 capture — one real frame of a mid-match app under a chosen skin, saved as PNG.
## NOT headless: the palette gate needs real rendered pixels (headless returns blank textures),
## so the shell runs Godot with `--rendering-driver opengl3` and a hidden window.
##
## Usage: godot --path game --rendering-driver opengl3 res://tools/gates/sg03_capture.tscn --
##          --out=<abs path> --skin=<id>
const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

var _n := 0
var _out := "user://sg03.png"
var _skin := ""
var _launcher = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--skin="):
			_skin = s.substr(7)
	if _skin != "":
		SkinManager.chosen = _skin
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_n += 1
	if _n == 30 and _launcher != null and _launcher.has_method("_autostart"):
		_launcher.call("_autostart")
	if _n == 600:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_out)
		if err != OK:
			print("SG-03 CAPTURE FAILED: save_png rc=%d" % err)
			get_tree().quit(1)
			return
		print("SG-03 CAPTURED %s %dx%d skin=%s" % [_out, img.get_width(), img.get_height(), SkinManager.chosen])
		get_tree().quit(0)
