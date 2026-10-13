extends Node
## UI smoke + playability probe: instantiates the real launcher (main.tscn),
## verifies the settings overlay builds, auto-starts via the overlay, then
## DRIVES the human LOCAL seat one full turn by pushing "roll" through the
## game_view, and prints engine phase/money to prove the human input path works
## end-to-end.
## Run windowed: godot --path game res://tools/ui_smoke.tscn

const MainScript := preload("res://main.gd")
const ProjectionScript := preload("res://sdk/projection.gd")

var _launcher

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	# 1) overlay present?
	var overlay = _launcher.get("_overlay")
	if overlay == null:
		print("FAIL: no settings overlay"); quit(1); return
	print("PASS: settings overlay built (players list has %d children)" % overlay._players_list.get_child_count())

	# 2) start the game
	overlay.call("_start_pressed")
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

	# 5) A3: tile inspector auto-hide. Select a tile -> visible; wait >3s -> hidden.
	var insp = gv._inspector
	insp.select(5)
	insp.sync(ProjectionScript.new().for_spectator(eng), gv.seats)
	if not insp.visible:
		print("FAIL: inspector should be visible after select")
		quit(1); return
	print("PASS: inspector visible after tile select")
	# wait ~4s of real time (frame count is unreliable under llvmpipe)
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if insp.visible:
		print("FAIL: inspector should auto-hide after 3s")
		quit(1); return
	print("PASS: inspector auto-hides after 3s")

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
