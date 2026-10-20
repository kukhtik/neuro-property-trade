extends Control
## Dump the LIVE layout: every tile rect, every label rect and whether the text fits it.
## Written because "поля и текст поехали" is not answered by the gates that exist: SG-02 asks
## "does anything leave the window", READ-03 asks "is the font at least N px" - neither asks
## "does the name fit inside the cell it belongs to, and does it overlap its neighbour".

const MainScript := preload("res://main.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

var _launcher = null
var _frame := 0
var _done := false


func _ready() -> void:
	var size: Vector2i = LayoutProfile.new().screen
	DisplayServer.window_set_size(size)
	get_tree().root.size = size
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_launcher.call("_autostart")
		return
	if _frame < 70 or _done:
		return
	_done = true
	_dump()


func _dump() -> void:
	var board := _find_named(_launcher, "board")
	print("DUMP root=%s board=%s" % [str(get_tree().root.size),
		str(Rect2(board.global_position, board.size)) if board else "нет"])
	for node in _all(_launcher):
		if not (node is Label):
			continue
		var l := node as Label
		if not l.is_visible_in_tree():
			continue
		var txt := l.text.strip_edges()
		if txt == "":
			continue
		var r := Rect2(l.global_position, l.size)
		# how much of the text actually fits the box it was given
		# measure LINE BY LINE: a deliberate break in the string is not an overflow
		var need := 0.0
		for ln in txt.split("
"):
			need = maxf(need, l.get_theme_font("font").get_string_size(ln,
				HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
		var over: float = maxf(0.0, need - r.size.x)
		var flag := "OVER" if over > 1.0 else "ok"
		if l.name.begins_with("tile-") or l.name.begins_with("glance-"):
			print("DUMP %s '%s' at [%d,%d %dx%d] need=%.0f over=%.0f %s" % [
				str(l.name), txt.substr(0, 22), int(r.position.x), int(r.position.y),
				int(r.size.x), int(r.size.y), need, over, flag])
	for i in 40:
		var tv := _tile_at(i)
		if tv == null:
			continue
		var tr := Rect2(tv.global_position, tv.size)
		if i < 12 or i >= 36:
			print("CELL %02d [%d,%d %dx%d]" % [i, int(tr.position.x), int(tr.position.y),
				int(tr.size.x), int(tr.size.y)])
	_tiles_overlap()
	print("DUMP END")
	get_tree().quit(0)


func _tiles_overlap() -> void:
	var rects := []
	for i in 40:
		var tv := _tile_at(i)
		if tv != null:
			rects.append({"i": i, "r": Rect2(tv.global_position, tv.size)})
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			var ov: Rect2 = (rects[a]["r"] as Rect2).intersection(rects[b]["r"])
			if ov.size.x > 1.0 and ov.size.y > 1.0:
				print("OVERLAP cells %d and %d by %.1fx%.1f" % [
					int(rects[a]["i"]), int(rects[b]["i"]), ov.size.x, ov.size.y])


func _tile_at(idx: int) -> Control:
	var board := _find_named(_launcher, "board")
	if board == null:
		return null
	var n := 0
	for ch in board.get_children():
		if ch is Control and (ch as Control).get_script() != null \
				and str((ch as Control).get_script().resource_path).ends_with("tile_view.gd"):
			if n == idx:
				return ch as Control
			n += 1
	return null


func _find_named(root: Node, nm: String) -> Node:
	if str(root.name) == nm:
		return root
	for ch in root.get_children():
		var hit := _find_named(ch, nm)
		if hit != null:
			return hit
	return null


func _all(root: Node) -> Array:
	var out: Array = []
	for ch in root.get_children():
		out.append(ch)
		out.append_array(_all(ch))
	return out
