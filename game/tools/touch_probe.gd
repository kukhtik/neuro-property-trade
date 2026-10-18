extends Node
## "Кнопки боковых панелей супер маленькие" - measured, not guessed. Boots the shell, starts a
## match and prints every CLICKABLE control in the side panels (docks + rails + drawers) with its
## real rectangle, flagging targets below the 28px comfort floor (44 is the touch rule, 28 is the
## mouse floor this UI uses for a labelled control).
## Run: godot --headless --path game res://tools/touch_probe.tscn

const MainScript := preload("res://main.gd")

const FLOOR := 28.0

var _launcher = null
var _frame := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1200))
	get_tree().root.size = Vector2i(1600, 1200)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_launcher.call("_autostart")
		return
	if _frame == 60:
		_timer_check(_launcher.get("_game_view"))
		return
	if _frame == 64:
		_timer_first = _timer_label.size.x
		_timer_label.text = "10:00"
		return
	if _frame == 68:
		var second := _timer_label.size.x
		print("TIMER box %.1fpx at '9:59' vs %.1fpx at '10:00' -> %s" % [_timer_first, second,
			"STABLE" if absf(second - _timer_first) < 0.5 else "JUMPS"])
		return
	if _frame != 72:
		return
	var gv = _launcher.get("_game_view")
	print("TOUCH profile root=", get_tree().root.size)
	for root_name in ["seats", "rightcol", "rail-right", "drawer-seats", "drawer-journal",
			"drawer-inspector", "top"]:
		var node = gv.find_child(root_name, true, false)
		if node == null:
			print("TOUCH %s: absent" % root_name)
			continue
		var c := node as Control
		print("TOUCH %s visible=%s rect=%s" % [root_name, str(c.is_visible_in_tree()),
			str(c.get_global_rect())])
		_walk(c, root_name)
	get_tree().quit(0)


## Two texts, one box: the clock must not resize between "9:59" and "10:00". A one-frame gap lets
## the container lay out between the two reads.
var _timer_when := 0
var _timer_first := 0.0
var _timer_label: Label


func _timer_check(gv) -> void:
	_timer_label = gv.find_child("top-decision", true, false) as Label
	if _timer_label == null:
		print("TOUCH timer: top-decision not found")
		get_tree().quit(1)
		return
	_timer_label.visible = true
	_timer_label.text = "9:59"
	_timer_when = 1


func _walk(n: Node, group: String) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			var clickable := c is BaseButton or (c is RailPanel) \
				or (c.mouse_filter == Control.MOUSE_FILTER_STOP and c.gui_input.get_connections().size() > 0)
			if clickable and c.is_visible_in_tree():
				var sz := c.get_global_rect().size
				var text := ""
				if c is Button:
					text = (c as Button).text
				elif c is Label:
					text = (c as Label).text
				var small := sz.x < FLOOR or sz.y < FLOOR
				print("TOUCH   %s%s %s %s text='%s'%s" % ["SMALL " if small else "",
					group, str(c.name), str(sz), text.left(18),
					" tooltip='%s'" % c.tooltip_text.left(24) if c.tooltip_text != "" else ""])
			_walk(c, group)
