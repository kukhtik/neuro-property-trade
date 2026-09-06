extends RefCounted
## Phase 4 admin_controller tests: pure policy layer — override forwarding,
## seat reset, dump_state diagnostics, list_events.

static func test_list() -> Array[String]:
	return [
		"test_override_forwards_set_balance",
		"test_reset_seat_away",
		"test_reset_seat_away_no_seat_fails",
		"test_dump_state_shape",
		"test_list_events_unfiltered",
		"test_list_events_filtered",
	]

static func _make():
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var e = E.new()
	e.setup(S.new(), ["Ada", "Bo"])
	return e

static func _make_seats():
	var Seat = load("res://seats/seat.gd")
	return [Seat.new(0), Seat.new(1)]

static func test_override_forwards_set_balance() -> String:
	var e = _make()
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, _make_seats())
	var res = c.override("set_balance", {"pid": 0, "amount": 600})
	if not res.get("ok", false): return "expected ok"
	if e.player(0).money != 600: return "want 600 got %d" % e.player(0).money
	return ""

static func test_reset_seat_away() -> String:
	var e = _make()
	var seats = _make_seats()
	seats[0].away = true
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, seats)
	var res = c.reset_seat_away(0)
	if not res.get("ok", false): return "expected ok"
	if seats[0].away: return "seat 0 should be un-away"
	return ""

static func test_reset_seat_away_no_seat_fails() -> String:
	var e = _make()
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, _make_seats())
	var res = c.reset_seat_away(7)
	if res.get("ok", false): return "should fail for unknown seat"
	return ""

static func test_dump_state_shape() -> String:
	var e = _make()
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, [])
	var dump = c.dump_state()
	if not dump.has("phase") or not dump.has("turn_player"): return "dump missing top keys"
	if (dump.get("players", []) as Array).size() != 2: return "dump should list 2 players"
	var first = (dump["players"] as Array)[0]
	for k in ["pid", "name", "money", "position", "in_jail", "bankrupt", "tiles", "away"]:
		if not first.has(k): return "player entry missing key %s" % k
	return ""

static func test_list_events_unfiltered() -> String:
	var e = _make()
	e.admin_override("teleport", {"pid": 1, "tile": 5})
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, [])
	var ev = c.list_events("")
	if (ev as Array).size() < 2: return "should list setup + admin_override events"
	return ""

static func test_list_events_filtered() -> String:
	var e = _make()
	e.admin_override("teleport", {"pid": 1, "tile": 5})
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, [])
	var ev = c.list_events("admin_override")
	if (ev as Array).size() != 1: return "filter should return 1 admin_override"
	return ""
