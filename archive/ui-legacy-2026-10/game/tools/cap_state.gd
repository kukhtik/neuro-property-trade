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
	if _n == 145:
		var gv3 = _launcher.get("_game_view")
		if gv3 != null and gv3._board_scene != null and gv3._board_scene._center != null:
			var ctr = gv3._board_scene._center
			print("CAPDBG center rect=%s vis_tree=%s" % [str(ctr.get_global_rect()), str(ctr.is_visible_in_tree())])
			var tr = ctr.get("_dice")
			if tr != null:
				print("CAPDBG tray rect=%s vis=%s" % [str(tr.get_global_rect()), str(tr.is_visible_in_tree())])
				for d in tr.get_children():
					if str(d.name).begins_with("Die"):
						print("CAPDBG %s rect=%s vis_tree=%s value=%s" % [
							str(d.name), str(d.get_global_rect()), str(d.is_visible_in_tree()),
							str(d.get_meta("value", -1))])
				# pure-green probe: a uniquely-coloured rect placed at the TRAY's tree coords —
				# if it lands elsewhere on screen, the canvas is transformed and all our
				# screen-pixel forensics were reading the wrong coordinates
				var probe := ColorRect.new()
				probe.color = Color(0, 1, 0, 1)
				probe.position = tr.get_global_rect().position
				probe.size = Vector2(80, 40)
				probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
				gv3._board_scene.add_child(probe)
	if _n == 146:
		var gv4 = _launcher.get("_game_view")
		if gv4 != null and gv4._board_scene != null:
			var bs4 = gv4._board_scene
			print("CAPDBG board_scene modulate=%s self=%s rect=%s" % [
				str(bs4.modulate), str(bs4.self_modulate), str(bs4.get_global_rect())])
			for ch in bs4.get_children():
				var extra := ""
				var vis_str := "n/a"
				if ch is CanvasItem:
					extra = " mod=%s" % str(ch.modulate)
					vis_str = str(ch.visible)
				if ch is Control:
					extra += " z=%s rect=%s" % [str(ch.z_index), str((ch as Control).get_global_rect())]
				print("CAPDBG child %s cls=%s vis=%s%s" % [
					str(ch.name), str(ch.get_class()), vis_str, extra])
			var ov = bs4.get("_overlay")
			if ov != null:
				print("CAPDBG overlay visible=%s rect=%s cls=%s" % [
					str(ov.visible), str(ov.get_global_rect()), str(ov.get_class())])
				ov.visible = false
	if _n == 148:
		var gv5 = _launcher.get("_game_view")
		if gv5 != null and gv5._board_scene != null:
			var bs5 = gv5._board_scene
			var cam = bs5.get("_camera")
			var cen = bs5.get("_center")
			if cam != null:
				print("CAPDBG camera pos=%s scale=%s rot=%s size=%s" % [
					str(cam.position), str(cam.scale), str(cam.rotation), str(cam.size)])
			if cen != null:
				print("CAPDBG center pos=%s scale=%s self_modulate=%s" % [
					str(cen.position), str(cen.scale), str(cen.self_modulate)])
			var sp = bs5.get("_spectacle")
			if sp != null:
				print("CAPDBG spectacle enabled=%s visible=%s scale=%s pos=%s" % [
					str(sp.get("_enabled")), str(sp.visible), str(sp.scale), str(sp.position)])
		var img2 := get_viewport().get_texture().get_image()
		var best := 0.0
		var bx := 0
		var by := 0
		for yy in range(100, 820, 3):
			for xx in range(290, 1100, 3):
				var c := img2.get_pixel(xx, yy)
				var l := (c.r + c.g + c.b) / 3.0
				if l > best:
					best = l
					bx = xx
					by = yy
		print("CAPDBG brightest in board area: (%d,%d) lum=%.2f col=%s" % [
			bx, by, best, str(img2.get_pixel(bx, by))])
	if _n == 149:
		var gv6 = _launcher.get("_game_view")
		if gv6 != null and gv6._board_scene != null and gv6._board_scene._center != null:
			var tr6 = gv6._board_scene._center.get("_dice")
			if tr6 != null:
				var red := ColorRect.new()
				red.color = Color(1, 0, 0, 1)
				red.custom_minimum_size = Vector2(20, 20)
				red.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr6.add_child(red)
				print("CAPDBG red child added to tray")
			var img3 := get_viewport().get_texture().get_image()
			print("CAPDBG in-game px(635,385)=%s px(700,437)=%s px(500,200)=%s" % [
				str(img3.get_pixel(635, 385)), str(img3.get_pixel(700, 437)), str(img3.get_pixel(500, 200))])
	if _n == 150:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("CAPTURED %s %dx%d" % [_out, img.get_width(), img.get_height()])
		get_tree().quit(0)
