extends Node
## Why does READ-02 call the panno's players zone 32 % empty? It measures the largest vertical gap
## without content inside whatever stands in for the seats dock. This prints the real rects.
## Run: godot --headless --path game res://tools/panno_zone_probe.tscn  (or --script)

const MainScript := preload("res://main.gd")

var _launcher = null
var _frame := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_launcher.call("_autostart")
		return
	if _frame < 60:
		return
	var gv = _launcher.get("_game_view")
	var zone = gv.find_child("zone-players", true, false)
	if zone == null:
		print("ZONE probe: zone-players not found")
		get_tree().quit(1)
		return
	var z: Control = zone
	print("ZONE rect=", z.get_global_rect(), " visible=", z.is_visible_in_tree())
	_dump(z, 0)
	get_tree().quit(0)


func _dump(n: Node, depth: int) -> void:
	for ch in n.get_children():
		if ch is Control:
			var c := ch as Control
			var txt := ""
			if c is Label:
				txt = " text='%s'" % (c as Label).text.left(18)
			elif c is Button:
				txt = " text='%s'" % (c as Button).text.left(18)
			print("ZONE %s%s rect=%s vis=%s%s" % ["  ".repeat(depth), str(c.name),
				str(c.get_global_rect()), str(c.is_visible_in_tree()), txt])
			if depth < 2:
				_dump(c, depth + 1)
