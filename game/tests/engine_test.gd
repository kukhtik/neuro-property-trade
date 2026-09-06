extends RefCounted
## Tests for the authoritative Engine (core/engine.gd). Scaffold-level.

static func test_list() -> Array[String]:
	return ["test_setup_creates_players", "test_setup_money_and_position", "test_submit_intent_wrong_player_rejected", "test_submit_intent_invalid_action_rejected"]

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
