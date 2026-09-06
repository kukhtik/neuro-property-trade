extends RefCounted
## Tests for the authoritative Engine (core/engine.gd). Scaffold-level.

static func test_list() -> Array[String]:
	return ["test_setup_creates_players", "test_setup_money_and_position", "test_submit_intent_wrong_player_rejected", "test_submit_intent_invalid_action_rejected", "test_move_advances_position", "test_move_no_go_bonus_without_wrap", "test_go_bonus_on_wrap", "test_doubles_grants_extra_turn_same_player", "test_non_doubles_advances_next_player", "test_triple_doubles_sends_to_jail", "test_purchase_buy", "test_purchase_insufficient_funds", "test_purchase_pass_leaves_unowned", "test_base_rent_on_property"]

static func _make_engine(player_names: Array = ["Ada", "Bo"]) -> Dictionary:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, player_names)
	return {"engine": e}

static func test_setup_creates_players() -> String:
	var r = _make_engine()
	if r["engine"].player_count() != 2:
		return "want 2 players, got %d" % r["engine"].player_count()
	return ""

static func test_setup_money_and_position() -> String:
	var r = _make_engine()
	var p = r["engine"].player(0)
	if p.money != 1500:
		return "starting cash should be 1500, got %d" % p.money
	if p.position != 0:
		return "start position should be 0, got %d" % p.position
	return ""

static func test_submit_intent_wrong_player_rejected() -> String:
	var r = _make_engine()
	var res = r["engine"].submit_intent(1, "roll", {})
	if res["ok"] == true:
		return "should reject player 1 (not turn_player) in TURN_START"
	return ""

static func test_submit_intent_invalid_action_rejected() -> String:
	var r = _make_engine()
	# player 0 is turn_player in TURN_START; "build" is not legal there
	var res = r["engine"].submit_intent(0, "build", {})
	if res["ok"] == true:
		return "should reject 'build' in TURN_START"
	if res["ok"] == false and (res.get("legal", []) as Array).size() == 0:
		return "legal list should not be empty for a rejected but in-phase action"
	return ""

static func _assert_reject(e, pid: int) -> String:
	# after any roll that ends the turn, turn_player should be a valid other... internal helper not strictly needed
	return ""

static func test_move_advances_position() -> String:
	var r = _make_engine()
	var e = r["engine"]
	var pos_before = e.player(0).position
	e._force_dice(2, 1, 1, false)  # sum 2, non-doubles, moves to tile 2
	var res = e.submit_intent(0, "roll", {})
	if res["ok"] != true: return "roll rejected: " + res.get("reason", "")
	if e.player(0).position != 2: return "expected position 2, got %d" % e.player(0).position
	return ""

static func test_move_no_go_bonus_without_wrap() -> String:
	var r = _make_engine()
	var e = r["engine"]
	var before = e.player(0).money
	e._force_dice(5, 2, 3, false)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != before: return "money changed: %d -> %d" % [before, e.player(0).money]
	if e.player(0).position != 5: return "expected pos 5, got %d" % e.player(0).position
	return ""

static func test_go_bonus_on_wrap() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# teleport near the end then roll past 0: use player(0).position = 38, then roll sum 3 -> 1 (cross 0)
	e.player(0).position = 38
	var before = e.player(0).money
	e._force_dice(3, 1, 2, false)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != before + 200: return "GO bonus not paid: %d -> %d (expected +200)" % [before, e.player(0).money]
	if e.player(0).position != 1: return "expected pos 1, got %d" % e.player(0).position
	return ""

static func test_doubles_grants_extra_turn_same_player() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(6, 3, 3, true)   # doubles sum 6, tile 6 (Cedar Ave, lightblue unowned — no decision in Task 4)
	e.submit_intent(0, "roll", {})
	if e.player(0).owns(6): return "should NOT auto-purchase in Task 4 (that's Task 5)"
	if e.turn_player != 0: return "doubles should keep player 0, got %d" % e.turn_player
	return ""

static func test_non_doubles_advances_next_player() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(4, 1, 3, false)  # tile 4 (Tax) non-doubles
	e.submit_intent(0, "roll", {})
	if e.turn_player != 1: return "non-doubles should advance to player 1, got %d" % e.turn_player
	return ""

static func test_triple_doubles_sends_to_jail() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(4, 2, 2, true);  e.submit_intent(0, "roll", {})
	e._force_dice(6, 3, 3, true);  e.submit_intent(0, "roll", {})
	e._force_dice(2, 1, 1, true);  e.submit_intent(0, "roll", {})
	if e.player(0).in_jail != true: return "triple doubles should jail player 0"
	if e.player(0).position != 10: return "jailed to tile 10, got %d" % e.player(0).position
	return ""

static func test_purchase_buy() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)   # sum 1 → tile 1 (Sunset Blvd, brown, cost 60, unowned)
	e.submit_intent(0, "roll", {})
	if e.phase != e.PHASE_PURCHASE_WAIT: return "should await purchase, phase=" + e.phase
	var res = e.submit_intent(0, "buy", {})
	if not res["ok"]: return "buy rejected: " + res.get("reason", "")
	if not e.player(0).owns(1): return "did not gain tile 1"
	if e.player(0).money != 1500 - 60: return "buy cost not charged, money=%d" % e.player(0).money
	return ""

static func test_purchase_insufficient_funds() -> String:
	var r = _make_engine(["Ada"])
	var e = r["engine"]
	e.player(0).money = 30
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	var res = e.submit_intent(0, "buy", {})
	if res["ok"] == true: return "buy should fail with insufficient funds"
	if e.player(0).owns(1): return "must not own tile on failed buy"
	return ""

static func test_purchase_pass_leaves_unowned() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})
	if e.player(0).owns(1) or e.player(1).owns(1): return "pass should leave tile unowned"
	if e.turn_player != 1: return "after pass+non-doubles turn should advance to player 1, got %d" % e.turn_player
	return ""

static func test_base_rent_on_property() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(1)   # player 1 owns tile 1 (Sunset Blvd rent 2)
	e._force_dice(1, 1, 0, false)  # player 0 lands on tile 1
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 2: return "base rent not charged, money=%d" % e.player(0).money
	if e.player(1).money != 1500 + 2: return "rent not credited, money=%d" % e.player(1).money
	return ""
