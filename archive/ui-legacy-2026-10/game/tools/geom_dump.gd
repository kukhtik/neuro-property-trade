extends Node
## Machine-readable geometry dump of the LIVE GameView at 1440x900, keyed exactly like the
## prototype extractor (tools/ci geometry diff). Prints `GEOM <key> x y w h` lines.
## Run: godot --path game res://tools/geom_dump.tscn

const MainScript := preload("res://main.gd")

func _ready() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	var l = MainScript.new()
	add_child(l)
	for _i in 20:
		await get_tree().process_frame
	var ov = l.get("_overlay")
	ov._rng_seed.value = 77
	ov.call("_start_pressed")
	for _i in 18:
		await get_tree().process_frame
	var gv = l.get("_game_view")
	if gv == null or gv.engine == null:
		print("GEOM ERROR no game"); quit(1); return

	_dump("top", gv._top)
	_dump("seats", gv._players_rail)
	_dump("stage", gv._stage_col)
	_dump("board", gv._board_scene)
	if gv._board_scene != null:
		_dump("center", gv._board_scene._center)
	_dump("act", gv._actions)
	_dump_node("act_row1", gv._actions, "Row1")
	_dump_node("act_prompt", gv._actions, "Prompt")
	_dump_node("act_lastroll", gv._actions, "LastRoll")
	_dump_node("act_row2", gv._actions, "Row2")
	_dump("rightcol", gv._rightcol)
	_dump("journal", gv._jpanel_rail)
	_dump("journal_panel", gv._journal)
	_dump("inspector", gv._inspector)
	_dump("toast_list", gv._toast_stack._toast_container)
	if gv._board_scene != null and gv._board_scene._board != null:
		var tn: Array = gv._board_scene._board._tile_nodes
		if tn.size() > 0:
			_dump("tile", tn[0])

	# ---- compact 880x600: the minimum supported window -------------------------------
	get_tree().root.size = Vector2i(880, 600)
	for _i in 12:
		await get_tree().process_frame
	print("GEOM --- compact 880x600 ---")
	_dump("top", gv._top)
	_dump("seats", gv._players_rail)
	_dump("stage", gv._stage_col)
	_dump("board", gv._board_scene)
	_dump("act", gv._actions)
	_dump("rightcol", gv._rightcol)
	_dump("inspector", gv._inspector)
	_dump_node("act_row1", gv._actions, "Row1")
	_dump_node("act_row2", gv._actions, "Row2")
	_dump("journal", gv._jpanel_rail)
	if gv._board_scene != null and gv._board_scene._board != null:
		var tn2: Array = gv._board_scene._board._tile_nodes
		if tn2.size() > 0:
			_dump("tile", tn2[0])
	# overflow checks: bars must keep their controls inside their own width
	_bar_overflow("act_row2", gv._actions, "Row2", gv._actions)
	_bar_overflow("top", gv._top, "", gv._top)
	print("GEOM DONE")
	quit(0)


## Sum the visible children of a bar and compare with the bar's own width.
func _bar_overflow(key: String, bar, child_name: String, box) -> void:
	if bar == null or not (bar is Control):
		return
	var inner: Node = bar.find_child(child_name, true, false) if child_name != "" else bar
	if inner == null:
		return
	var total := 0.0
	var n := 0
	for c in (inner as Node).get_children():
		if c is Control and (c as Control).visible and (c as Control).size.x > 0.0:
			total += (c as Control).size.x
			n += 1
	var sep := 10.0 * maxf(0.0, float(n - 1))
	var bar_w: float = (box as Control).size.x
	print("GEOM OVERFLOW %s children_sum=%d (+seps=%d) bar_w=%d %s"
		% [key, int(total), int(total + sep), int(bar_w),
			"OK" if total + sep <= bar_w + 1.0 else "OVERFLOWS"])


func _dump(k: String, n) -> void:
	if n == null or not (n is Control):
		print("GEOM %s NONE" % k)
		return
	var r: Rect2 = (n as Control).get_global_rect()
	print("GEOM %s %d %d %d %d" % [k, int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)])


func _dump_node(k: String, root: Node, name: String) -> void:
	if root == null:
		print("GEOM %s NONE" % k)
		return
	var n := root.find_child(name, true, false)
	_dump(k, n)


func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
