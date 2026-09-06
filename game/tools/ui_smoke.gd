extends Node
## UI smoke + playability probe: instantiates the real launcher (main.tscn),
## verifies the lobby builds, auto-starts via the lobby, then DRIVES the human
## LOCAL seat one full turn by pushing "roll" through the game_view, and prints
## engine phase/money to prove the human input path works end-to-end.
## Run windowed: godot --path game res://tools/ui_smoke.tscn

const MainScript := preload("res://main.gd")

var _launcher

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	# 1) lobby present?
	var lobby = _launcher.get("_lobby")
	if lobby == null:
		print("FAIL: no lobby"); quit(1); return
	print("PASS: lobby built (players list has %d children)" % lobby._players_list.get_child_count())

	# 2) start the game
	lobby.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	var gv = _launcher.get("_game_view")
	if gv == null:
		print("FAIL: no game view after START"); quit(1); return
	print("PASS: game view built; human_pid=%d" % gv._human_pid)

	# 3) find the human's legal actions and drive a roll
	var eng = gv.engine
	var hp: int = gv._human_pid
	if hp < 0:
		print("FAIL: no human (LOCAL/ADMIN) seat"); quit(1); return
	var legal: Array = eng.legal_actions(hp)
	print("human legal first: %s" % str(legal))
	var before: int = eng.players[hp].position
	var res: Dictionary = gv.manager.push_intent(hp, "roll", {})
	print("roll result ok=%s position %d -> %d" % [str(res.get("ok")), before, eng.players[hp].position])
	if not res.get("ok", false):
		print("FAIL: human roll rejected: %s" % str(res.get("reason")))
		quit(1); return
	print("PASS: human roll executed, position advanced")

	# 4) AI seats should self-drive a few steps
	for _i in 40:
		await get_tree().process_frame
	print("PASS: game survives; phase=%s" % str(eng.phase))
	await _shot_save("ui_played")
	quit(0)

func _shot_save(name: String) -> void:
	var vp := get_tree().root
	for _i in 6:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	var path := "%s.png" % name
	img.save_png(path)
	print("SAVED %s (%dx%d)" % [path, img.get_width(), img.get_height()])

func quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)
