extends RefCounted
## Tests for the UI contracts (stage 2): EventAdapter normalises the engine's
## vocabulary, IntentMap is the only UI->engine action mapping, UiStore builds
## the ViewModel from a projection and applies deltas, LayoutProfile picks a
## responsive profile, UiProfile picks the execution role.

const Adapter := preload("res://ui/core/event_adapter.gd")
const Intents := preload("res://ui/core/intent_map.gd")
const Store := preload("res://ui/core/ui_store.gd")
const Layout := preload("res://ui/core/layout_profile.gd")
const Profile := preload("res://ui/core/ui_profile.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const I18n := preload("res://i18n/i18n.gd")

## The pass button's label follows the pending action, and it did NOT: the condition was
## `str(a == b)`, which compares first and stringifies the boolean — so it read "False", and a
## non-empty string is true in GDScript. The button was relabelled "don't buy" on every turn no
## matter what was pending. A comparison whose result is more interesting than its truth value.
static func test_action_panel_pass_label_tracks_pending() -> String:
	var p := ActionPanel.new()
	var plain: Button = p.call("_button_for", "pass", {"pending": {"type": ""}}, 0)
	if plain.text != I18n.t("act.pass"):
		return "with nothing pending the pass button must read '%s', got '%s'" % [
			I18n.t("act.pass"), plain.text]
	var during: Button = p.call("_button_for", "pass", {"pending": {"type": "purchase"}}, 0)
	if during.text != I18n.t("act.no_buy"):
		return "during a purchase the pass button must read '%s', got '%s'" % [
			I18n.t("act.no_buy"), during.text]
	p.free()
	return ""


static func test_list() -> Array[String]:
	return [
		# EventAdapter
		"test_adapter_maps_engine_types", "test_adapter_purchase_fields",
		"test_adapter_rent_from_to", "test_adapter_tax_and_go",
		"test_adapter_auction_types", "test_adapter_card_deck_and_id",
		"test_adapter_unknown_type_dropped", "test_adapter_visibility",
		"test_adapter_deltas_cash", "test_adapter_deltas_ownership",
		"test_adapter_round_tracking", "test_adapter_adapt_all_skips_noise",
		# IntentMap
		"test_intent_names_match_engine", "test_intent_tile_params",
		"test_intent_trade_payload", "test_intent_respond_accept",
		"test_intent_can_respects_legal", "test_intent_can_needs_tile",
		"test_intent_ui_only_actions", "test_intent_auction_guard",
		# UiStore
		"test_store_resync_from_projection", "test_store_resync_emits_changed",
		"test_store_delta_cash", "test_store_delta_position",
		"test_store_delta_owner_and_clear", "test_store_delta_houses_mortgage",
		"test_store_delta_bankrupt", "test_store_delta_unknown_is_noop",
		"test_store_select_tile_emits_once", "test_store_lookup_helpers",
		# LayoutProfile
		"test_layout_profiles", "test_layout_compact_by_height",
		"test_layout_rails", "test_layout_label_degradation",
		"test_action_panel_pass_label_tracks_pending",
		# UiProfile
		"test_profile_roles", "test_profile_infer_from_launch",
		"test_profile_infer_web_is_player", "test_profile_infer_desktop_is_admin",
		"test_profile_infer_stream_flag", "test_profile_infer_admin_flag",
		"test_stream_profile_is_read_only", "test_admin_profile_owns_tools",
		"test_player_profile_takes_input", "test_every_role_reports_itself",
		# Money
		"test_money_formats", "test_money_compact", "test_money_names",
		"test_adapter_cash_event_carries_delta", "test_adapter_balance_correction",
		"test_adapter_pay_event_deltas"]

# --- EventAdapter -------------------------------------------------------------

static func test_adapter_maps_engine_types() -> String:
	var a = Adapter.new()
	var cases := {
		"setup": "start", "roll": "roll", "purchase": "buy", "rent": "rent",
		"tax": "tax", "go_bonus": "go", "card_draw": "card",
		"auction_start": "aucstart", "auction_bid": "bid", "auction_pass": "pass",
		"auction_win": "aucwin", "auction_unwon": "aucnone",
		"build": "build", "sell": "sell", "mortgage": "mort",
		"unmortgage": "unmort", "trade_proposed": "trdoffer", "trade": "trade",
		"trade_declined": "trdno", "bankrupt": "bank", "winner": "over",
		"jail": "jail", "free_parking": "park",
	}
	for etype in cases:
		var ev = a.adapt({"type": etype, "data": {}})
		if ev.is_empty():
			return "engine type '%s' was not adapted" % etype
		if ev["k"] != cases[etype]:
			return "'%s' should map to '%s', got '%s'" % [etype, cases[etype], ev["k"]]
	return ""

static func test_adapter_purchase_fields() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "purchase", "data": {"player": 2, "tile": 7, "cost": 140}})
	if ev["p"] != 2 or ev["ti"] != 7:
		return "purchase p/ti wrong: %d/%d" % [ev["p"], ev["ti"]]
	# UI uses 'a' as the amount; the engine calls it 'cost'
	if ev["a"] != 140:
		return "purchase cost should land in 'a', got %d" % ev["a"]
	return ""

static func test_adapter_rent_from_to() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "rent", "data": {"from": 1, "to": 3, "tile": 9, "amount": 55}})
	if ev["p"] != 1 or ev["q"] != 3:
		return "rent must map from->p and to->q, got %d/%d" % [ev["p"], ev["q"]]
	if ev["a"] != 55 or ev["ti"] != 9:
		return "rent amount/tile wrong"
	return ""

static func test_adapter_tax_and_go() -> String:
	var a = Adapter.new()
	var tax = a.adapt({"type": "tax", "data": {"player": 0, "tile": 4, "amount": 200}})
	if tax["a"] != 200 or tax["k"] != "tax":
		return "tax adaptation wrong"
	var go = a.adapt({"type": "go_bonus", "data": {"player": 1, "amount": 200}})
	if go["k"] != "go" or go["a"] != 200 or go["p"] != 1:
		return "go_bonus adaptation wrong"
	return ""

static func test_adapter_auction_types() -> String:
	var a = Adapter.new()
	var bid = a.adapt({"type": "auction_bid", "data": {"player": 1, "amount": 30, "tile": 5}})
	if bid["k"] != "bid" or bid["a"] != 30 or bid["p"] != 1:
		return "auction_bid adaptation wrong"
	var win = a.adapt({"type": "auction_win", "data": {"player": 2, "tile": 5, "amount": 80}})
	if win["k"] != "aucwin" or win["a"] != 80:
		return "auction_win adaptation wrong"
	var none = a.adapt({"type": "auction_unwon", "data": {"tile": 5}})
	if none["k"] != "aucnone" or none["ti"] != 5:
		return "auction_unwon adaptation wrong"
	return ""

static func test_adapter_card_deck_and_id() -> String:
	var a = Adapter.new()
	var ch = a.adapt({"type": "card_draw", "data": {"player": 0, "kind": "chance", "name": "Dividends", "value": 50}})
	if ch["deck"] != "chance":
		return "card deck should be 'chance', got %s" % ch["deck"]
	if not str(ch["c"]).begins_with("ch_"):
		return "chance card id should carry a ch_ prefix, got %s" % ch["c"]
	var cc = a.adapt({"type": "card_draw", "data": {"player": 0, "kind": "community", "name": "Tax refund", "value": 20}})
	if not str(cc["c"]).begins_with("cc_"):
		return "community card id should carry a cc_ prefix, got %s" % cc["c"]
	return ""

static func test_adapter_unknown_type_dropped() -> String:
	var a = Adapter.new()
	# types the UI neither animates NOR needs for money must not surface
	for t in ["land", "land_self", "pass_on_purchase", "admin_override", "purchase_dropped"]:
		var ev = a.adapt({"type": t, "data": {}})
		if not ev.is_empty():
			return "engine type '%s' should not surface to the UI, got k=%s" % [t, ev.get("k", "")]
	# an unknown engine type must be dropped, not crash
	if not a.adapt({"type": "not_a_real_type", "data": {}}).is_empty():
		return "an unknown engine type should be dropped"
	# 'move' DOES adapt (the walk animation needs it) but stays out of the journal
	var move = a.adapt({"type": "move", "data": {"player": 0, "to": 3}})
	if move.is_empty():
		return "move should adapt so the presenter can animate the walk"
	if move["visible"]:
		return "move must not be listed in the journal"
	# 'cash' adapts (its delta is needed) but is never a journal line
	var cash = a.adapt({"type": "cash", "data": {"player": 0, "amount": 50, "balance": 1550}})
	if cash.is_empty():
		return "cash must adapt so its money delta is applied"
	if cash["visible"]:
		return "cash must not be listed in the journal"
	return ""

static func test_adapter_visibility() -> String:
	var a = Adapter.new()
	# move is a board effect, not a journal line
	var move = a.adapt({"type": "move", "data": {"player": 0, "to": 5}})
	if move["k"] != "move":
		return "move should still adapt (for the walk animation)"
	if move["visible"]:
		return "move must not be visible in the journal"
	var buy = a.adapt({"type": "purchase", "data": {"player": 0, "tile": 1, "cost": 60}})
	if not buy["visible"]:
		return "purchase must be visible in the journal"
	if buy["cat"] != "buy":
		return "purchase category should be 'buy', got %s" % buy["cat"]
	return ""

static func test_adapter_deltas_cash() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "rent", "data": {"from": 1, "to": 2, "tile": 3, "amount": 40}})
	var has_neg := false
	var has_pos := false
	for d in ev["d"]:
		if d[0] == "c" and d[1] == 1 and d[2] == -40:
			has_neg = true
		if d[0] == "c" and d[1] == 2 and d[2] == 40:
			has_pos = true
	if not has_neg or not has_pos:
		return "rent deltas should debit the payer and credit the payee: %s" % str(ev["d"])
	return ""

static func test_adapter_deltas_ownership() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "purchase", "data": {"player": 3, "tile": 11, "cost": 220}})
	var own := false
	for d in ev["d"]:
		if d[0] == "o" and d[1] == 11 and d[2] == 3:
			own = true
	if not own:
		return "purchase must emit an ownership delta: %s" % str(ev["d"])
	var win = a.adapt({"type": "auction_win", "data": {"player": 1, "tile": 5, "amount": 90}})
	var auc_own := false
	for d in win["d"]:
		if d[0] == "o" and d[1] == 5 and d[2] == 1:
			auc_own = true
	if not auc_own:
		return "auction_win must transfer ownership: %s" % str(win["d"])
	return ""

static func test_adapter_round_tracking() -> String:
	var a = Adapter.new()
	a.reset()
	# turns 0,1,2 then back to 0 -> round 2
	var r1 = a.adapt({"type": "roll", "data": {"player": 0}})["round"]
	var r2 = a.adapt({"type": "roll", "data": {"player": 1}})["round"]
	var r3 = a.adapt({"type": "roll", "data": {"player": 2}})["round"]
	var r4 = a.adapt({"type": "roll", "data": {"player": 0}})["round"]
	if r1 != 1 or r2 != 1 or r3 != 1:
		return "round should stay 1 within the first lap, got %d/%d/%d" % [r1, r2, r3]
	if r4 != 2:
		return "wrapping back to player 0 should start round 2, got %d" % r4
	return ""

static func test_adapter_adapt_all_skips_noise() -> String:
	var a = Adapter.new()
	var entries := [
		{"type": "setup", "data": {"players": 3}},
		{"type": "roll", "data": {"player": 0, "d1": 2, "d2": 5, "sum": 7}},
		{"type": "move", "data": {"player": 0, "from": 0, "to": 7}},
		{"type": "cash", "data": {"player": 0, "amount": -60, "balance": 1440}},
		{"type": "purchase", "data": {"player": 0, "tile": 7, "cost": 60}},
	]
	var out = a.adapt_all(entries)
	# every entry adapts; 'land'-style noise (not present here) is what gets cut
	if out.size() != 5:
		return "adapt_all should keep all 5 adaptive entries, got %d" % out.size()
	# but 'cash' must never be a journal line the user sees
	var visible_kinds: Array = []
	for e in out:
		if e["visible"]:
			visible_kinds.append(e["k"])
	if visible_kinds.has("cash"):
		return "adapt_all leaked the cash ledger line into the journal"
	if not visible_kinds.has("buy"):
		return "adapt_all should surface the purchase"
	return ""

# --- IntentMap ----------------------------------------------------------------

static func test_intent_names_match_engine() -> String:
	var m = Intents.new()
	var cases := {
		"roll": "roll", "buy": "buy", "decline": "pass",
		"build": "build_house", "sell": "sell_house",
		"mortgage": "mortgage_property", "unmortgage": "unmortgage_property",
		"trade_offer": "propose_trade", "trade_accept": "respond_trade",
		"trade_reject": "respond_trade", "auction_bid": "bid", "auction_pass": "pass",
	}
	for ui in cases:
		var r = m.to_engine(ui, {})
		if r.is_empty():
			return "UI action '%s' produced no engine call" % ui
		if r["action"] != cases[ui]:
			return "UI '%s' should call engine '%s', got '%s'" % [ui, cases[ui], r["action"]]
	return ""

static func test_intent_tile_params() -> String:
	var m = Intents.new()
	# build_house takes 'tile', not 'ti'
	var r = m.to_engine("build", {"tile": 12})
	if r["params"].get("tile", -1) != 12:
		return "build should pass tile=12, got %s" % str(r["params"])
	if r["params"].has("ti"):
		return "the engine expects 'tile', not 'ti'"
	return ""

static func test_intent_trade_payload() -> String:
	var m = Intents.new()
	var r = m.to_engine("trade_offer", {"to": 2, "give_tiles": [3, 4], "give_cash": 50, "want_tiles": [9], "want_cash": 0})
	var p: Dictionary = r["params"]
	if p.get("to", -1) != 2 or p.get("give_cash", -1) != 50:
		return "trade payload wrong: %s" % str(p)
	if not p.has("want_tiles") or (p["want_tiles"] as Array).size() != 1:
		return "want_tiles should carry one tile: %s" % str(p)
	if p.has("give") or p.has("get"):
		return "the engine expects give_tiles/want_tiles, not give/get"
	return ""

static func test_intent_respond_accept() -> String:
	var m = Intents.new()
	if m.to_engine("trade_accept", {})["params"].get("accept", false) != true:
		return "trade_accept should send accept=true"
	if m.to_engine("trade_reject", {})["params"].get("accept", true) != false:
		return "trade_reject should send accept=false"
	return ""

static func test_intent_can_respects_legal() -> String:
	var m = Intents.new()
	if not m.can("roll", ["roll", "build_house"]):
		return "'roll' should be allowed when legal"
	if m.can("roll", ["buy", "pass"]):
		return "'roll' must be refused when not in legal_actions"
	# legal_actions is the authority — the UI never guesses
	if m.can("build", ["roll"], {"tile": 5}):
		return "'build' must be refused when build_house is absent from legal"
	return ""

static func test_intent_can_needs_tile() -> String:
	var m = Intents.new()
	if m.can("build", ["build_house"], {"tile": -1}):
		return "a tile action must require a selected tile"
	if not m.can("build", ["build_house"], {"tile": 3}):
		return "a tile action with a selection should be allowed"
	return ""

static func test_intent_ui_only_actions() -> String:
	var m = Intents.new()
	# 'end' is engine-owned: no intent, and it only shows when no decision is pending
	if not m.to_engine("end", {}).is_empty():
		return "'end' must not produce an engine call"
	if m.can("end", ["buy", "pass"]):
		return "'end' must not be offered while a purchase decision is pending"
	if not m.can("end", ["roll", "build_house"]):
		return "'end' should be offered from a normal turn phase"
	# 'trade_open' only opens a modal
	if not m.to_engine("trade_open", {}).is_empty():
		return "'trade_open' must not produce an engine call"
	if not m.can("trade_open", ["propose_trade"]):
		return "'trade_open' should follow propose_trade in legal_actions"
	return ""

static func test_intent_auction_guard() -> String:
	var m = Intents.new()
	# during an auction legal is [bid, pass]; 'decline' must not be mistaken for it
	if m.can("decline", ["bid", "pass"]):
		return "'decline' must not trigger during an auction"
	if not m.can("auction_pass", ["bid", "pass"]):
		return "'auction_pass' should be allowed during an auction"
	if m.can("auction_pass", ["buy", "pass"]):
		return "'auction_pass' must not trigger during a purchase"
	if not m.can("auction_bid", ["bid", "pass"]):
		return "'auction_bid' should be allowed for the current bidder"
	return ""

# --- UiStore ------------------------------------------------------------------

static func _proj() -> Dictionary:
	return {
		"phase": "TURN_START",
		"turn_player": 1,
		"parking_pot": 300,
		"pending": {},
		"legal": ["roll"],
		"players": [
			{"index": 0, "name": "Ada", "money": 1500, "position": 0, "bankrupt": false},
			{"index": 1, "name": "Bo", "money": 1200, "position": 5, "bankrupt": false},
		],
		"board": [
			{"index": 0, "name": "Start", "type": "go", "owner": -1, "houses": 0, "mortgaged": false},
			{"index": 1, "name": "Sunset Blvd", "type": "property", "group": "brown", "cost": 60, "owner": -1, "houses": 0, "mortgaged": false},
		],
	}

static func test_store_resync_from_projection() -> String:
	var s = Store.new()
	s.resync(_proj())
	if not s.vm["started"]:
		return "store should be started after resync"
	if s.vm["turn"] != 1:
		return "turn should come from turn_player, got %d" % s.vm["turn"]
	if s.vm["pot"] != 300:
		return "pot should come from parking_pot"
	if s.vm["tile_count"] != 2:
		return "tile_count should be the board size, got %d" % s.vm["tile_count"]
	if s.player(1)["name"] != "Bo":
		return "player(1) should be Bo"
	if s.tile(1)["group"] != "brown":
		return "tile(1) should carry its group"
	return ""

static func test_store_resync_emits_changed() -> String:
	var s = Store.new()
	var seen: Array = []
	s.changed.connect(func(keys): seen.append(keys))
	s.resync(_proj())
	if seen.size() != 1:
		return "resync should emit changed exactly once, got %d" % seen.size()
	if not (seen[0] as PackedStringArray).has("players"):
		return "resync should announce 'players'"
	return ""

static func test_store_delta_cash() -> String:
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta([["c", 0, -60]])
	if s.player(0)["money"] != 1440:
		return "delta cash should debit 60, got %d" % s.player(0)["money"]
	s.apply_delta([["c", 1, 25]])
	if s.player(1)["money"] != 1225:
		return "delta cash should credit 25, got %d" % s.player(1)["money"]
	return ""

static func test_store_delta_position() -> String:
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta([["pos", 0, 7]])
	if s.player(0)["pos"] != 7:
		return "position delta not applied, got %d" % s.player(0)["pos"]
	return ""

static func test_store_delta_owner_and_clear() -> String:
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta([["o", 1, 0]])
	if s.tile(1)["owner"] != 0:
		return "ownership delta not applied"
	# null clears ownership (bankruptcy hands tiles back)
	s.apply_delta([["o", 1, null]])
	if s.tile(1)["owner"] != -1:
		return "null ownership should clear to -1, got %d" % s.tile(1)["owner"]
	return ""

static func test_store_delta_houses_mortgage() -> String:
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta([["h", 1, 3], ["m", 1, true]])
	if s.tile(1)["houses"] != 3:
		return "houses delta not applied"
	if s.tile(1)["mortgaged"] != true:
		return "mortgage delta not applied"
	s.apply_delta([["m", 1, false]])
	if s.tile(1)["mortgaged"] != false:
		return "unmortgage delta not applied"
	return ""

static func test_store_delta_bankrupt() -> String:
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta([["out", 1]])
	if not s.player(1)["bankrupt"]:
		return "bankruptcy delta not applied"
	return ""

static func test_store_delta_unknown_is_noop() -> String:
	var s = Store.new()
	s.resync(_proj())
	var before = JSON.stringify(s.vm)
	s.apply_delta([["weird", 0, 1], [], ["c", 999, 5], ["c", 0]])
	var after = JSON.stringify(s.vm)
	if before != after:
		return "unknown/malformed deltas must not change the view model"
	return ""

static func test_store_select_tile_emits_once() -> String:
	var s = Store.new()
	s.resync(_proj())
	var n := [0]
	s.changed.connect(func(_k): n[0] += 1)
	s.select_tile(1)
	s.select_tile(1)   # same value -> no second emit
	if n[0] != 1:
		return "selecting the same tile twice should emit once, got %d" % n[0]
	if s.vm["selected_tile"] != 1:
		return "selected_tile not stored"
	s.select_tile(1)   # engine re-selects after resync
	return ""

static func test_store_lookup_helpers() -> String:
	var s = Store.new()
	s.resync(_proj())
	if not s.player(99).is_empty():
		return "player() for an unknown id should be empty"
	if not s.tile(99).is_empty():
		return "tile() for an unknown index should be empty"
	return ""

# --- LayoutProfile ------------------------------------------------------------

static func test_layout_profiles() -> String:
	if Layout.for_screen(Vector2i(1920, 1080)).id != "wide":
		return "1920x1080 should be 'wide'"
	if Layout.for_screen(Vector2i(1440, 900)).id != "desktop":
		return "1440x900 should be 'desktop'"
	if Layout.for_screen(Vector2i(1024, 768)).id != "compact":
		return "1024x768 should be 'compact'"
	return ""

static func test_layout_compact_by_height() -> String:
	# wide but short -> compact (spec: or height <= 700)
	var p = Layout.for_screen(Vector2i(1920, 600))
	if p.id != "compact":
		return "a <=700px tall window should be compact, got %s" % p.id
	if p.top_height() >= 46:
		return "compact should trim the top bar"
	if p.is_supported() and p.screen.x < Layout.MIN_WIDTH:
		return "widths below %d are unsupported" % Layout.MIN_WIDTH
	var narrow = Layout.for_screen(Vector2i(800, 900))
	if narrow.is_supported():
		return "800px wide should be reported unsupported"
	return ""

static func test_layout_rails() -> String:
	if not Layout.for_screen(Vector2i(950, 900)).rail_left():
		return "left rail should collapse below 1000px"
	if Layout.for_screen(Vector2i(1440, 900)).rail_left():
		return "left rail should stay open at 1440px"
	if not Layout.for_screen(Vector2i(1100, 900)).rail_right():
		return "right rail should collapse below 1180px"
	return ""

static func test_layout_label_degradation() -> String:
	if Layout.label_step(90.0) != 0:
		return "a wide cell should show the full label"
	if Layout.label_step(70.0) != 1:
		return "a mid cell should hide the price"
	if Layout.label_step(50.0) != 2:
		return "a small cell should shrink the font"
	if Layout.label_step(40.0) != 3:
		return "a tiny cell should hide the name (inspector carries it)"
	return ""

# --- UiProfile ----------------------------------------------------------------

static func test_profile_roles() -> String:
	var p = Profile.for_id("player")
	if not p.input_enabled or p.data_source != "player":
		return "player profile should accept input from its own seat"
	var s = Profile.for_id("stream")
	if s.input_enabled:
		return "stream profile must not accept input"
	if s.data_source != "spectator":
		return "stream profile must read the spectator projection"
	if not s.shows_lower_third:
		return "stream profile should show the lower third"
	var a = Profile.for_id("admin")
	if not a.shows_admin_tools or a.data_source != "admin":
		return "admin profile should expose admin tools and data"
	return ""

static func test_profile_infer_from_launch() -> String:
	# owner decision: the role is chosen at launch, never toggled in the UI
	if Profile.infer(true, []).id != "player":
		return "a web launch should be the player profile (WebUI)"
	if Profile.infer(false, ["--stream"]).id != "stream":
		return "--stream should select the stream profile"
	if Profile.infer(false, ["--admin"]).id != "admin":
		return "--admin should select the admin profile"
	if Profile.infer(false, []).id != "admin":
		return "a desktop launch without a flag is the host (admin-capable)"
	return ""

# --- Money --------------------------------------------------------------------

static func test_money_formats() -> String:
	var m = MoneyFmt.make("$", true)
	if m.amount(1500) != "$1,500":
		return "amount(1500) should group: %s" % m.amount(1500)
	if m.amount(-50) != "-$50":
		return "negative amount wrong: %s" % m.amount(-50)
	if m.amount(0) != "$0":
		return "zero amount wrong: %s" % m.amount(0)
	if m.signed(200) != "+$200":
		return "signed credit wrong: %s" % m.signed(200)
	if m.signed(-50) != "-$50":
		return "signed debit wrong: %s" % m.signed(-50)
	return ""

static func test_money_compact() -> String:
	var m = MoneyFmt.make("$")
	if m.compact(25000) != "$25K":
		return "compact(25000) should be $25K, got %s" % m.compact(25000)
	if m.compact(60) != "$60":
		return "compact(60) should stay plain, got %s" % m.compact(60)
	return ""

static func test_money_names() -> String:
	var m = MoneyFmt.make("$")
	if m.name_of("") != "?":
		return "an empty name should fall back to '?'"
	if m.name_of("  Ada  ") != "Ada":
		return "names should be trimmed"
	var long = m.name_of("VeryLongPlayerName", 10)
	if long.length() > 10:
		return "truncated name too long: %s" % long
	return ""

## Regression: the engine logs `cash` for card "collect"/"pay" and card
## landings. Dropping it as "ledger noise" drifted the view model away from the
## projection (caught by tools/ui_contracts_probe.gd on the real engine).
static func test_adapter_cash_event_carries_delta() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "cash", "data": {"player": 2, "amount": 50, "balance": 1550}})
	if ev.is_empty():
		return "a cash event must adapt so its delta is applied"
	if ev["visible"]:
		return "cash must not be a journal line"
	var found := false
	for d in ev["d"]:
		if d[0] == "c" and d[1] == 2 and d[2] == 50:
			found = true
	if not found:
		return "cash should emit a +50 delta: %s" % str(ev["d"])
	return ""

static func test_adapter_balance_correction() -> String:
	var a = Adapter.new()
	# when the engine logs a resulting balance, the delta must be absolute
	var ev = a.adapt({"type": "cash", "data": {"player": 1, "amount": 50, "balance": 1550}})
	var has_cb := false
	for d in ev["d"]:
		if d[0] == "cb" and d[1] == 1 and d[2] == 1550:
			has_cb = true
	if not has_cb:
		return "a logged balance should emit an absolute 'cb' delta: %s" % str(ev["d"])
	# ...and the store must honour it exactly
	var s = Store.new()
	s.resync(_proj())
	s.apply_delta(ev["d"])
	if s.player(1)["money"] != 1550:
		return "store should land on the engine balance 1550, got %d" % s.player(1)["money"]
	return ""

static func test_adapter_pay_event_deltas() -> String:
	var a = Adapter.new()
	var ev = a.adapt({"type": "pay", "data": {"from": 0, "to": 1, "amount": 75, "balance": 1425}})
	if ev.is_empty():
		return "a pay event must adapt for its delta"
	if ev["visible"]:
		return "pay must not be a journal line"
	var debited := false
	var credited := false
	for d in ev["d"]:
		if d[0] == "c" and d[1] == 0 and d[2] == -75:
			debited = true
		if d[0] == "c" and d[1] == 1 and d[2] == 75:
			credited = true
	if not debited or not credited:
		return "pay should move 75 from 0 to 1: %s" % str(ev["d"])
	return ""


# --- stage 7: execution roles --------------------------------------------------

## The role is a property of the LAUNCH, not a switch in the UI (owner decision).
## These lock in both halves: inference, and the fact that nothing can flip it.
static func test_profile_infer_web_is_player() -> String:
	var p = Profile.infer(true, [] as PackedStringArray)
	return "" if p.id == Profile.PLAYER else "web export should be player, got %s" % p.id


static func test_profile_infer_desktop_is_admin() -> String:
	var p = Profile.infer(false, [] as PackedStringArray)
	return "" if p.id == Profile.ADMIN else "a desktop launch should be admin, got %s" % p.id


static func test_profile_infer_stream_flag() -> String:
	var p = Profile.infer(false, PackedStringArray(["--stream"]))
	return "" if p.id == Profile.STREAM else "--stream should be stream, got %s" % p.id


static func test_profile_infer_admin_flag() -> String:
	var p = Profile.infer(false, PackedStringArray(["--admin"]))
	return "" if p.id == Profile.ADMIN else "--admin should be admin, got %s" % p.id


static func test_stream_profile_is_read_only() -> String:
	var p = Profile.for_id(Profile.STREAM)
	if p.input_enabled:
		return "a stream execution must take no input"
	if p.shows_actions:
		return "a stream execution must not show the action bar"
	if p.shows_admin_tools:
		return "a stream execution must expose no admin tools"
	if p.data_source != "spectator":
		return "a stream execution must read the spectator projection"
	return ""


static func test_admin_profile_owns_tools() -> String:
	var p = Profile.for_id(Profile.ADMIN)
	if not p.shows_admin_tools:
		return "an admin execution must expose the admin tools"
	if not p.input_enabled:
		return "an admin execution must accept input"
	return ""


static func test_player_profile_takes_input() -> String:
	var p = Profile.for_id(Profile.PLAYER)
	if not p.input_enabled:
		return "a player execution must accept input"
	if p.data_source != "player":
		return "a player execution reads its own seat projection"
	return ""


static func test_every_role_reports_itself() -> String:
	# a read-only badge replaces the prototype's switcher, so each role must be
	# identifiable without any writable state
	for rid in [Profile.PLAYER, Profile.STREAM, Profile.ADMIN]:
		var p = Profile.for_id(rid)
		if not p.shows_role_badge:
			return "role %s should report itself (read-only badge)" % rid
		if p.id != rid:
			return "for_id(%s) returned %s" % [rid, p.id]
	return ""
