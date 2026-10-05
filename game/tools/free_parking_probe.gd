extends SceneTree
## End-to-end scenario probe for the Free Parking house rule (settings.free_parking).
## Drives the real engine through a multi-turn sequence and prints the money
## trail, so the mechanic is verified by behaviour rather than by unit asserts.

func _init() -> void:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")

	print("=== Free Parking scenario: rule ON ===")
	var s = S.new()
	s.free_parking = true
	s.rng_seed = 4242
	var e = E.new()
	e.setup(s, ["Ada", "Bo", "Cy"])

	print("start: pot=%d  money=%s" % [e.parking_pot(), _money(e)])

	# 1) Ada lands on Tax (tile 4, amount 200) -> pot should hold 200
	e._teleport(0, 3)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	print("after Ada pays Tax 200 : pot=%d  money=%s" % [e.parking_pot(), _money(e)])

	# 2) Bo lands on Luxury Tax (tile 38, amount 100) -> pot 300
	e.turn_player = 1
	e.phase = e.PHASE_TURN_START
	e._teleport(1, 37)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(1, "roll", {})
	print("after Bo pays Luxury 100: pot=%d  money=%s" % [e.parking_pot(), _money(e)])

	# 3) Cy lands on Free Parking (tile 20) -> collects the whole 300
	e.turn_player = 2
	e.phase = e.PHASE_TURN_START
	e._teleport(2, 19)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(2, "roll", {})
	print("after Cy hits FreePark  : pot=%d  money=%s" % [e.parking_pot(), _money(e)])

	# 4) Cy lands on Free Parking again with an EMPTY pot -> nothing happens
	e.turn_player = 2
	e.phase = e.PHASE_TURN_START
	e._teleport(2, 19)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(2, "roll", {})
	print("after empty-pot landing : pot=%d  money=%s" % [e.parking_pot(), _money(e)])

	var ok := true
	if e.parking_pot() != 0:
		ok = false
		print("  FAIL: pot not empty at the end (%d)" % e.parking_pot())
	if e.player(2).money != 1500 + 300:
		ok = false
		print("  FAIL: Cy should hold 1800, got %d" % e.player(2).money)
	if e.player(0).money != 1300:
		ok = false
		print("  FAIL: Ada should hold 1300, got %d" % e.player(0).money)
	if e.player(1).money != 1400:
		ok = false
		print("  FAIL: Bo should hold 1400, got %d" % e.player(1).money)

	print("=== Free Parking scenario: rule OFF (default) ===")
	var s2 = S.new()
	var e2 = E.new()
	e2.setup(s2, ["Ada", "Bo"])
	e2._teleport(0, 3)
	e2._force_dice(1, 1, 0, false)
	e2.submit_intent(0, "roll", {})
	e2.turn_player = 1
	e2.phase = e2.PHASE_TURN_START
	e2._teleport(1, 19)
	e2._force_dice(1, 1, 0, false)
	e2.submit_intent(1, "roll", {})
	print("rule off: pot=%d  money=%s" % [e2.parking_pot(), _money(e2)])
	if e2.parking_pot() != 0:
		ok = false
		print("  FAIL: rule off accumulated %d" % e2.parking_pot())
	if e2.player(1).money != 1500:
		ok = false
		print("  FAIL: rule off paid out, Bo=%d" % e2.player(1).money)

	print("---")
	print("SCENARIO %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)

func _money(e) -> String:
	var out: Array = []
	for i in e.player_count():
		out.append("%s=%d" % [e.player(i).name, e.player(i).money])
	return " ".join(out)
