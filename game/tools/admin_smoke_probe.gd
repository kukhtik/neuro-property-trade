extends Node
## Behavioral probe: does the ADMIN panel (F12 surface) still build and paint
## after the v3 swap? Boots the host, autostarts, shows the panel, dumps its anatomy.
## Audit seed for gate HG-12 (docs/restoration/gates.md) — diagnostic today, gate next.
const MainScript := preload("res://main.gd")
var _launcher = null
var _n := 0
var _reported := false

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 10:
		_launcher.call("_autostart")
	if _n == 90 and not _reported:
		_reported = true
		_report()
		get_tree().quit(0)

func _report() -> void:
	var panel = _launcher.get("_panel")
	if panel == null:
		print("ADMIN PROBE: no panel object (is_host=false?)")
		return
	panel.visible = true
	panel.move_to_front()
	var labels: Array = []
	var buttons: Array = []
	var tabs := 0
	var stack: Array = [panel]
	while stack.size() > 0:
		var nd = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
			if c is Label and str((c as Label).text).strip_edges() != "":
				labels.append(str((c as Label).text))
			if c is Button and str((c as Button).text).strip_edges() != "":
				buttons.append(str((c as Button).text))
	print("ADMIN PROBE: panel built, labels=%d buttons=%d" % [labels.size(), buttons.size()])
	print("  first labels: %s" % str(labels.slice(0, 12)))
	print("  first buttons: %s" % str(buttons.slice(0, 10)))
	var gate = _launcher.get("_gate")
	if gate != null:
		print("  token needed? %s" % str(gate.get("require_token") if gate.get("require_token") != null else "?"))
