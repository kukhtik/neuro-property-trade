extends Node
## A1 adaptive-layout probe: boots the real launcher at a SMALL window (800x600)
## and verifies the game view still builds, the human can roll, and the layout
## re-computes proportional panel sizes (no fixed 1280x720 assumptions).
## Run windowed: godot --path game res://tools/ui_smoke_small.tscn

const MainScript := preload("res://main.gd")

var _launcher

func _ready() -> void:
	# force a small window BEFORE the launcher builds its layout
	DisplayServer.window_set_size(Vector2i(800, 600))
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	var lobby = _launcher.get("_lobby")
	if lobby == null:
		print("FAIL: no lobby"); quit(1); return
	print("PASS: lobby built at 800x600")

	# start the game
	lobby.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	var gv = _launcher.get("_game_view")
	if gv == null:
		print("FAIL: no game view after START"); quit(1); return
	print("PASS: game view built; human_pid=%d" % gv._human_pid)

	# resize the window AFTER the game view exists; the view's _process must
	# re-layout the proportional panels to the new (small) viewport
	DisplayServer.window_set_size(Vector2i(800, 600))
	for _i in 10:
		await get_tree().process_frame
	var pw: int = gv._panel_w()
	var jw: int = gv._journal_w()
	print("panel_w=%d journal_w=%d (after resize to 800x600)" % [pw, jw])
	if pw >= 235 or jw >= 300:
		print("FAIL: panel widths did not shrink after viewport resize")
		quit(1); return
	print("PASS: proportional panel widths adapt to small screen")

	# drive a human roll to prove the input path still works
	var eng = gv.engine
	var hp: int = gv._human_pid
	var res: Dictionary = gv.manager.push_intent(hp, "roll", {})
	if not res.get("ok", false):
		print("FAIL: human roll rejected at small screen: %s" % str(res.get("reason")))
		quit(1); return
	print("PASS: human roll executed at small screen")

	for _i in 30:
		await get_tree().process_frame
	print("PASS: game survives at 800x600; phase=%s" % str(eng.phase))
	await _shot_save("ui_small")
	quit(0)

func _shot_save(name: String) -> void:
	var vp := get_tree().root
	for _i in 6:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	var path := "%s.png" % name
	img.save_png(path)
	print("SAVED %s (%dx%d)" % [path, img.get_width(), img.get_height()])

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
