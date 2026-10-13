extends Node
## Saves one frame of the REAL launcher after it has drawn, WITH A MATCH RUNNING.
##
## The first version screenshot the launch screen — no match, no board data, empty panels —
## and the result was then compared against a mockup drawn in-game. That comparison was
## invalid: it measured an empty lobby against a working interface and could only conclude
## the app was far behind. A role is only worth photographing once it has something to show.
const MainScript := preload("res://main.gd")
var _n := 0
var _out := "user://role.png"
var _launcher = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	# let the launcher start an offline match of its own, so the frame has real state:
	# players, money, tiles, a turn. `--autostart` is what a smoke of the UI needs.
	if _n == 30 and _launcher != null and _launcher.has_method("_autostart"):
		_launcher.call("_autostart")
	if _n == 60 and _launcher != null:
		var gv = _launcher.get("_game_view")
		if gv != null:
			print("WIDTHS viewport=%s gvsize=%s panel_w=%d journal_w=%d observer=%s" % [
				get_viewport().get_visible_rect().size, gv.size,
				gv.call("_panel_w"), gv.call("_journal_w"), gv.get("_observer")])
	if _n == 600:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
