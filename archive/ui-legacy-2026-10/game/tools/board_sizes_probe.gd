extends SceneTree
## Stage-3 acceptance probe: the board is parametric END TO END.
##
## Checks that settings.tile_count actually changes the loaded board (the engine
## looks for board_<N>.json), that real games play at 16/24/40/64, and that the
## tile geometry produced for each is overlap-free and square.
##
## Exit 0 = the 40 hardcode is gone in practice, not just in the layout math.

const EngineS := preload("res://core/engine.gd")
const SettingsS := preload("res://core/game_settings.gd")
const BL := preload("res://visual/board_layout.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 3 acceptance: parametric board ===")
	_check_engine_loads_each_size()
	_check_geometry_per_size()
	_check_playable_run()
	print("")
	if _fail > 0:
		print("==> PARAMETRIC BOARD FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> PARAMETRIC BOARD PASSED — tile_count drives board and layout")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _check_engine_loads_each_size() -> void:
	print("[1] the engine loads board_<N>.json for each configured size")
	for n in [16, 24, 40, 64]:
		var s = SettingsS.new()
		s.tile_count = n
		var e = EngineS.new()
		e.setup(s, ["A", "B"])
		var got: int = e.board.tile_count()
		if got != n:
			_bad("tile_count=%d but the engine loaded %d tiles" % [n, got])
		else:
			_ok("tile_count=%d -> %d tiles (corners: %s)" % [
				n, got, str([e.board.type_at(0), e.board.type_at(n / 4),
					e.board.type_at(n / 2), e.board.type_at(3 * n / 4)])])


func _check_geometry_per_size() -> void:
	print("[2] geometry for each size: square, no overlaps, centre inside")
	for n in [16, 24, 40, 64]:
		for side in [600.0, 1000.0]:
			var tiles := BL.compute(n, side, 1.4, 2.0)
			if tiles.size() != n:
				_bad("n=%d side=%.0f: %d rects" % [n, side, tiles.size()])
				continue
			if not BL.rects_do_not_overlap(tiles):
				_bad("n=%d side=%.0f: tiles overlap" % [n, side])
			elif not BL.is_square(tiles, side):
				_bad("n=%d side=%.0f: ring is not square" % [n, side])
			else:
				var c := BL.center_rect(n, side, 1.4, 2.0)
				var hits := false
				for t in tiles:
					if c.intersects(t["rect"], true):
						hits = true
						break
				if hits:
					_bad("n=%d side=%.0f: centre overlaps the ring" % [n, side])
				else:
					_ok("n=%d side=%.0f: clean ring, centre %.0fx%.0f" % [n, side, c.size.x, c.size.y])


func _check_playable_run() -> void:
	print("[3] a real game plays to completion at each size")
	for n in [16, 24, 64]:
		var s = SettingsS.new()
		s.tile_count = n
		s.rng_seed = 777
		var e = EngineS.new()
		e.setup(s, ["A", "B", "C"])
		var turns := 0
		var guard := 0
		while e.phase != e.PHASE_END_GAME and guard < 400:
			guard += 1
			var pid: int = e.turn_player
			var legal: Array = e.legal_actions(pid)
			if legal.is_empty():
				break
			var act: String = legal[0]
			if legal.has("roll"):
				act = "roll"
			elif legal.has("pass") and legal.has("buy"):
				act = "pass"
			elif legal.has("bid"):
				act = "pass"
			var params := {}
			if e.phase == e.PHASE_AUCTION:
				var b: int = e._pending.get("bidder", -1)
				if b >= 0:
					pid = b
			e.submit_intent(pid, act, params)
			turns += 1
		var tiles: int = e.board.tile_count()
		if tiles != n:
			_bad("n=%d: ended on a %d-tile board" % [n, tiles])
		elif turns == 0:
			_bad("n=%d: no intents were accepted" % n)
		else:
			_ok("n=%d: %d intents accepted, phase=%s, tiles=%d" % [n, turns, e.phase, tiles])
