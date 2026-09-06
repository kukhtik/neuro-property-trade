extends RefCounted
## Phase 4 admin-console tests: engine.admin_override state-edit ops (spec §4.B).

static func test_list() -> Array[String]:
	return [
		"test_set_balance", "test_set_balance_rejects_bad_pid",
		"test_set_balance_rejects_negative", "test_teleport_moves",
		"test_teleport_rejects_bad_tile", "test_force_dice_applies",
		"test_force_dice_rejects_out_of_range", "test_grant_property",
		"test_revoke_property_clears_state", "test_set_houses",
		"test_set_houses_rejects_range", "test_set_mortgage_on_off",
		"test_set_go_jail", "test_admin_override_logged",
		"test_unknown_op_fails",
	]

static func _make_engine(names: Array = ["Ada", "Bo"]):
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var e = E.new()
	e.setup(S.new(), names)
	return e

static func _has_admin_event(e, op: String) -> bool:
	for entry in e.log.entries():
		if entry.get("type", "") == "admin_override" and entry.get("data", {}).get("op", "") == op:
			return true
	return false

static func test_set_balance() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_balance", {"pid": 0, "amount": 800})
	if not res.get("ok", false): return "expected ok: %s" % str(res)
	if e.player(0).money != 800: return "money want 800 got %d" % e.player(0).money
	if not _has_admin_event(e, "set_balance"): return "expected admin_override log"
	return ""

static func test_set_balance_rejects_bad_pid() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_balance", {"pid": 9, "amount": 100})
	if res.get("ok", false): return "should reject bad pid"
	if e.player(0).money != 1500: return "no mutation expected"
	return ""

static func test_set_balance_rejects_negative() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_balance", {"pid": 0, "amount": -5})
	if res.get("ok", false): return "should reject negative balance"
	return ""

static func test_teleport_moves() -> String:
	var e = _make_engine()
	var res = e.admin_override("teleport", {"pid": 0, "tile": 24})
	if not res.get("ok", false): return "expected ok"
	if e.player(0).position != 24: return "position want 24 got %d" % e.player(0).position
	return ""

static func test_teleport_rejects_bad_tile() -> String:
	var e = _make_engine()
	var res = e.admin_override("teleport", {"pid": 0, "tile": 99})
	if res.get("ok", false): return "should reject bad tile"
	return ""

static func test_force_dice_applies() -> String:
	var e = _make_engine()
	var res = e.admin_override("force_dice", {"d1": 1, "d2": 0})
	if not res.get("ok", false): return "expected ok"
	# next roll must be sum 1 (lands tile 1, a deterministic property, not a card)
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT": return "want PURCHASE_WAIT got %s (_last_roll=%s)" % [e.phase, str(e._last_roll)]
	if e._last_roll.get("sum", 0) != 1: return "forced roll sum want 1 got %d" % e._last_roll.get("sum", 0)
	if e._last_roll.get("doubles", true): return "forced roll should not be doubles"
	return ""

static func test_force_dice_rejects_out_of_range() -> String:
	var e = _make_engine()
	var res = e.admin_override("force_dice", {"d1": 7, "d2": 2})
	if res.get("ok", false): return "should reject dice out of 0..6"
	return ""

static func test_grant_property() -> String:
	var e = _make_engine()
	var res = e.admin_override("grant_property", {"pid": 1, "tile": 6})
	if not res.get("ok", false): return "expected ok"
	if not e.player(1).owns(6): return "player 1 should own tile 6"
	return ""

static func test_revoke_property_clears_state() -> String:
	var e = _make_engine()
	var gr = e.admin_override("grant_property", {"pid": 0, "tile": 6})
	var bh = e.admin_override("set_houses", {"tile": 6, "count": 2})
	if not bh.get("ok", false): return "set_houses should be ok (%s)" % str(bh)
	var mg = e.admin_override("set_mortgage", {"tile": 6, "on": true})
	if not mg.get("ok", false): return "set_mortgage should be ok"
	var rv = e.admin_override("revoke_property", {"pid": 0, "tile": 6})
	if not rv.get("ok", false): return "revoke should be ok"
	if e.player(0).owns(6): return "should not own after revoke"
	if e._houses.get(6, 0) != 0 or e._mortgaged.has(6): return "houses/mortgage should clear on revoke"
	return ""

static func test_set_houses() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_houses", {"tile": 6, "count": 4})
	if not res.get("ok", false): return "expected ok"
	if e._houses_on(6) != 4: return "houses want 4 got %d" % e._houses_on(6)
	return ""

static func test_set_houses_rejects_range() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_houses", {"tile": 6, "count": 9})
	if res.get("ok", false): return "should reject house count > 5"
	return ""

static func test_set_mortgage_on_off() -> String:
	var e = _make_engine()
	var g = e.admin_override("grant_property", {"pid": 0, "tile": 6})
	var on = e.admin_override("set_mortgage", {"tile": 6, "on": true})
	if not on.get("ok", false) or not e._mortgaged.has(6): return "mortgage on failed"
	var off = e.admin_override("set_mortgage", {"tile": 6, "on": false})
	if not off.get("ok", false) or e._mortgaged.has(6): return "mortgage off failed"
	return ""

static func test_set_go_jail() -> String:
	var e = _make_engine()
	var res = e.admin_override("set_go_jail", {"pid": 0})
	if not res.get("ok", false): return "expected ok"
	if not e.player(0).in_jail or e.player(0).position != 10: return "should be in jail at 10"
	return ""

static func test_admin_override_logged() -> String:
	var e = _make_engine()
	e.admin_override("teleport", {"pid": 1, "tile": 5})
	var found := false
	for entry in e.log.entries():
		if entry.get("type", "") == "admin_override":
			found = true
	if not found: return "no admin_override event in log"
	return ""

static func test_unknown_op_fails() -> String:
	var e = _make_engine()
	var res = e.admin_override("nonsense", {})
	if res.get("ok", false): return "should reject unknown op"
	return ""
