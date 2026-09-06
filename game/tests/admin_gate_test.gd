extends RefCounted
## admin_gate tests: token auth layer over admin_controller. Pure, headless.

static func test_list() -> Array[String]:
	return [
		"test_unguarded_authorize_true",
		"test_guarded_authorize_correct",
		"test_guarded_authorize_wrong",
		"test_guarded_authorize_empty",
		"test_override_authorized_mutates",
		"test_override_unauthorized_fails_closed",
		"test_override_unauthorized_no_mutation",
		"test_reset_away_unauthorized",
		"test_diagnostics_not_gated",
	]

static func _make() -> Dictionary:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var e = E.new()
	e.setup(S.new(), ["Ada", "Bo"])
	var Seat = load("res://seats/seat.gd")
	var seats = [Seat.new(0), Seat.new(1)]
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, seats)
	var Gate = load("res://admin/admin_gate.gd")
	var g = Gate.new()
	g.setup(c, "s3cret")
	return {"engine": e, "controller": c, "gate": g}

static func test_unguarded_authorize_true() -> String:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var e = E.new()
	e.setup(S.new(), ["Ada", "Bo"])
	var AC = load("res://admin/admin_controller.gd")
	var c = AC.new()
	c.setup(e, [])
	var Gate = load("res://admin/admin_gate.gd")
	var g = Gate.new()
	g.setup(c, "")   # no token -> open
	if g.is_guarded(): return "empty token should be unguarded"
	if not g.authorize(""): return "unguarded should authorize anything"
	if not g.authorize("whatever"): return "unguarded should authorize any token"
	return ""

static func test_guarded_authorize_correct() -> String:
	var r = _make()
	if not r["gate"].is_guarded(): return "non-empty token should be guarded"
	if not r["gate"].authorize("s3cret"): return "correct token should authorize"
	return ""

static func test_guarded_authorize_wrong() -> String:
	var r = _make()
	if r["gate"].authorize("wrong"): return "wrong token should fail"
	return ""

static func test_guarded_authorize_empty() -> String:
	var r = _make()
	if r["gate"].authorize(""): return "empty token should fail on guarded gate"
	return ""

static func test_override_authorized_mutates() -> String:
	var r = _make()
	var res = r["gate"].override("set_balance", {"pid": 0, "amount": 700}, "s3cret")
	if not res.get("ok", false): return "authorized override should be ok: %s" % str(res)
	if r["engine"].player(0).money != 700: return "money want 700 got %d" % r["engine"].player(0).money
	return ""

static func test_override_unauthorized_fails_closed() -> String:
	var r = _make()
	var res = r["gate"].override("set_balance", {"pid": 0, "amount": 700}, "nope")
	if res.get("ok", false): return "unauthorized override should fail"
	if res.get("reason", "") != "unauthorized": return "reason should be unauthorized, got %s" % res.get("reason", "")
	return ""

static func test_override_unauthorized_no_mutation() -> String:
	var r = _make()
	r["gate"].override("set_balance", {"pid": 0, "amount": 700}, "nope")
	if r["engine"].player(0).money != 1500: return "no mutation on unauthorized override"
	return ""

static func test_reset_away_unauthorized() -> String:
	var r = _make()
	var res = r["gate"].reset_seat_away(0, "bad")
	if res.get("ok", false): return "unauthorized reset should fail"
	return ""

static func test_diagnostics_not_gated() -> String:
	var r = _make()
	var dump = r["gate"].dump_state()
	if not dump.has("phase"): return "dump_state should work without token"
	var ev = r["gate"].list_events("")
	if (ev as Array).size() < 1: return "list_events should work without token"
	return ""
