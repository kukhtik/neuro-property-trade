extends SceneTree
## Why is the ring's interior still empty? Builds the REAL board at the launch size and prints
## the geometry the FILL gate cannot see: the panno's rect, its root column and every zone.
## Run: godot --headless --path game --script res://tools/panno_probe.gd

const BoardScene := preload("res://visual/board_scene.gd")

var _frames := 0
var _board: Control


func _init() -> void:
	root.size = Vector2i(1600, 1200)
	_board = BoardScene.new()
	root.add_child(_board)
	_board.position = Vector2.ZERO
	_board.size = Vector2(1600, 1200)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var p = _board.get("_panno")
	if p == null:
		print("PROBE panno=NULL")
		quit(1)
		return true
	print("PROBE board=", _board.size, " panno pos=", p.position, " size=", p.size,
		" visible=", p.visible, " clip=", p.clip_contents)
	if p.get_child_count() > 0:
		var r: Control = p.get_child(0)
		print("PROBE panno-root pos=", r.position, " size=", r.size, " children=", r.get_child_count())
		for i in r.get_child_count():
			var z: Control = r.get_child(i)
			print("PROBE zone[", i, "] name=", z.name, " pos=", z.position, " size=", z.size,
				" visible=", z.visible, " min=", z.get_combined_minimum_size())
			if z.get_child_count() > 0:
				var col: Control = z.get_child(0)
				print("      col size=", col.size, " kids=", col.get_child_count())
				for j in col.get_child_count():
					var c: Control = col.get_child(j)
					print("        kid[", j, "] ", c.get_class(), " size=", c.size,
						" min=", c.get_combined_minimum_size(), " vis=", c.visible,
						" wrap=", (c.autowrap_mode if c is Label else -1),
						" text=", (c.text.left(24) if c is Label else ""))
	var cells := float(_board.get("_cell"))
	print("PROBE cell=", cells, " ring=", cells * 11.0, " interior=", cells * 9.0)
	quit(0)
	return true
