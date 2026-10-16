extends Node
## THE OWNER'S QUESTION, MEASURED: "половина панелей абсурдно огромные с парой строк информации,
## некоторые вообще пустые".
##
## READ-02 measures the largest GAP between content rows, so a panel whose one card is stretched to
## fill the dock reports 0% empty while showing two lines of text - the gate answers a different
## question than the player asks. This probe asks the player's question instead:
##
##     what fraction of a panel's AREA is actually covered by TEXT?
##
## A dock with one line of text in 700px of panel has a tiny text fraction and a huge one. That is
## the number the complaint is about, and it is measured, not argued.
##
## It also counts, per board cell, how many labels carry text - because the owner reports cells that
## look DOUBLED ("клетки почему-то по две") and cells that look EMPTY.
##
## Run: godot --path game --rendering-driver opengl3 res://tools/layout_density_probe.tscn
## Verdict: ==> LAYOUT DENSITY ... (report only - this is a measurement, not a threshold gate)
const MainScript := preload("res://main.gd")

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
	if gv == null:
		print("==> LAYOUT DENSITY: no game view")
		return
	for id in ["seats", "journal", "inspector", "act", "top"]:
		var n: Node = gv.find_child(id, true, false)
		if n is Control:
			_text_fraction(id, n as Control)
	# the board: how many text-bearing labels per cell, and how many cells carry NO text
	_cells(gv)


## Fraction of a panel's area covered by its visible TEXT (Label/Button rects), and the same for the
## panel's single biggest text block - a panel that is 800px tall showing a 20px line is the shape
## the owner is describing.
func _text_fraction(id: String, panel: Control) -> void:
	var area: float = panel.size.x * panel.size.y
	if area <= 1.0:
		print("LAYOUT DENSITY %-10s NOT LAID OUT" % id)
		return
	var labels: Array = []
	_collect_text(panel, labels)
	var text_area := 0.0
	var biggest := 0.0
	for l in labels:
		var r: Rect2 = (l as Control).get_global_rect()
		var a: float = minf(r.size.x, panel.size.x) * minf(r.size.y, panel.size.y)
		text_area += a
		biggest = maxf(biggest, a)
	print("LAYOUT DENSITY %-10s panel=%dx%d text_labels=%d text_area=%.1f%% biggest_block=%.0fpx (%.1f%% of panel height)"
		% [id, int(panel.size.x), int(panel.size.y), labels.size(),
			100.0 * text_area / area, biggest, 100.0 * sqrt(biggest) / maxf(1.0, panel.size.y)])


func _collect_text(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl := c as Control
			var is_text := ctl is Label or ctl is Button
			# a styled PANEL paints a background - it is not information; only real text counts
			if is_text and _has_text(ctl):
				out.append(ctl)
		_collect_text(c, out)


func _has_text(c: Control) -> bool:
	if c is Label:
		return (c as Label).text.strip_edges() != ""
	if c is Button:
		return (c as Button).text.strip_edges() != ""
	return false


func _find_stage(n: Node) -> Control:
	for c in n.get_children():
		if str(c.name) == "stage" and c is Control:
			return c as Control
		var d := _find_stage(c)
		if d != null:
			return d
	return null


## Per board cell: how many text labels it carries. 0 = empty cell (the owner's complaint);
## 2+ on the SAME role = duplicated (also his complaint).
func _cells(gv: Node) -> void:
	# the board lives under the camera now (ZOOM-01), so search the tree instead of the direct
	# children - a name that moved is still the same board, and a probe that misses it would report
	# "cells=0" as if the board had no cells.
	var board: Control = null
	for c in gv.get_children():
		if str(c.name) == "stage":
			board = c
	if board == null:
		board = _find_stage(gv)
	if board == null:
		print("LAYOUT DENSITY board NOT FOUND")
		return
	var empty := 0
	var counts: Array = []
	for tv in board.get_children():
		if tv.get("index") == null or not tv.has_method("apply"):
			continue
		var n := 0
		var roles: Array = []
		for c in (tv as Control).get_children():
			if c is Label and (c as Label).visible and (c as Label).text.strip_edges() != "":
				n += 1
				roles.append(str((c as Label).name))
		counts.append(n)
		if n == 0:
			empty += 1
	counts.sort()
	var median: int = int(counts[counts.size() / 2]) if not counts.is_empty() else -1
	var maxn: int = int(counts[-1]) if not counts.is_empty() else -1
	var minn: int = int(counts[0]) if not counts.is_empty() else -1
	print("LAYOUT DENSITY board cells=%d labels_per_cell min=%d median=%d max=%d cells_with_no_text=%d"
		% [counts.size(), minn, median, maxn, empty])
