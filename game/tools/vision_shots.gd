extends Node
## Vision-model screenshot capture: boots the real launcher (main.tscn), drives
## a game, and saves PNGs of several distinct UI states for a vision model to
## review. Run windowed: godot --path game res://tools/vision_shots.tscn
## Saves: vision_01_overlay.png, vision_02_board.png, vision_03_owned.png,
##        vision_04_en.png, vision_05_compact.png
## Exit 0 on success.

const MainScript := preload("res://main.gd")
const ProjectionScript := preload("res://sdk/projection.gd")
const I18n := preload("res://i18n/i18n.gd")

var _launcher
var _gv

func _ready() -> void:
	_launcher = MainScript.new()
	add_child(_launcher)
	for _i in 20:
		await get_tree().process_frame

	# 1) settings overlay (pre-game)
	await _shot("vision_01_overlay")

	# 2) start the game
	var overlay = _launcher.get("_overlay")
	overlay.call("_start_pressed")
	for _i in 15:
		await get_tree().process_frame
	_gv = _launcher.get("_game_view")
	if _gv == null or _gv.engine == null:
		print("FAIL: game did not start"); quit(1); return
	var eng = _gv.engine
	var hp: int = _gv._human_pid

	# 3) drive a few turns so the board has tokens + journal content
	for _t in 6:
		var holder := _decision_holder(eng)
		if holder < 0:
			break
		var act := _pick(eng, holder)
		_gv.manager.push_intent(holder, act.action, act.params)
		for _i in 6:
			await get_tree().process_frame
	await _shot("vision_02_board")

	# 4) give player 0 a property + houses so ownership renders
	if eng.players.size() > 0:
		eng.players[0].add_ownership(1)
		eng._houses[1] = 2
		_gv._board_scene._paint(false)
		for _i in 6:
			await get_tree().process_frame
	await _shot("vision_03_owned")

	# 5) switch to EN locale (live relabel, no rebuild)
	I18n.set_locale("en")
	for _i in 6:
		await get_tree().process_frame
	await _shot("vision_04_en")

	# 6) compact window (small board) — drive layout directly (llvmpipe ignores
	#    multi window resizes)
	_gv.size = Vector2(900, 600)
	_gv.position = Vector2.ZERO
	_gv.call("_layout")
	for _i in 10:
		await get_tree().process_frame
	await _shot("vision_05_compact")

	print("VISION SHOTS DONE")
	quit(0)

func _decision_holder(eng) -> int:
	for i in eng.players.size():
		if eng.legal_actions(i).size() > 0:
			return i
	return -1

func _pick(eng, holder: int) -> Dictionary:
	var legal: Array = eng.legal_actions(holder)
	if legal.has("roll"):
		return {"action": "roll", "params": {}}
	if legal.has("pass"):
		return {"action": "pass", "params": {}}
	if legal.has("pay"):
		return {"action": "pay", "params": {}}
	if legal.has("use_card"):
		return {"action": "use_card", "params": {}}
	return {"action": str(legal[0]), "params": {}}

func _shot(name: String) -> void:
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
