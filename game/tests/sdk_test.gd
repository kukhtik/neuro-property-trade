extends RefCounted
## Tests for the pure SDK adapter pieces: engine.legal_actions, projection,
## markdown_renderer, decision_controller. These never touch the SDK autoloads
## (which don't resolve in --script mode), so they run headless.

static func test_list() -> Array[String]:
	return [
		"test_legal_actions_turn_start_roll",
		"test_legal_actions_not_your_turn_empty",
		"test_legal_actions_purchase_wait",
		"test_legal_actions_purchase_insufficient",
		"test_legal_actions_auction_bidder",
		"test_legal_actions_auction_non_bidder_empty",
		"test_legal_actions_trade_recipient",
		"test_legal_actions_jail",
		"test_legal_actions_game_over_empty",
		"test_projection_public_board",
		"test_projection_private_jail_cards_isolated",
		"test_projection_pending_purchase",
		"test_projection_pending_auction",
		"test_renderer_contains_sections",
		"test_renderer_legal_actions_listed",
		"test_decision_force_when_legal",
		"test_decision_no_force_when_no_legal",
		"test_decision_priority_low_ephemeral",
	]

static func _make_engine(player_names: Array = ["Ada", "Bo"]) -> Dictionary:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, player_names)
	return {"engine": e}

static func _make_projection() -> Dictionary:
	var P = load("res://sdk/projection.gd")
	return {"proj": P.new()}

static func _make_renderer() -> Dictionary:
	var R = load("res://sdk/markdown_renderer.gd")
	return {"renderer": R.new()}

static func _make_controller() -> Dictionary:
	var C = load("res://sdk/decision_controller.gd")
	return {"controller": C.new()}

# --- legal_actions ---

static func test_legal_actions_turn_start_roll() -> String:
	var r = _make_engine()
	var legal = r["engine"].legal_actions(0)
	if not legal.has("roll"):
		return "turn_start should allow roll, got %s" % str(legal)
	return ""

static func test_legal_actions_not_your_turn_empty() -> String:
	var r = _make_engine()
	var legal = r["engine"].legal_actions(1)
	if legal.size() != 0:
		return "player 1 (not turn) should have no legal actions, got %s" % str(legal)
	return ""

static func test_legal_actions_purchase_wait() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# teleport player 0 to tile 0 and force a roll that lands on tile 1
	# (Sunset Blvd, unowned property, cost 60)
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)  # sum 1 -> tile 1
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT":
		return "expected PURCHASE_WAIT, got %s" % e.phase
	var legal = e.legal_actions(0)
	if not legal.has("buy") or not legal.has("pass"):
		return "purchase_wait should allow buy+pass, got %s" % str(legal)
	return ""

static func test_legal_actions_purchase_insufficient() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).change_cash(-1500)  # money 0
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.phase != "PURCHASE_WAIT":
		return "expected PURCHASE_WAIT, got %s" % e.phase
	var legal = e.legal_actions(0)
	if legal.has("buy"):
		return "insufficient funds should not allow buy, got %s" % str(legal)
	if not legal.has("pass"):
		return "should still allow pass, got %s" % str(legal)
	return ""

static func test_legal_actions_auction_bidder() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# start an auction directly
	e._start_auction(1)
	if e.phase != "AUCTION":
		return "expected AUCTION, got %s" % e.phase
	var bidder = e._pending.get("bidder", -1)
	var legal = e.legal_actions(bidder)
	if not legal.has("bid") or not legal.has("pass"):
		return "auction bidder should allow bid+pass, got %s" % str(legal)
	return ""

static func test_legal_actions_auction_non_bidder_empty() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._start_auction(1)
	var bidder = e._pending.get("bidder", -1)
	var other = (bidder + 1) % e.player_count()
	var legal = e.legal_actions(other)
	if legal.size() != 0:
		return "non-bidder should have no legal actions, got %s" % str(legal)
	return ""

static func test_legal_actions_trade_recipient() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 0 proposes a trade to player 1
	var res = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [], "want_tiles": [], "give_cash": 0, "want_cash": 0})
	if not res["ok"]:
		return "propose_trade should succeed: %s" % res.get("reason", "")
	var legal = e.legal_actions(1)
	if not legal.has("respond_trade"):
		return "trade recipient should be able to respond, got %s" % str(legal)
	return ""

static func test_legal_actions_jail() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).in_jail = true
	e.player(0).jail_turns = 0
	var legal = e.legal_actions(0)
	if not legal.has("roll") or not legal.has("pay"):
		return "jail should allow roll+pay, got %s" % str(legal)
	return ""

static func test_legal_actions_game_over_empty() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.phase = "END_GAME"
	var legal = e.legal_actions(0)
	if legal.size() != 0:
		return "game over should have no legal actions, got %s" % str(legal)
	return ""

# --- projection ---

static func test_projection_public_board() -> String:
	var r = _make_engine()
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 0)
	if proj["board"].size() != 40:
		return "board should have 40 tiles, got %d" % proj["board"].size()
	if proj["players"].size() != 2:
		return "should project 2 players, got %d" % proj["players"].size()
	if proj["phase"] != "TURN_START":
		return "phase should be TURN_START, got %s" % proj["phase"]
	return ""

static func test_projection_private_jail_cards_isolated() -> String:
	var r = _make_engine()
	var p = _make_projection()["proj"]
	r["engine"].player(0).get_out_of_jail_cards = 2
	r["engine"].player(1).get_out_of_jail_cards = 0
	var proj0 = p.for_player(r["engine"], 0)
	var proj1 = p.for_player(r["engine"], 1)
	if proj0["private"]["get_out_of_jail_cards"] != 2:
		return "seat 0 should see its own 2 jail cards, got %d" % proj0["private"]["get_out_of_jail_cards"]
	if proj1["private"]["get_out_of_jail_cards"] != 0:
		return "seat 1 should see its own 0 jail cards, got %d" % proj1["private"]["get_out_of_jail_cards"]
	return ""

static func test_projection_pending_purchase() -> String:
	var r = _make_engine()
	var p = _make_projection()["proj"]
	var e = r["engine"]
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	var proj = p.for_player(e, 0)
	if proj["pending"].get("type", "") != "purchase":
		return "pending should be purchase, got %s" % str(proj["pending"])
	if proj["pending"].get("tile", -1) != 1:
		return "pending purchase tile should be 1, got %d" % proj["pending"].get("tile", -1)
	return ""

static func test_projection_pending_auction() -> String:
	var r = _make_engine()
	var p = _make_projection()["proj"]
	var e = r["engine"]
	e._start_auction(1)
	var proj = p.for_player(e, 0)
	if proj["pending"].get("type", "") != "auction":
		return "pending should be auction, got %s" % str(proj["pending"])
	if proj["pending"].get("tile", -1) != 1:
		return "auction tile should be 1, got %d" % proj["pending"].get("tile", -1)
	return ""

# --- markdown_renderer ---

static func test_renderer_contains_sections() -> String:
	var r = _make_engine()
	var renderer = _make_renderer()["renderer"]
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 0)
	var md = renderer.render(proj)
	if not md.contains("## Players"):
		return "markdown should contain Players section"
	if not md.contains("## Board"):
		return "markdown should contain Board section"
	if not md.contains("## Your legal actions"):
		return "markdown should contain legal actions section"
	return ""

static func test_renderer_legal_actions_listed() -> String:
	var r = _make_engine()
	var renderer = _make_renderer()["renderer"]
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 0)
	var md = renderer.render(proj)
	if not md.contains("roll"):
		return "markdown should list roll as a legal action"
	return ""

# --- decision_controller ---

static func test_decision_force_when_legal() -> String:
	var r = _make_engine()
	var controller = _make_controller()["controller"]
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 0)
	var d = controller.decide(r["engine"], 0, proj)
	if not d["force"]:
		return "should force when seat has legal actions"
	if d["actions"].size() == 0:
		return "force should include actions"
	return ""

static func test_decision_no_force_when_no_legal() -> String:
	var r = _make_engine()
	var controller = _make_controller()["controller"]
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 1)  # not turn_player
	var d = controller.decide(r["engine"], 1, proj)
	if d["force"]:
		return "should not force when seat has no legal actions"
	return ""

static func test_decision_priority_low_ephemeral() -> String:
	var r = _make_engine()
	var controller = _make_controller()["controller"]
	var p = _make_projection()["proj"]
	var proj = p.for_player(r["engine"], 0)
	var d = controller.decide(r["engine"], 0, proj)
	if d["priority"] != "low":
		return "priority should be low, got %s" % d["priority"]
	if not d["ephemeral_context"]:
		return "ephemeral_context should be true for turn-based board dump"
	return ""
