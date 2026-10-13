extends Node
## v3 capture: boots the launcher, autostarts a match, optionally selects a tile, then
## saves the viewport to `--out=`. `--size=WxH` overrides the window AFTER the launcher
## has forced its own size (the `--resolution` CLI flag cannot be trusted for this).
##   godot --path game res://tools/v3_cap.tscn -- --out=<abs> [--size=880x600] [--tile=3]

const MainScript := preload("res://main.gd")

var _n := 0
var _out := "user://v3cap.png"
var _size := Vector2i.ZERO
var _tile := -1
var _launcher = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var wh := s.substr(7).split("x")
			if wh.size() == 2:
				_size = Vector2i(int(wh[0]), int(wh[1]))
		elif s.begins_with("--tile="):
			_tile = int(s.substr(7))
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
		if gv != null and gv.get("_board") != null:
			gv.call("_on_tile_clicked", _tile)
	if _n == 148:
		var gv9 = _launcher.get("_game_view")
		if gv9 != null:
			print("GEO gv=%s" % str(gv9.get_global_rect()))
			for nm in ["top", "seats", "stage", "act", "rightcol", "journal", "inspector"]:
				var nd = gv9.find_child(nm, true, false)
				if nd != null and nd is Control:
					print("GEO %s rect=%s" % [nm, str((nd as Control).get_global_rect())])
			var bs = gv9.get("_board")
			if bs != null and bs is Control:
				print("GEO board size=%s pos=%s tiles=%d" % [
					str((bs as Control).size), str((bs as Control).position),
					(bs.get("_tiles") as Array).size() if bs.get("_tiles") != null else -1])
				var tl = bs.get("_tiles")
				if tl != null and tl.size() > 0:
					print("GEO tile0 rect=%s tile1=%s tile10=%s tile20=%s" % [
						str((tl[0] as Control).get_global_rect()),
						str((tl[1] as Control).get_global_rect()),
						str((tl[10] as Control).get_global_rect()),
						str((tl[20] as Control).get_global_rect())])
				var tray = bs.get("_tray")
				if tray != null and tray is Control:
					print("GEO tray=%s" % str((tray as Control).get_global_rect()))
	if _n == 149:
		var gv8 = _launcher.get("_game_view")
		if gv8 != null:
			var top = gv8.find_child("top", true, false)
			var act = gv8.find_child("act", true, false)
			var seats2 = gv8.find_child("seats", true, false)
			for pair in [["top", top], ["act", act], ["seats", seats2]]:
				var nd = pair[1]
				if nd == null:
					continue
				print("MIN %s total=%s" % [str(pair[0]), str((nd as Control).get_combined_minimum_size())])
				if nd.get_child_count() > 0:
					var inner = nd.get_child(0)
					print("MIN %s inner=%s" % [str(pair[0]), str((inner as Control).get_combined_minimum_size()) if inner is Control else "?"])
					if inner != null and inner.get_child_count() > 0:
						var col2 = inner.get_child(0)
						if col2 is Control:
							print("MIN %s col=%s" % [str(pair[0]), str((col2 as Control).get_combined_minimum_size())])
							for c in col2.get_children():
								if c is Control:
									print("MIN   child %s min=%s" % [str(c.name), str((c as Control).get_combined_minimum_size())])
	if _n == 150:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
