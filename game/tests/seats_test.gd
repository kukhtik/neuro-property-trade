extends RefCounted
## Seat-layer tests (Phase 3): SeatConfig, seat defaults, driver resolution.

static func test_list() -> Array[String]:
	return [
		"test_defaults_three_seats",
		"test_assignment_parsing",
		"test_resolve_driver_sdk_second_falls_back_to_ai",
		"test_starting_order_manual_keeps_order",
		"test_auto_pass_phases",
		"test_jail_timeout_priority",
	]

static func _make_settings():
	var S = load("res://core/game_settings.gd")
	return S.new()

static func test_defaults_three_seats() -> String:
	var settings = _make_settings()
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(settings)
	if seats.size() != 4:
		return "want 4 default seats, got %d" % seats.size()
	if seats[0].input_driver != "LOCAL":
		return "seat 0 should be LOCAL"
	if seats[1].input_driver != "AI":
		return "seat 1 should be AI"
	for s in seats:
		if s.pid < 0 or s.pid >= seats.size():
			return "bad pid"
	return ""

static func test_assignment_parsing() -> String:
	var settings = _make_settings()
	settings.seat_assignments = [
		{"driver": "LOCAL", "name": "Vedal", "token_color": "red", "token_id": "t0"},
		{"driver": "sdk:neuro", "name": "Neuro", "token_id": "t1"},
		{"driver": "AI", "name": "Ada", "token_id": "t2"},
		{"driver": "CHAT", "name": "Chat", "token_id": "t3"},
	]
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(settings)
	if seats[0].driver_label != "LOCAL":
		return "label LOCAL"
	if seats[0].name != "Vedal":
		return "name Vedal"
	if seats[0].color != Color(1, 0.3, 0.3):
		return "color red"
	if seats[1].driver_label != "sdk:neuro":
		return "label sdk:neuro"
	if seats[1].input_driver != "SDK":
		return "driver SDK"
	if seats[1].color != Color(0.35, 0.6, 1):
		return "sdk seat should get default blue color, got %s" % str(seats[1].color)
	if seats[2].input_driver != "AI":
		return "driver AI"
	if seats[3].input_driver != "CHAT":
		return "driver CHAT"
	return ""

static func test_resolve_driver_sdk_second_falls_back_to_ai() -> String:
	var SeatConfig = load("res://seats/seat_config.gd")
	var labels: Array[String] = ["LOCAL", "sdk:neuro", "sdk:evil", "AI"]
	var seen_sdk := false
	for label in labels:
		var d: String = SeatConfig.resolve_driver(label, seen_sdk)
		if label == "LOCAL" and d != "LOCAL":
			return "LOCAL maps LOCAL"
		if label == "sdk:neuro" and d != "SDK":
			return "first sdk maps SDK"
		if label == "sdk:evil" and d != "AI":
			return "second sdk maps AI"
		if d == "SDK":
			seen_sdk = true
	return ""

static func test_starting_order_manual_keeps_order() -> String:
	var settings = _make_settings()
	settings.starting_order = "manual"
	var SeatConfig = load("res://seats/seat_config.gd")
	var seats: Array = SeatConfig.from_settings(settings)
	if seats[0].name != "Host":
		return "manual order, seat0 should be Host, got %s" % seats[0].name
	if seats[2].name != "AI Seat #3":
		return "manual order kept, seat2 name unexpected: %s" % seats[2].name
	return ""

# --- MinimalAction (timeout auto-pass) ---

static func _engine(settings=null):
	var S = load("res://core/game_settings.gd")
	var s = settings if settings != null else S.new()
	var E = load("res://core/engine.gd")
	var e = E.new()
	e.setup(s, ["A", "B"])
	return e

static func test_auto_pass_phases() -> String:
	var MA = load("res://seats/minimal_action.gd")
	var e = _engine()
	# TURN_START player 0 (not in jail) -> roll
	var p = MA.pick(e, 0)
	if p.get("action", "") != "roll":
		return "turn start -> roll, got %s" % p.get("action", "")
	# Force a purchase: land player 0 on tile 6 (unowned Cedar Ave), auctions off
	e.settings.auctions_on_refusal = false
	e._force_dice(6, 3, 3, false)
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT":
		return "expected PURCHASE_WAIT, got %s" % e.phase
	var p2 = MA.pick(e, 0)
	if p2.get("action", "") != "pass":
		return "purchase -> pass, got %s" % p2.get("action", "")
	return ""

static func test_jail_timeout_priority() -> String:
	var MA = load("res://seats/minimal_action.gd")
	var S = load("res://core/game_settings.gd")
	var settings = S.new()
	settings.jail_fine = 50
	var e = _engine(settings)
	# Jail player 0 with 0 attempts left -> engine legal omits "roll",
	# has money -> pay.
	e._send_to_jail()
	e.player(0).jail_turns = 3
	var p = MA.pick(e, 0)
	if p.get("action", "") != "pay":
		return "jailed, 3 attempts, has money -> pay, got %s" % p.get("action", "")
	# No money, no card -> nothing available (pick returns {})
	e.player(0).money = 0
	var p2 = MA.pick(e, 0)
	if not p2.is_empty():
		return "jailed, broke, no card -> {} expected, got %s" % str(p2)
	return ""
