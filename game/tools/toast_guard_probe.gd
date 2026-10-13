extends Node
## F-68 measured on the LIVE layout: a notification may never cover the board (stage), the
## console (act) or the centre scene. Desktop keeps the toast host in the RIGHT DOCK; the
## compact profile folds the dock host away and the console's one-line ticker carries the
## text instead (the ticker lives INSIDE the console by construction).
## Run: godot --path game res://tools/toast_guard_probe.tscn

const MainScript := preload("res://main.gd")

var _had_fail := false

func _ready() -> void:
	# headless starts at a 64x64 viewport; this probe measures the real layout
	get_tree().root.size = Vector2i(1440, 900)
	var launcher = MainScript.new()
	add_child(launcher)
	for _i in 20:
		await get_tree().process_frame
	var gv = launcher.get("_game_view")
	if gv == null:
		_fail("no GameView"); return
	var overlay = launcher.get("_overlay")
	overlay._rng_seed.value = 4242
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	if gv.engine == null:
		_fail("engine not built after START"); return

	var stack = gv._toast_stack
	if stack == null:
		_fail("no toast host in GameView"); return
	stack.dismiss_all()
	for i in 3:
		stack.show_toast("probe toast %d" % i, ["info", "warning", "success"][i], 30.0)
	for _i in 3:
		await get_tree().process_frame

	var toasts: Array = []
	for c in stack._toast_container.get_children():
		toasts.append(c)
	if toasts.is_empty():
		_fail("no toasts to measure"); return

	var regions := [
		["stage", gv._stage_col], ["board", gv._board_scene], ["console", gv._actions],
	]
	for t in toasts:
		var tr: Rect2 = (t as Control).get_global_rect()
		for pair in regions:
			var r: Rect2 = (pair[1] as Control).get_global_rect()
			if tr.intersects(r):
				_fail("a toast covers %s: toast %s vs %s" % [pair[0], tr, r]); return
	# and the host itself lives in the right dock: inside the window, right of the board
	var hr: Rect2 = (stack._toast_container as Control).get_global_rect()
	if hr.end.x > float(get_tree().root.size.x) + 1.0 or hr.position.x < 0.0:
		_fail("toast host runs outside the window: %s" % hr); return
	if gv._board_scene != null and hr.position.x < gv._board_scene.get_global_rect().end.x - 1.0:
		_fail("toast host overlaps the board column: host %s vs board %s"
			% [hr, gv._board_scene.get_global_rect()]); return
	print("PASS: toasts stay in the right dock, clear of stage/board/console")

	# compact: the dock host folds away; the console ticker carries the text
	get_tree().root.size = Vector2i(1100, 800)
	for _i in 8:
		await get_tree().process_frame
	stack.show_toast("compact toast", "info", 30.0)
	for _i in 3:
		await get_tree().process_frame
	if stack._toast_container.visible:
		_fail("compact: the dock toast host must fold away"); return
	if not gv._actions._ticker.visible:
		_fail("compact: the console ticker must carry the notification"); return
	if gv._actions._ticker.text != "compact toast":
		_fail("compact: ticker shows %r" % gv._actions._ticker.text); return
	print("PASS: compact folds the host away and the console ticker shows the notification")

	if _had_fail:
		quit(1)
	else:
		print("TOAST GUARD PROBE: ALL PASSED")
		quit(0)

func _fail(msg: String) -> void:
	_had_fail = true
	print("FAIL: " + msg)
	quit(1)

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
