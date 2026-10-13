extends Node
## One-shot live-UI dump for the console/dice forensics: boots the launcher, autostarts,
## waits for the local seat's awaiting state, selects tile 3, then prints the real text,
## colour and rects of the console prompt / ticker / status and the board-centre dice.
## Run: godot --path game res://tools/ui_state_dump.tscn

const MainScript := preload("res://main.gd")

var _n := 0
var _launcher = null

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)

func _process(_dt: float) -> void:
	_n += 1
	if _n == 20:
		_launcher.call("_autostart")
	if _n == 80:
		var gv = _launcher.get("_game_view")
		if gv != null:
			gv.call("_on_tile_clicked", 3)
	if _n == 120:
		var gv = _launcher.get("_game_view")
		var ap = gv.get("_actions")
		for key in ["_hint", "_ticker", "_status"]:
			var l = ap.get(key)
			if l == null:
				print("UI %s: MISSING" % key)
				continue
			var col: Color = l.get_theme_color("font_color")
			print("UI %s: visible=%s text=%s col=%s rect=%s" % [
				key, str(l.visible), str(l.text), str(col), str(l.get_global_rect())])
		var bc = gv.get("_game_view")
		var bs = gv.get("_board_scene")
		if bs != null:
			var center = bs.get("_center")
			if center != null:
				var dice = center.get("_dice")
				if dice != null:
					print("DICE hbox rect=%s" % str(dice.get_global_rect()))
					for d in dice.get_children():
						print("  die rect=%s value=%s visible=%s" % [str(d.get_global_rect()), str(d.get_meta("value", -1)), str(d.visible)])
		get_tree().quit(0)
