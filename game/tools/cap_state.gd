extends Node
## State-matched captures for the mockup comparison. The mockup renders show the
## awaiting-roll state of the first seat (turn-human) with a selected tile; this captures
## the SAME states from the real app so region metrics compare like with like:
##   --mode=turn  awaiting-roll state (no input; the LOCAL seat waits by design)
##   --tile=N     also select tile N shortly before the shot (fills the inspector)
## Run: godot --path game --resolution 1440x900 res://tools/cap_state.tscn -- --out=<abs> --tile=3

const MainScript := preload("res://main.gd")

var _n := 0
var _out := "user://cap.png"
var _tile := -1
var _size := Vector2i.ZERO
var _roll := false
var _launcher = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--tile="):
			_tile = int(s.substr(7))
		elif s.begins_with("--size="):
			# main.gd forces 1440x900 in its own _ready, so `--resolution` cannot be trusted:
			# override AFTER the launcher is up (frame 20), or a "compact" shot is a lie.
			var wh := s.substr(7).split("x")
			if wh.size() == 2:
				_size = Vector2i(int(wh[0]), int(wh[1]))
		elif s == "--roll":
			_roll = true
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 20 and _size != Vector2i.ZERO:
		DisplayServer.window_set_size(_size)
		get_window().size = _size
	if _n == 30 and _launcher != null and _launcher.has_method("_autostart"):
		_launcher.call("_autostart")
	if _n == 100 and _tile >= 0:
		var gv = _launcher.get("_game_view")
		if gv != null:
			gv.call("_on_tile_clicked", _tile)
	if _n == 120 and _roll:
		# cosmetic dice + last-roll chip so this frame compares with a mockup render that
		# shows a roll (the awaiting-roll state has no numbers to show)
		var gv2 = _launcher.get("_game_view")
		if gv2 != null:
			if gv2._board_scene != null and gv2._board_scene._center != null:
				gv2._board_scene._center.set_dice(4, 3)
			if gv2._actions != null:
				gv2._actions.set_last_roll(4, 3, false)
	if _n == 150:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
