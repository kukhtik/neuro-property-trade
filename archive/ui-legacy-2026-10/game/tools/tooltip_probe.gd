extends Node
## P3 Tooltip Coverage Probe — verifies that every interactive control
## (Button, TextureButton, CheckButton, etc.) has a non-empty tooltip_text.
## Run: godot --headless --path game --script res://tools/tooltip_probe.gd

const MainScript := preload("res://main.gd")

var _launcher
var _had_fail := false
var _checked := 0
var _missing := 0

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 30:
		await get_tree().process_frame
	
	# Start game to get all UI elements
	var overlay = _launcher.get("_overlay")
	if overlay:
		overlay.call("_start_pressed")
		for _i in 20:
			await get_tree().process_frame
	
	_check_tooltips(_launcher)
	
	# Also check cold state (settings overlay)
	_check_tooltips(overlay)
	
	# Check any modals that might be open
	var gv = _launcher.get("_game_view")
	if gv and gv._modals:
		_check_tooltips(gv._modals)
	
	if _had_fail:
		print("TOOLTIP PROBE: FAILED - %d controls missing tooltips out of %d checked" % [_missing, _checked])
		quit(1)
	else:
		print("TOOLTIP PROBE: PASSED - all %d interactive controls have tooltips" % _checked)
		quit(0)

func _check_tooltips(root) -> void:
	if root == null:
		return
	
	var nodes := root.get_tree().get_nodes_in_group("buttons")
	if nodes.is_empty():
		nodes = _find_interactive(root)
	
	for node in nodes:
		_checked += 1
		var tooltip := ""
		if node.has_method("get_tooltip_text"):
			tooltip = node.get_tooltip_text()
		elif node.has_property("tooltip_text"):
			tooltip = node.tooltip_text
		
		if tooltip == "" or tooltip == null:
			_missing += 1
			var path := node.get_path()
			print("MISSING TOOLTIP: %s (%s)" % [path, node.get_class()])
			_had_fail = true

func _find_interactive(root) -> Array:
	var result := []
	var to_process := [root]
	while to_process.size() > 0:
		var n := to_process.pop_back()
		if n is Button or n is TextureButton or n is CheckButton or n is OptionButton or n is MenuButton:
			result.append(n)
		for c in n.get_children():
			to_process.append(c)
	return result

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)