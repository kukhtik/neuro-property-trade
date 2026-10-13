extends Node
## Behavioral probe: what survives the COMPACT profile (880x600..1279 wide)?
## Same boot as v3_probe but the window is 1000x650, then dump region visibility.
## Audit seed for gate SG-01 (docs/restoration/gates.md) — diagnostic today, gate next.
const MainScript := preload("res://main.gd")
var _launcher = null
var _n := 0

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1000, 650))
	get_tree().root.size = Vector2i(1000, 650)
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 10:
		_launcher.call("_autostart")
	if _n == 90:
		_report()
		get_tree().quit(0)

func _report() -> void:
	var gv = _launcher.get("_game_view")
	print("COMPACT PROBE  window=%s" % str(get_viewport().get_visible_rect().size))
	for nm in ["top", "seats", "stage", "act", "rightcol", "journal", "inspector", "toast", "modal"]:
		var nd = gv.find_child(nm, true, false)
		if nd == null:
			print("  MISSING region %s" % nm)
		else:
			print("  %-10s visible=%s size=%s" % [nm, str((nd as Control).visible), str((nd as Control).size)])
	var journal = gv.find_child("journal", true, false)
	if journal != null:
		print("  journal rows visible to a player? %s" % str((journal as Control).visible))
