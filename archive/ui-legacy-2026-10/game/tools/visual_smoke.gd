extends Node
## Windowed screenshot smoke: boots board_scene, drives a game, saves PNGs.
## Run:  godot --path . res://tools/visual_smoke.tscn   (windowed, displays :0)
## Expected: prints SAVED visual_smoke_N.png, exits 0.

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const MinimalAction := preload("res://seats/minimal_action.gd")
const BoardScene := preload("res://visual/board_scene.gd")

var _engine
var _shot_count := 0

const MAX_TURNS := 12
const SHOT_EVERY := 3   # capture every N turn-steps

func _ready() -> void:
	var s = Settings.new()
	s.rng_seed = 12345    # deterministic
	var seats: Array = SeatConfig.from_settings(s)
	_engine = EngineScript.new()
	var names := []
	for seat in seats: names.append(seat.name)
	_engine.setup(s, names)

	var scene = BoardScene.new()
	scene.name = "BoardScene"
	add_child(scene)
	scene.setup(_engine, s)

	_run()

func _decision_holder() -> int:
	for i in _engine.players.size():
		if _engine.legal_actions(i).size() > 0:
			return i
	return -1

func _run() -> void:
	# let the first frames draw, then play the turn loop
	for i in 4:
		await get_tree().process_frame

	var turns := 0
	while turns < MAX_TURNS:
		var holder := _decision_holder()
		if holder < 0:
			break
		var act := MinimalAction.pick(_engine, holder)
		var res = _engine.submit_intent(holder, act.action, act.params)
		turns += 1
		if turns % SHOT_EVERY == 0:
			await _shot(turns)
		else:
			# give the event-driven scene a couple frames to repaint
			await get_tree().process_frame
			await get_tree().process_frame

	if _shot_count == 0:
		await _shot(turns)
	_finish(0)

func _shot(turn: int) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "visual_smoke_%02d.png" % _shot_count
	img.save_png(path)
	print("SAVED %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	_shot_count += 1

func _finish(code: int) -> void:
	print("VISUAL SMOKE DONE: shots=%d" % _shot_count)
	get_tree().quit(code)
