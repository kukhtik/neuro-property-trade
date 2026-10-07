extends SceneTree
const MainScript := preload("res://main.gd")
func _init() -> void: _run()
func _run() -> void:
	await process_frame
	var l = MainScript.new(); root.add_child(l)
	for i in 12: await process_frame
	var ov = l.get("_overlay"); ov.call("_start_pressed")
	for i in 20: await process_frame
	var gv = l.get("_game_view")
	var eo = gv.get("_event_overlay")
	print("before: pos=", eo.position, " size=", eo.size)
	gv.call("_fit_event_overlay")
	print("after : pos=", eo.position, " size=", eo.size)
	print("journal panel size=", gv.get("_journal").size, " global=", gv.get("_journal").global_position)
	print("gv size=", gv.size, " gv global=", gv.global_position)
	quit(0)
