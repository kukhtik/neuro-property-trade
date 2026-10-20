extends Node
## PANEL-NOT-EMPTY gate — R-3 (docs/specs/ui-redesign-brief.md §3.1, §5).
##
## THE RULE (literal): a panel whose CONTENT is fewer than 2 lines of text while its area is over
## 40 000 px is a hole with a border. Today's example in the brief: four player cards of 242x245
## (59 290 px) carrying two lines.
##
## WHY A TREE, NOT A FRAME: R-1 asks "does the frame look empty"; R-3 asks "which panel is empty and
## why". A frame can be 95 % covered by four nearly-empty cards. So this gate boots the REAL shell,
## autostarts a match, and walks the tree for the DEEPEST panels - the ones that actually own text.
##
## Verdict: ==> PANEL-NOT-EMPTY PASSED (N panels, 0 empty) / FAILED: <name> <area> px with <k> line(s)
## The verdict carries the REGISTRY ID: the runner matches verdicts by `==> <id>`, and a gate whose
## line says `==> PANEL` is reported as "did not run" while it ran fine (measured 18.10).
## Run: godot --headless --path game res://tools/gates/panel_gate.tscn

const MainScript := preload("res://main.gd")
const LayoutProfile := preload("res://ui/core/layout_profile.gd")

const MIN_AREA := 40000.0
const MIN_LINES := 2

var _launcher = null
var _frame := 0
var _done := false
var _fails: Array = []
var _rows: Array = []


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
	# 60 frames after the autostart: the shell has laid out AND the first projection has reached the
	# panno. Measured at 22 frames: the players and journal zones were still captions only, which
	# made the gate report the gate's own impatience as a product defect.
	if _frame < 70 or _done:
		return
	_done = true
	print("PANEL PROFILE root=%s screen=%s" % [str(get_tree().root.size), str(LayoutProfile.new().screen)])
	_walk(_launcher)
	_report()


## Deepest panels only: a parent panel must not re-count its children's text.
func _walk(node: Node) -> void:
	if node is Control:
		var c := node as Control
		# A node on its way out is not part of the UI: `_place_board` rebuilds the ring when the band
		# changes and queue_frees the old tiles, whose children are already gone - so a zombie tile
		# measured as "a 53 250px panel carrying 0 lines" and turned PANEL-NOT-EMPTY red with a node
		# a human can never see.
		# `decor` marks a Panel that exists to draw (the owner border). It is not a container, so
		# "carries no text" is not a defect for it - and every other panel still has to say something.
		if not c.has_meta("decor") and not c.is_queued_for_deletion() and c.is_visible_in_tree() 				and _is_panel(c) and not _has_panel_child(c):
			var area := c.size.x * c.size.y
			if area > MIN_AREA:
				var lines := _lines_in(c)
				_rows.append({"name": str(c.name), "area": int(area), "lines": lines,
					"rect": "[%d,%d %dx%d]" % [int(c.global_position.x),
						int(c.global_position.y), int(c.size.x), int(c.size.y)]})
				if lines < MIN_LINES:
					_fails.append("%s %s area=%d px carries %d line(s) of text" % [
						str(c.name), _rows[-1]["rect"], int(area), lines])
					if OS.get_environment("PANEL_DEBUG") != "":
						# WHICH node is this? Without this the verdict names a Panel by an auto id
						# (@Panel@1590) that appears nowhere in the source, and the fix becomes a guess.
						print("PANEL DEBUG %s class=%s script=%s path=%s parent=%s grandparent=%s children=%s" % [
							str(c.name), c.get_class(), str(c.get_script().resource_path if c.get_script() != null else "-"), str(get_path_to(c)),
							str("%s(%s)" % [c.get_parent().name if c.get_parent() else "?", (c.get_parent().get_script().resource_path if c.get_parent() and c.get_parent().get_script() else "-")]),
							str(c.get_parent().get_parent().name if c.get_parent() and c.get_parent().get_parent() else "?"),
							str(c.get_children().map(func(x): return str(x.name) + ":" + str(x.get_class())))])
	for ch in node.get_children():
		_walk(ch)


func _is_panel(c: Control) -> bool:
	if c is PanelContainer or c is Panel:
		return true
	var n := str(c.name)
	return n.begins_with("dock-") or n.begins_with("rail-") or n.begins_with("drawer-") \
		or n.begins_with("zone-") or n.begins_with("card-")


func _has_panel_child(c: Control) -> bool:
	for ch in c.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree() and _is_panel(ch as Control):
			return true
	return false


## A line = a visible label with text; a wrapped paragraph counts by its own newlines.
## RichTextLabel counts its laid-out lines. Buttons count (their label is the control's word).
func _lines_in(root: Control) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
			if not (ch is Control) or not (ch as Control).is_visible_in_tree():
				continue
			var c := ch as Control
			if c is Label:
				var t := (c as Label).text.strip_edges()
				if t != "" and (c as Label).modulate.a > 0.05:
					n += t.count("\n") + 1
			elif c is RichTextLabel:
				n += maxi(1 if ((c as RichTextLabel).text.strip_edges() != "") else 0,
					(c as RichTextLabel).get_line_count())
			elif c is Button:
				if (c as Button).text.strip_edges() != "":
					n += 1
	return n


func _report() -> void:
	for r in _rows:
		print("PANEL %s %s area=%d lines=%d" % [r["name"], r["rect"], int(r["area"]), int(r["lines"])])
	for f in _fails:
		print("PANEL EMPTY %s" % f)
	if _fails.is_empty():
		print("==> PANEL-NOT-EMPTY PASSED (%d panels over %d px, 0 empty, every one carries >= %d lines)" % [
			_rows.size(), int(MIN_AREA), MIN_LINES])
		get_tree().quit(0)
		return
	print("==> PANEL-NOT-EMPTY FAILED: %s" % " | ".join(_fails))
	get_tree().quit(1)
