extends Node
## WHY ARE 12 CELLS BLANK? Read what each cell actually decided: its size, its label_step, and
## whether it renders a name and a price. tile_view computes `_name.visible = step < 3`, and step 3
## is "cell narrower than 44px" - so this prints the cells that fell into it.
##
## Run: godot --path game --rendering-driver opengl3 res://tools/cell_step_probe.tscn
const MainScript := preload("res://main.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

var _launcher = null
var _t := 0
var _done := false


func _ready() -> void:
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _t == 20:
		_launcher.call("_autostart")
	if _t < 80:
		return
	_done = true
	_report()
	get_tree().quit(0)


func _report() -> void:
	var gv = _launcher.get("_game_view")
	var board: Control = _find_stage(gv)
	if board == null:
		print("CELL STEP: no board")
		return
	var blanks: Array = []
	var by_step := {0: 0, 1: 0, 2: 0, 3: 0}
	for tv in board.get_children():
		if tv.get("index") == null or not tv.has_method("apply"):
			continue
		var c: float = (tv as Control).size.x
		var step: int = LayoutProfile.label_step(c)
		by_step[step] = int(by_step[step]) + 1
		var has_name := false
		var has_price := false
		for ch in (tv as Control).get_children():
			if ch is Label:
				var l := ch as Label
				if str(l.name) == "tile-name" and l.visible and l.text.strip_edges() != "":
					has_name = true
				if str(l.name) == "tile-price" and l.visible and l.text.strip_edges() != "":
					has_price = true
		if not has_name and not has_price:
			blanks.append("%d(w=%.0f,step=%d)" % [int(tv.get("index")), c, step])
	print("CELL STEP board=%dx%d cell_px=%.0f  steps: full=%d price_hidden=%d small=%d smallest=%d"
		% [int(board.size.x), int(board.size.y), float(board.size.x) / 11.0,
			int(by_step[0]), int(by_step[1]), int(by_step[2]), int(by_step[3])])
	print("CELL STEP blank cells: %s" % ("none" if blanks.is_empty() else ", ".join(blanks)))


func _find_stage(n: Node) -> Control:
	for c in n.get_children():
		if str(c.name) == "stage" and c is Control:
			return c as Control
		var d := _find_stage(c)
		if d != null:
			return d
	return null
