extends RefCounted
## Tests for the authoritative Engine (core/engine.gd). Scaffold-level.

static func test_list() -> Array[String]:
	return ["test_setup_creates_players", "test_setup_money_and_position", "test_submit_intent_wrong_player_rejected", "test_submit_intent_invalid_action_rejected", "test_move_advances_position", "test_move_no_go_bonus_without_wrap", "test_go_bonus_on_wrap", "test_doubles_grants_extra_turn_same_player", "test_non_doubles_advances_next_player", "test_triple_doubles_sends_to_jail", "test_purchase_buy", "test_purchase_insufficient_funds", "test_purchase_pass_leaves_unowned", "test_base_rent_on_property", "test_auction_bid_requires_exceed", "test_auction_single_winner", "test_auction_all_pass_unowned", "test_auction_winner_pays_bid", "test_teleport_helper_moves", "test_railroad_rent_two_owned", "test_railroad_rent_single", "test_utility_rent_single_and_pair", "test_tax_charged", "test_free_parking_default_noop", "test_go_to_jail_sends_to_jail_tile", "test_jail_pay_fine_leaves_and_rolls", "test_jail_roll_doubles_leaves_and_moves", "test_jail_roll_no_doubles_stays_and_fails", "test_jail_three_failures_forces_pay", "test_card_collect_applied", "test_card_go_to_jail", "test_monopoly_rent_x2_doubled", "test_monopoly_rent_not_without_full_set", "test_build_requires_full_set", "test_build_even_and_charge", "test_build_rejects_uneven", "test_house_rent_increases", "test_sell_house_refunds_half", "test_mortgage_grants_loan", "test_mortgage_blocks_rent", "test_mortgage_breaks_monopoly", "test_unmortgage_repays_premium", "test_cannot_mortgage_with_houses", "test_bankrupt_rent_transfers_assets", "test_bankrupt_removes_player", "test_bankruptcy_turns_detect_winner", "test_game_over_blocks_intents", "test_solvent_payment_no_bankruptcy", "test_trade_propose_and_accept_swaps", "test_trade_decline_leaves_state", "test_trade_requires_owning_offered", "test_trade_blocks_non_recipient_response", "test_trade_rejects_self_or_invalid_target", "test_bankrupt_mid_turn_no_deadlock", "test_bankrupt_non_turn_player_keeps_turn", "test_recovered_turn_hands_over_exactly_once", "test_bankruptcy_latch_is_transient", "test_card_back_three_never_leaves_the_board", "test_negative_position_never_pends_a_purchase", "test_invalid_pending_purchase_does_not_deadlock", "test_board_type_at_bounds_checked", "test_imprisoned_penniless_has_a_legal_move", "test_served_sentence_frees_penniless_player", "test_jail_pay_still_required_when_affordable"]

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

static func test_tax_charged() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 3)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 4 (Tax 200)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 200: return "tax 200 not charged, money=%d" % e.player(0).money
	return ""

static func test_free_parking_default_noop() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 19)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 20 (free_parking, house rule OFF)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500: return "free_parking should not change money, got %d" % e.player(0).money
	return ""

static func test_go_to_jail_sends_to_jail_tile() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 29)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 30 (go_to_jail)
	e.submit_intent(0, "roll", {})
	if e.player(0).in_jail != true: return "go_to_jail should jail player"
	if e.player(0).position != 10: return "jailed to tile 10, got %d" % e.player(0).position
	return ""

static func test_jail_pay_fine_leaves_and_rolls() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).in_jail = true
	e.player(0).position = 10
	e._force_dice(1, 1, 0, false)   # after paying, roll sum 1 → tile 11 (Oak Street unowned → PURCHASE_WAIT)
	var res = e.submit_intent(0, "pay", {})
	if res["ok"] != true: return "pay rejected: " + res.get("reason", "")
	if e.player(0).in_jail != false: return "pay should leave jail"
	if e.player(0).money != 1500 - 50: return "jail fine 50 not charged, money=%d" % e.player(0).money
	return ""

static func test_jail_roll_doubles_leaves_and_moves() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).in_jail = true
	e.player(0).position = 10
	e._force_dice(8, 4, 4, true)    # doubles sum 8 → out of jail to tile 18 (Aspen Way unowned → PURCHASE_WAIT)
	var res = e.submit_intent(0, "roll", {})
	if res["ok"] != true: return "jail roll rejected"
	if e.player(0).in_jail != false: return "doubles should leave jail"
	if e.turn_player != 0: return "after leaving jail via doubles, player should be in PURCHASE_WAIT (not advanced), got turn_player=%d" % e.turn_player
	return ""

static func test_jail_roll_no_doubles_stays_and_fails() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).in_jail = true
	e.player(0).position = 10
	e._force_dice(6, 3, 3, false)   # non-doubles (sum 6, but is_doubles=false)
	e.submit_intent(0, "roll", {})
	if e.player(0).in_jail != true: return "non-doubles should stay in jail"
	if e.turn_player != 1: return "failed jail roll should advance turn, got %d" % e.turn_player
	if e.player(0).jail_turns != 1: return "jail_turns should be 1, got %d" % e.player(0).jail_turns
	return ""

static func test_jail_three_failures_forces_pay() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).in_jail = true
	e.player(0).position = 10
	e.player(0).jail_turns = 2
	# 3rd roll attempt is a failure → jail_turns 3
	e._force_dice(5, 2, 3, false)
	var res = e.submit_intent(0, "roll", {})
	if res["ok"] != true: return "2 jail_turns then a roll should still be allowed (3rd failure)"
	if e.player(0).jail_turns != 3: return "jail_turns should now be 3, got %d" % e.player(0).jail_turns
	if e.player(0).in_jail != true: return "still in jail"
	# now 3 failures — next "roll" should be rejected; only pay/use_card
	# (note: the failed attempt advanced the turn to player 1 — bring the jailed
	# player back so their next jail decision can be exercised)
	e.turn_player = 0
	e._force_dice(5, 2, 3, false)
	var res2 = e.submit_intent(0, "roll", {})
	if res2["ok"] == true: return "after 3 failures roll must be rejected"
	var legal: Array = res2.get("legal", []) as Array
	if legal.has("pay") != true: return "after 3 failures 'pay' must be legal, got %s" % str(legal)
	return ""

static func test_card_collect_applied() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 1)
	e._force_draw_card("community", "collect", 50)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 2 (community), draws forced collect 50
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 + 50: return "community collect 50 not applied, money=%d" % e.player(0).money
	return ""

static func test_card_go_to_jail() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._teleport(0, 6)
	e._force_draw_card("chance", "go_to_jail", 0)
	e._force_dice(1, 1, 0, false)   # move 1 → tile 7 (chance), draws forced go_to_jail
	e.submit_intent(0, "roll", {})
	if e.player(0).in_jail != true: return "go_to_jail card should jail player"
	if e.player(0).position != 10: return "jailed to tile 10, got %d" % e.player(0).position
	return ""

static func test_monopoly_rent_x2_doubled() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns BOTH brown tiles (1 Sunset, 3 Palm) → monopoly for group "brown"
	e.player(1).add_ownership(1)
	e.player(1).add_ownership(3)
	# land player 0 on tile 1 (Sunset, owned by player 1): base rent 2, rent_set 4
	e._teleport(0, 0)  # at Start
	# need to reach tile 1 with sum 1
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 4: return "monopoly rent should be rent_set 4, money=%d" % e.player(0).money
	return ""

static func test_monopoly_rent_not_without_full_set() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns only tile 1 (NOT tile 3) → no monopoly → base rent 2
	e.player(1).add_ownership(1)
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 2: return "without full set rent should be base 2, money=%d" % e.player(0).money
	return ""

static func test_build_requires_full_set() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 0 owns only tile 1 (not full brown set)
	e.player(0).add_ownership(1)
	var res = e.submit_intent(0, "build_house", {"tile": 1})
	if res["ok"] == true: return "build without full set should fail"
	return ""

static func test_build_even_and_charge() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# give full brown set to player 0 (tiles 1 and 3)
	e.player(0).add_ownership(1)
	e.player(0).add_ownership(3)
	var money_before = e.player(0).money
	var res = e.submit_intent(0, "build_house", {"tile": 1})
	if res["ok"] != true: return "build on full set should succeed: " + res.get("reason", "")
	# house_cost for brown = 50
	if e.player(0).money != money_before - 50: return "house cost 50 not charged, money=%d" % e.player(0).money
	if e._houses_on(1) != 1: return "tile 1 should have 1 house"
	return ""

static func test_build_rejects_uneven() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(1)
	e.player(0).add_ownership(3)
	e.submit_intent(0, "build_house", {"tile": 1})   # tile1: 1 house
	e.submit_intent(0, "build_house", {"tile": 1})   # tile1: 2 houses, tile3: 0 -> uneven, reject
	var res = e.submit_intent(0, "build_house", {"tile": 1})
	if res["ok"] == true: return "uneven build on tile 1 should fail (min is tile3=0)"
	return ""

static func test_house_rent_increases() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns full brown set with 1 house on tile 1
	e.player(1).add_ownership(1)
	e.player(1).add_ownership(3)
	e._houses[1] = 1   # directly place a house on tile 1 for player 1 (engine-owned dict)
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)   # player 0 lands on tile 1 (owned by player 1, 1 house)
	e.submit_intent(0, "roll", {})
	# house rents brown tile1: houses[0] = 10
	if e.player(0).money != 1500 - 10: return "1-house rent should be 10, money=%d" % e.player(0).money
	return ""

static func test_sell_house_refunds_half() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(1)
	e.player(0).add_ownership(3)
	var m0 = e.player(0).money
	e.submit_intent(0, "build_house", {"tile": 1})
	var m1 = e.player(0).money   # after build (should be m0 - 50)
	if e._houses_on(1) != 1: return "expected 1 house after build"
	var res = e.submit_intent(0, "sell_house", {"tile": 1})
	if res["ok"] != true: return "sell should succeed: " + res.get("reason", "")
	# refund = 25 (half of 50), only 1 house in group (tile3=0)... even-build on sell: tile3 has 0, selling tile1 from 1->0 is allowed since it becomes 0 = min.
	if e.player(0).money != m1 + 25: return "refund should be +25, money=%d" % e.player(0).money
	if e._houses_on(1) != 0: return "should be 0 houses after sell"
	return ""

static func test_mortgage_grants_loan() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(1)   # Sunset Blvd cost 60
	var m0 = e.player(0).money
	var res = e.submit_intent(0, "mortgage_property", {"tile": 1})
	if res["ok"] != true: return "mortgage should succeed: " + res.get("reason", "")
	# 50% of 60 = 30
	if e.player(0).money != m0 + 30: return "mortgage loan should be +30, money=%d" % e.player(0).money
	if e._mortgaged.has(1) != true: return "tile 1 should be mortgaged"
	return ""

static func test_mortgage_blocks_rent() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(1)   # player 1 owns tile 1, mortgaged
	e._mortgaged.append(1)
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)  # player 0 lands on tile 1 (mortgaged)
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500: return "mortgaged property should collect no rent, money=%d" % e.player(0).money
	return ""

static func test_mortgage_breaks_monopoly() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns both brown tiles but tile 3 is mortgaged
	e.player(1).add_ownership(1)
	e.player(1).add_ownership(3)
	e._mortgaged.append(3)
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)  # land on tile 1 (owned by player 1)
	e.submit_intent(0, "roll", {})
	# base rent 2 (mortgage on tile 3 breaks the monopoly doubling)
	if e.player(0).money != 1500 - 2: return "mortgaged set should use base rent 2, money=%d" % e.player(0).money
	return ""

static func test_unmortgage_repays_premium() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(1)
	e._mortgaged.append(1)
	var m0 = e.player(0).money
	var res = e.submit_intent(0, "unmortgage_property", {"tile": 1})
	if res["ok"] != true: return "unmortgage should succeed: " + res.get("reason", "")
	# repay 110% of 60 = 66
	if e.player(0).money != m0 - 66: return "unmortgage should repay 66, money=%d" % e.player(0).money
	if e._mortgaged.has(1) == true: return "tile 1 should no longer be mortgaged"
	return ""

static func test_cannot_mortgage_with_houses() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(1)
	e._houses[1] = 1   # has a house
	var res = e.submit_intent(0, "mortgage_property", {"tile": 1})
	if res["ok"] == true: return "cannot mortgage a property with houses"
	return ""

static func test_bankrupt_rent_transfers_assets() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns tile 37 (Grand Avenue, green? actually darkblue group). Give them a pricey tile: 39 Grand Place (darkblue, rent base 50).
	e.player(1).add_ownership(39)
	# player 0 near the end with low cash
	e.player(0).money = 30
	e.player(0).position = 38   # Luxury Tax tile
	e.player(0).add_ownership(5)  # player 0 owns railroad 5 (will be transferred to creditor on bankruptcy)
	var ada = e.player(0)   # capture pre-removal references — the players array shrinks when Ada goes bankrupt
	var bo = e.player(1)
	e._force_dice(1, 1, 0, false)  # move 1 → tile 39 (darkblue, owned by player 1, rent 50)
	e.submit_intent(0, "roll", {})
	# player 0 can't pay 50 (has 30) → bankrupt, railroad 5 transfers to player 1 (creditor)
	if ada.bankrupt != true: return "player 0 should be bankrupt"
	if ada.owns(5) == true: return "bankrupt player should lose railroad 5"
	if bo.owns(5) != true: return "railroad 5 should transfer to creditor player 1"
	return ""

static func test_bankrupt_removes_player() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(39)   # rent 50
	e.player(0).money = 10
	e.player(0).position = 38
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.player_count() != 1: return "bankrupt player should be removed, count=%d" % e.player_count()
	if e.player_count() == 1 and e.player(0).name != "Bo": return "remaining player should be Bo (player 1)"
	return ""

static func test_bankruptcy_turns_detect_winner() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(39)
	e.player(0).money = 5
	e.player(0).position = 38
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.phase != e.PHASE_END_GAME: return "should reach END_GAME, phase=%s" % e.phase
	return ""

static func test_game_over_blocks_intents() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(39)
	e.player(0).money = 5
	e.player(0).position = 38
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	var res = e.submit_intent(1, "roll", {})
	if res["ok"] == true: return "game over should block intents"
	return ""

static func test_solvent_payment_no_bankruptcy() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(1).add_ownership(1)   # Sunset Blvd rent 2
	e._teleport(0, 0)
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.player(0).bankrupt == true: return "solvent player should not be bankrupt"
	if e.player(0).money != 1500 - 2: return "rent 2 charged, money=%d" % e.player(0).money
	return ""

static func test_trade_propose_and_accept_swaps() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 0 owns railroad 5, player 1 owns railroad 15; trade 5 for 15
	e.player(0).add_ownership(5)
	e.player(1).add_ownership(15)
	var res = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [5], "give_cash": 0, "want_tiles": [15], "want_cash": 0})
	if res["ok"] != true: return "propose rejected: " + res.get("reason", "")
	var res2 = e.submit_intent(1, "respond_trade", {"accept": true})
	if res2["ok"] != true: return "accept rejected: " + res2.get("reason", "")
	if e.player(0).owns(15) != true: return "player 0 should now own tile 15"
	if e.player(1).owns(5) != true: return "player 1 should now own tile 5"
	if e.player(0).owns(5) == true: return "player 0 should have given up tile 5"
	return ""

static func test_trade_decline_leaves_state() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(5)
	e.player(1).add_ownership(15)
	e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [5], "give_cash": 0, "want_tiles": [15], "want_cash": 100})
	var res = e.submit_intent(1, "respond_trade", {"accept": false})
	if res["ok"] != true: return "decline rejected: " + res.get("reason", "")
	if e.player(0).owns(5) != true: return "proposer should still own tile 5 after decline"
	if e.player(1).owns(15) != true: return "recipient should still own tile 15 after decline"
	return ""

static func test_trade_requires_owning_offered() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 0 does NOT own tile 5, tries to trade it away
	var res = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [5], "give_cash": 0, "want_tiles": [], "want_cash": 0})
	if res["ok"] == true: return "should reject offering a tile you don't own"
	return ""

static func test_trade_blocks_non_recipient_response() -> String:
	var r = _make_engine(["Ada", "Bo", "Cy"])
	var e = r["engine"]
	e.player(0).add_ownership(5)
	e.player(1).add_ownership(15)
	e.player(2).add_ownership(3)   # Cy owns tile 3 to keep things simple
	e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [5], "give_cash": 0, "want_tiles": [15], "want_cash": 0})
	# player 2 is NOT the recipient — only player 1 may respond
	var res = e.submit_intent(2, "respond_trade", {"accept": true})
	if res["ok"] == true: return "non-recipient should not be able to respond"
	return ""

static func test_trade_rejects_self_or_invalid_target() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e.player(0).add_ownership(5)
	var res = e.submit_intent(0, "propose_trade", {"to": 0, "give_tiles": [5], "give_cash": 0, "want_tiles": [], "want_cash": 0})
	if res["ok"] == true: return "should reject trading with yourself"
	var res2 = e.submit_intent(0, "propose_trade", {"to": 7, "give_tiles": [5], "give_cash": 0, "want_tiles": [], "want_cash": 0})
	if res2["ok"] == true: return "should reject out-of-range recipient"
	return ""

# --- regression: bankruptcy during resolution must not strand the engine ---
# Found by tools/soak_cli.gd (seed 12345): with 3+ players, a rent bankruptcy
# removed the turn player while phase was still ROLL_RESOLVE, leaving EVERY seat
# with zero legal actions - a dead game that no timer or driver can unblock.

static func _three_players_with_rent_trap():
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.rng_seed = 4242   # every roll in this fixture must be reproducible
	var e = E.new()
	e.setup(s, ["Ada", "Bo", "Cyd"])
	# Bo owns tile 6 (Cedar Ave, cost 100, base rent 6? no - use a pricier
	# tile so the rent is unambiguous): tile 18 (cost 180, rent 18) keeps the
	# arithmetic obvious when read back from the log.
	e.player(1).add_ownership(18)
	e.player(0).position = 17   # one step short of Bo's tile
	e.player(0).money = 10      # cannot pay any rent at all
	return e

static func test_bankrupt_mid_turn_no_deadlock() -> String:
	var e = _three_players_with_rent_trap()
	e._force_dice(1, 1, 0, false)   # sum 1 -> tile 18, owned by Bo -> bankruptcy
	e.submit_intent(0, "roll", {})
	if e.player_count() != 2:
		return "bankrupt player should be removed, count=%d" % e.player_count()
	if e.phase != "TURN_START":
		return "phase must recover to TURN_START, got %s" % e.phase
	var legal_total := 0
	for pid in e.player_count():
		legal_total += e.legal_actions(pid).size()
	if legal_total == 0:
		return "dead game: no seat has a legal action after bankruptcy"
	return ""

static func test_bankrupt_non_turn_player_keeps_turn() -> String:
	var e = _three_players_with_rent_trap()
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	# Ada (the turn player, now bankrupt and removed) was followed by Bo; the
	# recovered turn holder must be a real seat that can actually roll.
	var holder_name: String = e.player(e.turn_player).name
	if holder_name == "Cyd":
		return "turn skipped Bo after Ada was removed (holder=%s)" % holder_name
	if not e.legal_actions(e.turn_player).has("roll"):
		return "recovered turn holder %s cannot roll" % holder_name
	# and the game must continue: one intent is accepted
	var res: Dictionary = e.submit_intent(e.turn_player, "roll", {})
	if not res.get("ok", false):
		return "recovered turn holder could not act: %s" % str(res.get("reason", ""))
	return ""

static func test_recovered_turn_hands_over_exactly_once() -> String:
	# After recovery the turn must be handed over exactly once. The latch that
	# suppresses a second advance is transient: it must NOT be able to eat a
	# later, legitimate turn change.
	var e = _three_players_with_rent_trap()
	e.player(0).add_ownership(5)     # Ada owns a railroad; it transfers to Bo
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	# NOTE: removing Ada (index 0) shifts Bo to index 0, so look the creditor up
	# by name - indexing by the pre-removal pid is exactly the kind of mistake
	# the seat layer has to avoid.
	var bo = null
	for pp in e.players:
		if pp.name == "Bo":
			bo = pp
	if bo == null:
		return "Bo vanished from the player list"
	if not bo.owns(5):
		return "creditor should have received the bankrupt player's tile"
	if e.player(e.turn_player).name != "Bo":
		return "turn should sit with Bo after Ada was removed, got %s" % e.player(e.turn_player).name

	# Bo rolls a non-doubles move; the turn must land on the ONE remaining other
	# seat (Cyd). If the latch leaked, a seat would be silently skipped.
	e._force_dice(4, 2, 2, false)
	var res: Dictionary = e.submit_intent(e.turn_player, "roll", {})
	if not res.get("ok", false):
		return "Bo could not roll after recovery: %s" % str(res.get("reason", ""))
	if e.phase == "PURCHASE_WAIT":
		e.submit_intent(e.turn_player, "pass", {})
	if e.player(e.turn_player).name != "Cyd":
		return "turn should pass to Cyd, got %s (phase %s)" % [e.player(e.turn_player).name, e.phase]
	return ""

static func test_bankruptcy_latch_is_transient() -> String:
	# The "turn already handed over" latch is consumed by the end-of-turn path
	# or cleared when the next intent begins - it can never suppress an advance
	# for a later, unrelated intent.
	var e = _three_players_with_rent_trap()
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.player_count() != 2:
		return "expected 2 survivors"
	var holder: int = e.turn_player
	e._force_dice(5, 2, 3, false)      # non-doubles
	var res: Dictionary = e.submit_intent(holder, "roll", {})
	if not res.get("ok", false):
		return "recovered holder could not act: %s" % str(res.get("reason", ""))
	if e.phase == "PURCHASE_WAIT":
		e.submit_intent(holder, "pass", {})
	if e.turn_player == holder:
		return "the turn did not advance after a non-doubles roll"
	return ""

# --- regression: the board ring is a ring (no negative positions) ---
# Found by tools/soak_cli.gd (seed 2026, 3 players): the community card
# "Go Back Three Spaces" resolved to position -1, because Godot's % keeps the
# sign of the dividend. The engine then opened PURCHASE_WAIT on tile -1.

static func _community_engine(player_names: Array = ["Ada", "Bo", "Cyd"]):
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, player_names)
	return e

static func test_card_back_three_never_leaves_the_board() -> String:
	var n: int = _community_engine().board.tile_count()
	# Backwards moves must land exactly on the wrapped tile and always stay on
	# the board. Forwards moves may cascade (landing on another card tile draws
	# again), so those only assert the position stays in range.
	for start in range(n):
		for value in [-3, -5, -1]:
			var eb = _community_engine()
			eb.turn_player = 0
			eb.player(0).position = start
			eb._apply_card_effect({"kind": "community", "effect": "advance", "value": value})
			var expected: int = posmod(start + value, n)
			# Landing on another card tile cascades into a fresh draw, so only
			# assert the exact landing when the destination has no cascade; in
			# every case the position must equal the wrapped tile or stay on the
			# board (never negative).
			# Only assert the exact landing for destinations that resolve in
			# place: card tiles draw again and "go to jail" relocates the piece.
			var landing: String = eb.board.type_at(expected)
			if landing in ["property", "railroad", "utility", "tax", "go", "jail", "free_parking"]:
				if eb.player(0).position != expected:
					return "advance %d from %d: want %d, got %d" % [value, start, expected, eb.player(0).position]
			var pos_neg: int = eb.player(0).position
			if pos_neg < 0 or pos_neg >= n:
				return "advance %d from %d left the board: position %d (n=%d)" % [value, start, pos_neg, n]
	for start in range(n):
		for value in [3, 7]:
			var ef = _community_engine()
			ef.turn_player = 0
			ef.player(0).position = start
			ef._apply_card_effect({"kind": "community", "effect": "advance", "value": value})
			var pos: int = ef.player(0).position
			if pos < 0 or pos >= n:
				return "advance %d from %d left the board: position %d (n=%d)" % [value, start, pos, n]
	return ""

static func test_negative_position_never_pends_a_purchase() -> String:
	# A pending purchase must always reference a real tile.
	var e = _community_engine()
	e.turn_player = 0
	e.player(0).position = 2
	e._apply_card_effect({"kind": "community", "effect": "advance", "value": -3})
	if e.phase == "PURCHASE_WAIT":
		var tile: int = int(e._pending.get("tile", -1))
		if e.board.tile_at(tile).is_empty():
			return "PURCHASE_WAIT pended on a nonexistent tile %d" % tile
	if e.player(0).position < 0:
		return "player position left the board: %d" % e.player(0).position
	return ""

static func test_invalid_pending_purchase_does_not_deadlock() -> String:
	# Force the corrupt state explicitly: the phase must still be unblockable and
	# the game must continue rather than freezing with zero legal actions.
	var e = _community_engine()
	e.turn_player = 0
	e.phase = "PURCHASE_WAIT"
	e._pending = {"tile": -1}
	var legal: Array = e.legal_actions(0)
	if legal.is_empty():
		return "no legal action for an invalid pending purchase - dead game"
	var res: Dictionary = e.submit_intent(0, "pass", {})
	if not res.get("ok", false):
		return "recovery pass rejected: %s" % str(res.get("reason", ""))
	if e.phase == "PURCHASE_WAIT":
		return "phase stayed in PURCHASE_WAIT after the recovery pass"
	if e.log.entries_of_type("purchase_dropped").size() == 0:
		return "the dropped purchase was not recorded in the event log"
	return ""

static func test_board_type_at_bounds_checked() -> String:
	var Board = load("res://core/board.gd")
	var b = Board.new()
	var f = FileAccess.open("res://data/board.json", FileAccess.READ)
	b.load_from_json(JSON.parse_string(f.get_as_text()))
	f.close()
	if b.type_at(-1) != "":
		return "type_at(-1) should be empty, got '%s' (negative index wrapped to the last tile)" % b.type_at(-1)
	if b.type_at(b.tile_count()) != "":
		return "type_at(tile_count) should be empty"
	if b.tile_at(-1) != {}:
		return "tile_at(-1) should be empty"
	if b.type_at(0) == "":
		return "type_at(0) must still resolve the first tile"
	return ""

# --- regression: a jailed seat can always act ---
# Found by tools/soak_cli.gd (seed 2002, 2 players): a penniless, card-less
# player with three served attempts had ZERO legal actions, freezing the game.

static func _jailed_engine(money: int, jail_turns: int, cards: int):
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.rng_seed = 4242   # every roll in this fixture must be reproducible
	var e = E.new()
	e.setup(s, ["Ada", "Bo"])
	e.turn_player = 0
	var p = e.player(0)
	p.in_jail = true
	p.position = 10
	p.money = money
	p.jail_turns = jail_turns
	p.get_out_of_jail_cards = cards
	return e

static func test_imprisoned_penniless_has_a_legal_move() -> String:
	# the exact frozen state: served time, cannot pay, no card
	var e = _jailed_engine(0, 3, 0)
	var legal: Array = e.legal_actions(0)
	if legal.is_empty():
		return "a jailed, penniless, card-less seat had no legal action - dead game"
	if not legal.has("roll"):
		return "the only possible move must be 'roll', got %s" % str(legal)
	if legal.has("pay"):
		return "'pay' must not be offered without the money"
	if legal.has("use_card"):
		return "'use_card' must not be offered without a card"
	return ""

static func test_served_sentence_frees_penniless_player() -> String:
	var e = _jailed_engine(0, 3, 0)
	e._force_dice(2, 1, 1, false)   # 10 -> 12 (utility, unowned): nothing to pay
	var res: Dictionary = e.submit_intent(0, "roll", {})
	if not res.get("ok", false):
		return "the final-attempt roll was refused: %s" % str(res.get("reason", ""))
	if e.phase == "END_GAME":
		return "unexpected end of game"
	# the player must be free and off the jail tile (no infinite retry loop)
	if e.player(0).in_jail:
		return "the served sentence must release the player"
	if e.player(0).jail_turns != 0:
		return "jail_turns should reset, got %d" % e.player(0).jail_turns
	if e.player(0).position == 10:
		return "a freed player must move (still parked on the jail tile)"
	# and the game must be able to continue: someone has a legal action
	var total := 0
	for pid in e.player_count():
		total += e.legal_actions(pid).size()
	if total == 0:
		return "no seat can act after the release - still dead"
	return ""

static func test_jail_pay_still_required_when_affordable() -> String:
	# The escape hatch must not weaken the normal path: with cash and no card,
	# a served sentence still offers the choice, and paying releases immediately.
	var e = _jailed_engine(500, 3, 0)
	var legal: Array = e.legal_actions(0)
	if not legal.has("pay"):
		return "an affordable fine must be offered, got %s" % str(legal)
	e._force_dice(2, 1, 1, false)
	var res: Dictionary = e.submit_intent(0, "pay", {})
	if not res.get("ok", false):
		return "pay was refused: %s" % str(res.get("reason", ""))
	if e.player(0).in_jail:
		return "paying the fine must release the player"
	var paid := false
	for entry in e.log.entries_of_type("jail"):
		var data: Dictionary = entry["data"]
		if String(data.get("reason", "")) == "paid fine" and int(data.get("amount", 0)) == e.settings.jail_fine:
			paid = true
	if not paid:
		return "no 'paid fine' event for %d in the log" % e.settings.jail_fine
	# with a card in hand the card path wins and the roll stays restricted
	var e2 = _jailed_engine(0, 1, 1)
	var legal2: Array = e2.legal_actions(0)
	if legal2.has("pay"):
		return "'pay' must not be offered without the money"
	if not legal2.has("use_card"):
		return "a held card must be offered, got %s" % str(legal2)
	if not legal2.has("roll"):
		return "an attempt remains available at jail_turns=1"
	return ""
