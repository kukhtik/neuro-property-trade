extends RefCounted
## Test-ladder rung 3: Tony scripted scenarios. Each is deterministic (forced
## dice/teleports/admin overrides, no RNG) and asserts a named ending invariant.

static func test_list() -> Array[String]:
	return [
		"scenario_auction_resolve",
		"scenario_bankruptcy_transfer",
		"scenario_trade_chain",
		"scenario_admin_unblock",
	]

static func _make_engine(names: Array):
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var e = E.new()
	e.setup(S.new(), names)
	return e

static func scenario_auction_resolve() -> String:
	var e = _make_engine(["Ada", "Bo"])
	# Ada (turn 0) rolls sum 1 -> lands tile 1 (unowned) -> PURCHASE_WAIT.
	e.phase = "TURN_START"
	e.turn_player = 0
	e.admin_override("force_dice", {"d1": 1, "d2": 0})
	var r = e.submit_intent(0, "roll", {})
	if not r.get("ok", false): return "roll failed: %s" % str(r)
	if e.phase != "PURCHASE_WAIT": return "want PURCHASE_WAIT got %s" % e.phase
	# Ada passes -> starts an auction (auctions_on_refusal default on).
	var p = e.submit_intent(0, "pass", {})
	if e.phase != "AUCTION": return "want AUCTION got %s" % e.phase
	# 2-player rotation: active=[0,1], bidder starts at turn_player 0 (Ada).
	if e._pending.get("bidder", -1) != 0: return "Ada should open the bid"
	var b1 = e.submit_intent(0, "bid", {"amount": 61})
	if not b1.get("ok", false): return "Ada bid failed: %s" % str(b1)
	if e._pending.get("bidder", -1) != 1: return "expected Bo (1) to bid next"
	var b2 = e.submit_intent(1, "bid", {"amount": 62})
	if not b2.get("ok", false): return "Bo bid failed: %s" % str(b2)
	if e._pending.get("bidder", -1) != 0: return "expected Ada (0) to bid next"
	e.submit_intent(0, "pass", {})
	# only Bo (1) left with a high -> Bo wins at 62.
	if not e.players[1].owns(1): return "Bo should own tile 1 after auction"
	if e.players[1].money != 1500 - 62: return "Bo money want %d got %d" % [1500 - 62, e.players[1].money]
	if e.players[0].money != 1500: return "passing bidder should not be charged"
	if e._pending.size() != 0: return "auction pending should be cleared after win"
	return ""

static func scenario_bankruptcy_transfer() -> String:
	var e = _make_engine(["Ada", "Bo"])
	# Bo owns both brown tiles with max houses; Ada is broke and lands on one.
	e.admin_override("grant_property", {"pid": 1, "tile": 1})
	e.admin_override("grant_property", {"pid": 1, "tile": 3})
	e.admin_override("set_houses", {"tile": 1, "count": 5})
	e.admin_override("set_balance", {"pid": 0, "amount": 50})
	e.phase = "TURN_START"
	e.turn_player = 0
	e.admin_override("force_dice", {"d1": 1, "d2": 0})   # lands tile 1 (rent 250 > 50)
	var r = e.submit_intent(0, "roll", {})
	if not r.get("ok", false): return "roll failed: %s" % str(r)
	if e.phase != "END_GAME": return "want END_GAME got %s" % e.phase
	if e.player_count() != 1: return "Ada should be removed; want 1 player got %d" % e.player_count()
	if e.player(0).name != "Bo": return "Bo should be winner, got %s" % e.player(0).name
	# Ada's cash/assets transferred to Bo (her 50 + tiles).
	if e.player(0).money != 1500 + 50: return "Bo should inherit Ada's cash"
	return ""

static func scenario_trade_chain() -> String:
	var e = _make_engine(["Ada", "Bo"])
	e.admin_override("grant_property", {"pid": 0, "tile": 6})
	e.admin_override("grant_property", {"pid": 1, "tile": 11})
	var money_before_a: int = e.player(0).money
	var money_before_b: int = e.player(1).money
	var pr = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [6], "give_cash": 0, "want_tiles": [11], "want_cash": 50})
	if not pr.get("ok", false): return "propose failed: %s" % str(pr)
	var rs = e.submit_intent(1, "respond_trade", {"accept": true})
	if not rs.get("ok", false): return "accept failed: %s" % str(rs)
	if e.player(0).owns(6) or not e.player(1).owns(6): return "tile 6 should move to Bo"
	if e.player(1).owns(11) or not e.player(0).owns(11): return "tile 11 should move to Ada"
	if e.player(0).money != money_before_a + 50: return "Ada should gain 50 cash"
	if e.player(1).money != money_before_b - 50: return "Bo should lose 50 cash"
	if e._pending_trade.size() != 0: return "pending trade should be cleared"
	# Chain onward: Ada (turn) proposes back, Bo accepts -> swap reverses.
	var pr2 = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [11], "give_cash": 0, "want_tiles": [6], "want_cash": 0})
	if not pr2.get("ok", false): return "second propose failed: %s" % str(pr2)
	var rs2 = e.submit_intent(1, "respond_trade", {"accept": true})
	if not rs2.get("ok", false): return "second accept failed: %s" % str(rs2)
	if not e.player(0).owns(6) or not e.player(1).owns(11): return "chain should swap back"
	return ""

static func scenario_admin_unblock() -> String:
	var e = _make_engine(["Ada", "Bo"])
	# Ada (turn 0) is the decision holder at TURN_START. Admin forces a roll.
	e.phase = "TURN_START"
	e.turn_player = 0
	var phase_before: String = e.phase
	var res = e.admin_override("force_roll", {})
	if not res.get("ok", false): return "admin force_roll failed: %s" % str(res)
	if e.phase == phase_before: return "phase should have advanced after force_roll"
	var logged := false
	for entry in e.log.entries():
		if entry.get("type", "") == "admin_override":
			logged = true
	if not logged: return "expected admin_override event in log"
	return ""
