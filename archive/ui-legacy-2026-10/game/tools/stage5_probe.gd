extends SceneTree
## Stage-5 acceptance probe: the presentation queue drives the real board.
##
## The suite tests EventPresenter in isolation. This checks it is WIRED and
## behaves under a real engine, which is the failure mode stage 3 taught us
## (a component can pass its own tests while the game never calls it):
##   1. board_scene owns a presenter, an adapter and a store;
##   2. a real engine turn pushes events through the queue;
##   3. after the queue drains, the store equals the projection;
##   4. animations=off applies instantly;
##   5. skip_all drains and reconciles.
##
## Exit 0 = stage 5 is integrated.

const BoardScene := preload("res://visual/board_scene.gd")
const EngineS := preload("res://core/engine.gd")
const SettingsS := preload("res://core/game_settings.gd")
const SeatConfig := preload("res://seats/seat_config.gd")
const Proj := preload("res://sdk/projection.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 5 acceptance: presentation queue in the live game ===")
	await process_frame
	_check_wired()
	await _check_real_turn()
	_check_animations_off()
	_check_skip()
	print("")
	if _fail > 0:
		print("==> STAGE 5 FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 5 PASSED — events queue, drain to the projection, and skip")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _make() -> Dictionary:
	var s = SettingsS.new()
	s.rng_seed = 4242
	s.seat_count = 3
	s.seat_assignments = [
		{"driver": "AI", "name": "Ada"},
		{"driver": "AI", "name": "Bo"},
		{"driver": "AI", "name": "Cy"},
	]
	var e = EngineS.new()
	e.setup(s, ["Ada", "Bo", "Cy"])
	# real Seat objects: board_view resolves token_id/color off seat PROPERTIES,
	# so a plain Dictionary would blow up in the token panel
	var seats: Array = SeatConfig.from_settings(s)
	var scene = BoardScene.new()
	root.add_child(scene)
	scene.setup(e, s, seats)
	await process_frame
	return {"scene": scene, "engine": e, "settings": s}


func _check_wired() -> void:
	print("[1] board_scene owns the presenter, adapter and store")
	var r = await _make()
	var scene = r["scene"]
	if scene.get("_presenter") == null:
		_bad("board_scene has no EventPresenter")
	elif scene.get("_adapter") == null:
		_bad("board_scene has no EventAdapter")
	elif scene.get("_store") == null:
		_bad("board_scene has no UiStore")
	else:
		_ok("presenter + adapter + store are wired")
	scene.queue_free()
	await process_frame


func _check_real_turn() -> void:
	print("[2] a real engine turn flows through the queue to the projection")
	var r = await _make()
	var scene = r["scene"]
	var e = r["engine"]
	# let the initial setup paint settle, then take a real turn
	await process_frame
	var before: int = e.log.size()
	e._force_dice(4, 3, 4, false)
	e.submit_intent(e.turn_player, "roll", {})
	# flush the deferred run and let the scene settle
	for i in 5:
		await process_frame
	var pushed: int = int(scene._presenter.stats()["played"])
	if pushed <= 0:
		_bad("no events reached the presenter from a real turn")
	else:
		_ok("the turn pushed %d events through the queue" % pushed)
	# resolve any purchase decision so the engine is quiescent
	if e.phase == e.PHASE_PURCHASE_WAIT:
		e.submit_intent(e.turn_player, "pass", {})
		for i in 5:
			await process_frame
	# THE check: after draining, the store must equal the projection
	var proj: Dictionary = Proj.new().for_spectator(e)
	var mismatch := 0
	for pl in proj.get("players", []):
		var pid: int = int(pl["index"])
		var mine: int = int(scene._store.player(pid).get("money", -1))
		if mine != int(pl["money"]):
			_bad("player %d money: store=%d projection=%d" % [pid, mine, int(pl["money"])])
			mismatch += 1
	if mismatch == 0:
		_ok("after drain the store matches the projection")
	if scene._presenter.is_busy():
		_bad("the presenter should be idle after settling")
	scene.queue_free()
	await process_frame


func _check_animations_off() -> void:
	print("[3] animations=off applies instantly")
	var r = await _make()
	var scene = r["scene"]
	var e = r["engine"]
	scene.set_animations(false)
	await process_frame
	e._force_dice(2, 3, 2, false)
	e.submit_intent(e.turn_player, "roll", {})
	for i in 4:
		await process_frame
	if scene._presenter.animations:
		_bad("set_animations(false) did not reach the presenter")
	else:
		_ok("the animations toggle reaches the presenter")
	# the view must still converge with animations off
	var proj: Dictionary = Proj.new().for_spectator(e)
	var p0_store: int = int(scene._store.player(0).get("money", -1))
	var p0_proj: int = int(proj["players"][0]["money"])
	if p0_store != p0_proj:
		_bad("with animations off the store diverged: %d vs %d" % [p0_store, p0_proj])
	else:
		_ok("the view converges with animations off")
	scene.queue_free()
	await process_frame


func _check_skip() -> void:
	print("[4] skip_all drains the queue")
	var r = await _make()
	var scene = r["scene"]
	# push a burst, then skip before it can run
	for i in 6:
		scene._presenter.push({"k": "rent", "d": [], "p": 0, "a": 10, "ti": 1})
	scene.skip_all_animations()
	if scene._presenter.is_busy():
		_bad("skip_all left the presenter busy")
	elif scene._presenter.pending() != 0:
		_bad("skip_all left %d events pending" % scene._presenter.pending())
	else:
		_ok("skip_all emptied the queue")
	# and the store is reconciled afterwards
	for i in 3:
		await process_frame
	var proj: Dictionary = Proj.new().for_spectator(r["engine"])
	var p0_store: int = int(scene._store.player(0).get("money", -1))
	if p0_store != int(proj["players"][0]["money"]):
		_bad("after skip the store did not reconcile: %d vs %d" % [p0_store, int(proj["players"][0]["money"])])
	else:
		_ok("the store reconciled after skip")
	scene.queue_free()
	await process_frame
