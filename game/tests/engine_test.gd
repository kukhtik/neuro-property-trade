extends RefCounted
## Tests for the authoritative Engine (core/engine.gd). Scaffold-level.

static func test_list() -> Array[String]:
	return ["test_setup_creates_players", "test_setup_money_and_position", "test_submit_intent_wrong_player_rejected", "test_submit_intent_invalid_action_rejected", "test_move_advances_position", "test_move_no_go_bonus_without_wrap", "test_go_bonus_on_wrap", "test_doubles_grants_extra_turn_same_player", "test_non_doubles_advances_next_player", "test_triple_doubles_sends_to_jail", "test_purchase_buy", "test_purchase_insufficient_funds", "test_purchase_pass_leaves_unowned", "test_base_rent_on_property", "test_auction_bid_requires_exceed", "test_auction_single_winner", "test_auction_all_pass_unowned", "test_auction_winner_pays_bid", "test_teleport_helper_moves", "test_railroad_rent_two_owned", "test_railroad_rent_single", "test_utility_rent_single_and_pair"]

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
	e.settings.auctions_on_refusal = false   # this test covers the non-auction pass path
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

static func test_auction_bid_requires_exceed() -> String:
	var r = _make_engine(["Ada", "Bo", "Cy"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})            # land tile 1, PURCHASE_WAIT
	e.submit_intent(0, "pass", {})            # open auction (auctioneer=0) → AUCTION
	if e.phase != e.PHASE_AUCTION: return "pass should open auction, phase=" + e.phase
	# bidder 0 bids 40, then bidder 1 must exceed 40
	e.submit_intent(0, "bid", {"amount": 40})
	var res = e.submit_intent(1, "bid", {"amount": 30})
	if res["ok"] == true: return "lower bid should be rejected"
	return ""

static func test_auction_single_winner() -> String:
	var r = _make_engine(["Ada", "Bo", "Cy"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})            # auction opens, auctioneer 0
	e.submit_intent(0, "bid", {"amount": 30}) # bidder 0 bids 30
	if e.player(0).owns(1): return "should not own before auction resolves"
	# rotate: bidder 1 bids/passes; bidder 2 passes; then only ... resolve
	e.submit_intent(1, "pass", {})            # bidder 1 out
	e.submit_intent(2, "pass", {})            # bidder 2 out → active=[0], winner=0
	if not e.player(0).owns(1): return "auction winner should own tile 1"
	if e.player(0).money != 1500 - 30: return "winner should pay bid 30, money=%d" % e.player(0).money
	return ""

static func test_auction_all_pass_unowned() -> String:
	var r = _make_engine(["Ada", "Bo"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})   # auctioneer 0 passes → bidder becomes 1
	e.submit_intent(0, "pass", {})   # not bidder 1 → rejected (harmless no-op)
	e.submit_intent(1, "pass", {})   # bidder 1 passes → active empty → unowned
	if e.player(0).owns(1) or e.player(1).owns(1): return "all-pass should leave tile unowned"
	return ""

static func test_auction_winner_pays_bid() -> String:
	var r = _make_engine(["Ada", "Bo"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})
	e.submit_intent(0, "bid", {"amount": 50}) # bidder 0 bids 50, high=50
	e.submit_intent(1, "pass", {})            # bidder 1 out → active=[0], winner=0 pays 50
	if e.player(0).money != 1500 - 50: return "winner must pay bid 50, got %d" % e.player(0).money
	if not e.player(0).owns(1): return "winner should own tile"
	return ""

static func test_teleport_helper_moves() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 7)
	if e.player(0).position != 7: return "teleport failed"
	return ""

static func test_railroad_rent_two_owned() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns 2 railroads (5 and 15) → rent for landing on 15 = 25*2^(2-1)=50
	e.player(1).add_ownership(5)
	e.player(1).add_ownership(15)
	e._teleport(0, 14)              # player 0 at 14
	e._force_dice(1, 1, 0, false)   # move 1 → tile 15 (railroad owned by player 1)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 50: return "railroad rent for 2 owned should be 50, money=%d" % e.player(0).money
	if e.player(1).money != 1500 + 50: return "railroad owner not credited, money=%d" % e.player(1).money
	return ""

static func test_railroad_rent_single() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(15)   # player 1 owns 1 railroad (tile 15)
	e._teleport(0, 14)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})  # lands tile 15, owned by player 1, rent 25*(2^0)=25
	if e.player(0).money != 1500 - 25: return "single railroad rent should be 25, money=%d" % e.player(0).money
	return ""

static func test_utility_rent_single_and_pair() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(12)   # player 1 owns ONE utility (12)
	e._teleport(0, 11)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 12 (utility), sum=1
	e.submit_intent(0, "roll", {})
	# single utility: rent = 4 * sum = 4 * 1 = 4
	if e.player(0).money != 1500 - 4: return "single utility rent should be 4, money=%d" % e.player(0).money
	# now test pair: reset engine fresh
	var r2 = _make_engine()
	var e2 = r2["engine"]
	e2.player(1).add_ownership(12)
	e2.player(1).add_ownership(28)  # player 1 owns BOTH utilities
	e2._teleport(0, 11)
	e2._force_dice(1, 1, 0, false)
	e2.submit_intent(0, "roll", {})
	# pair utility: rent = 10 * sum = 10 * 1 = 10
	if e2.player(0).money != 1500 - 10: return "pair utility rent should be 10, money=%d" % e2.player(0).money
	return ""
