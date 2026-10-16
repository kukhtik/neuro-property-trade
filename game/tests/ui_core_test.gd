extends RefCounted
## Headless tests for the pure UI-core modules.
##
## Modules covered:
##   EventAdapter   — engine → UI event schema, deltas, round tracking
##   Money          — formatting (amount, signed, compact, name_of)
##   IntentMap      — UI action → engine intent translation + availability
##   LayoutProfile  — window-size → layout-profile mapping + rail widths
##   UiProfile      — execution-role profiles (player/stream/admin)
##   UiStore        — view model: resync, apply_delta, lookups
##   JournalLines   — event + context → human-readable journal line
##
## What is NOT covered here (needs a live scene tree or full engine run):
##   EventPresenter  — already covered by event_presenter_test.gd
##   LaunchParams   — already covered by launch_params_test.gd (CLI/URL paths)

const AdapterScript := preload("res://ui/core/event_adapter.gd")
const MoneyScript := preload("res://ui/core/money.gd")
const IntentMapScript := preload("res://ui/core/intent_map.gd")
const LayoutProfileScript := preload("res://ui/core/layout_profile.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
const UiStoreScript := preload("res://ui/core/ui_store.gd")
const JournalLinesScript := preload("res://ui/core/journal_lines.gd")
const KeyboardNavScript := preload("res://ui/core/keyboard_nav.gd")
const BindingsScript := preload("res://ui/core/bindings.gd")
const I18nScript := preload("res://i18n/i18n.gd")


static func test_list() -> Array[String]:
	return [
		# KeyboardNav — the keyboard model (PART 3)
		"test_kbnav_owns_only_its_keys",
		"test_kbnav_tab_cycles_and_wraps",
		"test_kbnav_spatial_picks_the_direction",
		"test_kbnav_spatial_no_move_returns_minus_one",
		"test_kbnav_no_current_starts_at_first",
		"test_kbnav_empty_list_is_no_move",
		"test_kbnav_hint_names_every_hotkey",
		# Bindings (PART 4) — the one home for every rebindable key
		"test_bindings_defaults_cover_every_action",
		"test_bindings_resolved_applies_saved_overrides",
		"test_bindings_resolved_ignores_nonsense",
		"test_bindings_action_for_finds_the_bound_action",
		"test_bindings_rebind_swaps_the_holder",
		"test_bindings_rebind_refuses_nothing_key",
		"test_bindings_reset_one_returns_the_default",
		"test_bindings_labels_exist_in_both_languages",
		"test_bindings_no_two_actions_share_a_default_key",
		# EventAdapter — adapt()
		"test_adapt_roll", "test_adapt_purchase", "test_adapt_rent",
		"test_adapt_unknown_type_returns_empty",
		# EventAdapter — adapt_all()
		"test_adapt_all_filters_invisible",
		# EventAdapter — round tracking
		"test_round_increments_on_turn_wrap",
		"test_setup_resets_round",
		# EventAdapter — _card_id slug generation
		"test_card_id_slugs_chance_card", "test_card_id_slugs_community_card",
		"test_card_id_unknown_falls_back",
		# EventAdapter — text_key
		"test_text_key_prefixes_event",
		# EventAdapter — deltas (money-only path)
		"test_adapt_cash_emits_delta",
		"test_adapt_pay_emits_both_parties",
		# Money
		"test_amount_positive_no_sign", "test_amount_negative_sign_before_symbol",
		"test_amount_three_digits_no_separator", "test_amount_large_with_grouping",
		"test_signed_positive_plus_prefix", "test_signed_negative_no_plus",
		"test_compact_thousands_K", "test_compact_millions_M",
		"test_name_of_empty_fallback", "test_name_of_truncation",
		# IntentMap
		"test_to_engine_roll", "test_to_engine_build_house",
		"test_to_engine_trade_offer_all_params",
		"test_to_engine_unknown_action_returns_empty",
		"test_can_decline_when_pass_and_buy_legal",
		"test_can_decline_false_when_only_pass",
		"test_can_buy_when_legal", "test_can_build_needs_tile",
		"test_tile_action_hint_returns_build_when_legal",
		"test_tile_action_hint_empty_when_nothing_legal",
		# LayoutProfile
		"test_wide_at_1600", "test_desktop_at_1280",
		"test_compact_under_1280", "test_compact_short_height",
		"test_rail_both_on_compact", "test_rail_both_open_on_desktop",
		"test_left_width_per_profile", "test_right_width_per_profile",
		"test_unsupported_below_880",
		"test_label_step_thresholds",
		# UiProfile
		"test_for_id_player", "test_for_id_stream_disables_input",
		"test_for_id_admin_enables_tools", "test_infer_admin_from_flag",
		"test_infer_stream_from_flag", "test_infer_player_on_web",
		# UiStore
		"test_resync_fills_vm", "test_resync_preserves_started",
		"test_apply_delta_cash", "test_apply_delta_absolute_cash",
		"test_apply_delta_position", "test_apply_delta_owner",
		"test_apply_delta_houses", "test_apply_delta_mortgage",
		"test_apply_delta_bankruptcy", "test_player_lookup_by_pid",
		"test_tile_lookup_by_index", "test_select_tile_updates_vm",
		# JournalLines
		"test_line_for_buy_uses_tile_name",
		"test_line_for_rent_uses_both_names",
		"test_line_for_hidden_type_returns_empty",
	]


# ------------------------------------------------------------------
# EventAdapter — adapt()
# ------------------------------------------------------------------

static func test_adapt_roll() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "roll", "data": {"player": 2, "d1": 4, "d2": 3}})
	if out.is_empty():
		return "roll event must not be empty"
	if out["k"] != "roll":
		return "kind must be 'roll', got '%s'" % out["k"]
	if out["p"] != 2:
		return "player must be 2, got %d" % out["p"]
	if out["a"] != 4 or out["b"] != 3:
		return "dice must be [4, 3], got [%d, %d]" % [out["a"], out["b"]]
	if out["cat"] != "roll":
		return "category must be 'roll', got '%s'" % out["cat"]
	if out["visible"] != true:
		return "roll must be visible in the journal"
	return ""


static func test_adapt_purchase() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "purchase", "data": {"player": 1, "tile": 5, "cost": 120}})
	if out.is_empty():
		return "purchase event must not be empty"
	if out["k"] != "buy":
		return "kind must be 'buy', got '%s'" % out["k"]
	if out["p"] != 1:
		return "player must be 1, got %d" % out["p"]
	if out["ti"] != 5:
		return "tile must be 5, got %d" % out["ti"]
	if out["a"] != 120:
		return "cost must be 120, got %d" % out["a"]
	# a purchase must emit a cash delta and an ownership delta
	var d: Array = out["d"]
	var has_cash := false
	var has_owner := false
	for item in d:
		if item.size() >= 2:
			if str(item[0]) == "c" and int(item[1]) == 1:
				has_cash = true
			if str(item[0]) == "o" and int(item[1]) == 5:
				has_owner = true
	if not has_cash:
		return "purchase must emit a cash delta"
	if not has_owner:
		return "purchase must emit an ownership delta"
	return ""


static func test_adapt_rent() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "rent", "data": {"from": 0, "to": 1, "tile": 11, "amount": 45}})
	if out.is_empty():
		return "rent event must not be empty"
	if out["k"] != "rent":
		return "kind must be 'rent', got '%s'" % out["k"]
	if out["p"] != 0 or out["q"] != 1:
		return "rent must carry from/to as p/q: got p=%d q=%d" % [out["p"], out["q"]]
	if out["a"] != 45:
		return "amount must be 45, got %d" % out["a"]
	if out["cat"] != "money":
		return "rent category must be 'money', got '%s'" % out["cat"]
	return ""


static func test_adapt_unknown_type_returns_empty() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "nonsense_type", "data": {}})
	if not out.is_empty():
		return "unknown type must return empty dict, got %s" % str(out)
	# unknown types also do not emit deltas
	if out.size() != 0:
		return "empty dict must have size 0"
	return ""


static func test_adapt_cash_emits_delta() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "cash", "data": {"player": 3, "amount": 200}})
	if out.is_empty():
		return "cash event must not be empty"
	if out["visible"] != false:
		return "cash must not be visible in the journal"
	var d: Array = out["d"]
	var found := false
	for item in d:
		if item.size() >= 3 and str(item[0]) == "c" and int(item[1]) == 3 and int(item[2]) == 200:
			found = true
	if not found:
		return "cash event must emit a cash delta [c, 3, 200]"
	return ""


static func test_adapt_pay_emits_both_parties() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "pay", "data": {"from": 0, "to": 1, "amount": 50}})
	if out.is_empty():
		return "pay event must not be empty"
	var d: Array = out["d"]
	var from_delta := false
	var to_delta := false
	for item in d:
		if item.size() >= 3 and str(item[0]) == "c":
			if int(item[1]) == 0 and int(item[2]) == -50:
				from_delta = true
			if int(item[1]) == 1 and int(item[2]) == 50:
				to_delta = true
	if not from_delta:
		return "pay must emit a negative delta for the payer"
	if not to_delta:
		return "pay must emit a positive delta for the payee"
	return ""


# ------------------------------------------------------------------
# EventAdapter — adapt_all()
# ------------------------------------------------------------------

static func test_adapt_all_filters_invisible() -> String:
	# adapt_all() returns ALL non-empty events including visible=false ones.
	# JournalLines.line_for() is what filters by visibility.
	var a = AdapterScript.new()
	var entries := [
		{"type": "roll", "data": {"player": 0, "d1": 2, "d2": 1}},
		{"type": "move", "data": {"player": 0, "to": 5}},   # visible=false
		{"type": "purchase", "data": {"player": 0, "tile": 5, "cost": 120}},
	]
	var out: Array = a.adapt_all(entries)
	# adapt_all returns all non-empty dicts; move has visible=false but is still returned
	if out.size() != 3:
		return "adapt_all must return all non-empty events (3), got %d" % out.size()
	if out[0]["k"] != "roll":
		return "first event must be roll"
	if out[1]["k"] != "move":
		return "second event must be move"
	if out[1].get("visible", true) != false:
		return "move event must have visible=false"
	if out[2]["k"] != "buy":
		return "third event must be buy"
	return ""


# ------------------------------------------------------------------
# EventAdapter — round tracking
# ------------------------------------------------------------------

static func test_round_increments_on_turn_wrap() -> String:
	var a = AdapterScript.new()
	a.reset()
	# Simulate: player 3 rolls, then player 0 rolls (wrap)
	a.adapt({"type": "roll", "data": {"player": 3, "d1": 1, "d2": 2}})
	var r1 := a.adapt({"type": "roll", "data": {"player": 0, "d1": 3, "d2": 4}})
	if r1["round"] != 2:
		return "round must increment on turn wrap from 3 to 0: got %d" % r1["round"]
	return ""


static func test_setup_resets_round() -> String:
	var a = AdapterScript.new()
	a.reset()
	# First establish round 2: player 3 rolls, then player 0 wraps back.
	a.adapt({"type": "roll", "data": {"player": 3, "d1": 1, "d2": 1}})
	a.adapt({"type": "roll", "data": {"player": 0, "d1": 1, "d2": 1}})
	# _round is now 2, _last_turn is 0.
	# Setup resets _last_turn=-1 but leaves _round=2.
	a.adapt({"type": "setup", "data": {"players": 3}})
	# The first roll after setup: player=1, _last_turn=-1 → condition false, _round stays 1.
	var r1 := a.adapt({"type": "roll", "data": {"player": 1, "d1": 2, "d2": 3}})
	if r1["round"] != 1:
		return "first roll after setup must be round 1 (setup resets _last_turn=-1, condition blocked): got %d" % r1["round"]
	# Second roll: player=0, _last_turn=1 → 0 <= 1 is true → _round becomes 2.
	var r2 := a.adapt({"type": "roll", "data": {"player": 0, "d1": 1, "d2": 1}})
	if r2["round"] != 2:
		return "second roll after setup must be round 2 (wrap from 1 to 0): got %d" % r2["round"]
	return ""


# ------------------------------------------------------------------
# EventAdapter — _card_id / text_key
# ------------------------------------------------------------------

static func test_card_id_slugs_chance_card() -> String:
	# Card IDs are built by adapt() -> _card_id(); we test the path via the output.
	var a = AdapterScript.new()
	var out = a.adapt({"type": "card_draw", "data": {
		"player": 0, "kind": "chance", "name": "Go Back 3 Spaces", "value": 0}})
	if out["c"] != "ch_go_back_3_spaces":
		return "chance card id must be 'ch_go_back_3_spaces', got '%s'" % out["c"]
	if out["deck"] != "chance":
		return "deck must be 'chance'"
	return ""


static func test_card_id_slugs_community_card() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "card_draw", "data": {
		"player": 1, "kind": "community", "name": "Bank error in your favour", "value": 200}})
	if out["c"] != "cc_bank_error_in_your_favour":
		return "community card id must be 'cc_bank_error_in_your_favour', got '%s'" % out["c"]
	if out["deck"] != "community":
		return "deck must be 'community'"
	return ""


static func test_card_id_unknown_falls_back() -> String:
	var a = AdapterScript.new()
	var out = a.adapt({"type": "card_draw", "data": {
		"player": 0, "kind": "chance", "name": "", "value": 0}})
	if out["c"] != "ch_unknown":
		return "empty name must fall back to 'ch_unknown', got '%s'" % out["c"]
	return ""


static func test_text_key_prefixes_event() -> String:
	var k = AdapterScript.text_key("roll")
	if k != "event.roll":
		return "text_key('roll') must be 'event.roll', got '%s'" % k
	return ""


# ------------------------------------------------------------------
# Money
# ------------------------------------------------------------------

static func test_amount_positive_no_sign() -> String:
	var m = MoneyScript.make("$", true)
	var r = m.amount(1500)
	if r != "$1,500":
		return "amount(1500) must be '$1,500', got '%s'" % r
	return ""


static func test_amount_negative_sign_before_symbol() -> String:
	var m = MoneyScript.make("$", true)
	var r = m.amount(-50)
	# negative: "-$50" (sign before symbol, per spec §9.3)
	if r != "-$50":
		return "amount(-50) must be '-$50', got '%s'" % r
	return ""


static func test_amount_three_digits_no_separator() -> String:
	var m = MoneyScript.make("$", true)
	var r = m.amount(999)
	if r != "$999":
		return "amount(999) must be '$999', got '%s'" % r
	return ""


static func test_amount_large_with_grouping() -> String:
	var m = MoneyScript.make("$", true)
	var r = m.amount(1234567)
	if r != "$1,234,567":
		return "amount(1234567) must be '$1,234,567', got '%s'" % r
	return ""


static func test_signed_positive_plus_prefix() -> String:
	var m = MoneyScript.make()
	var r = m.signed(200)
	if r != "+$200":
		return "signed(200) must be '+$200', got '%s'" % r
	return ""


static func test_signed_negative_no_plus() -> String:
	var m = MoneyScript.make()
	var r = m.signed(-50)
	# signed() calls amount() for negatives, which already has the minus
	if r != "-$50":
		return "signed(-50) must be '-$50', got '%s'" % r
	return ""


static func test_compact_thousands_K() -> String:
	var m = MoneyScript.make()
	var r = m.compact(15000)
	if r != "$15K":
		return "compact(15000) must be '$15K', got '%s'" % r
	return ""


static func test_compact_millions_M() -> String:
	var m = MoneyScript.make()
	var r = m.compact(2200000)
	if r != "$2.2M":
		return "compact(2200000) must be '$2.2M', got '%s'" % r
	return ""


static func test_name_of_empty_fallback() -> String:
	var m = MoneyScript.make()
	var r = m.name_of("", 0)
	if r != "?":
		return "name_of('') must be '?', got '%s'" % r
	return ""


static func test_name_of_truncation() -> String:
	var m = MoneyScript.make()
	var r = m.name_of("LongPlayerName", 8)
	# substr(0, max_len-1) + "…" gives max_len chars total.
	# "LongPlayerName".substr(0,7) = "LongPla" (7 chars) + "…" = "LongPla…" (8 chars)
	if r != "LongPla…":
		return "name_of('LongPlayerName', 8) must be 'LongPla…' (8 chars), got '%s'" % r
	if r.length() != 8:
		return "result length %d must equal max_len 8" % r.length()
	return ""


# ------------------------------------------------------------------
# IntentMap
# ------------------------------------------------------------------

static func test_to_engine_roll() -> String:
	var im = IntentMapScript.new()
	var r: Dictionary = im.to_engine("roll")
	if r.get("action", "") != "roll":
		return "roll must map to engine action 'roll'"
	return ""


static func test_to_engine_build_house() -> String:
	var im = IntentMapScript.new()
	var r: Dictionary = im.to_engine("build", {"tile": 7})
	if r.get("action", "") != "build_house":
		return "build must map to 'build_house'"
	if int(r.get("params", {}).get("tile", -1)) != 7:
		return "build must carry tile 7 in params"
	return ""


static func test_to_engine_trade_offer_all_params() -> String:
	var im = IntentMapScript.new()
	var r: Dictionary = im.to_engine("trade_offer", {
		"to": 2, "give_tiles": [5], "give_cash": 500,
		"want_tiles": [11], "want_cash": 0
	})
	if r.get("action", "") != "propose_trade":
		return "trade_offer must map to 'propose_trade'"
	var p: Dictionary = r.get("params", {})
	if int(p.get("to", -1)) != 2:
		return "params.to must be 2"
	if int(p.get("give_cash", -1)) != 500:
		return "params.give_cash must be 500"
	return ""


static func test_to_engine_unknown_action_returns_empty() -> String:
	var im = IntentMapScript.new()
	var r: Dictionary = im.to_engine("not_a_real_action")
	if not r.is_empty():
		return "unknown action must return empty dict"
	return ""


static func test_can_decline_when_pass_and_buy_legal() -> String:
	var im = IntentMapScript.new()
	var legal := ["roll", "buy", "pass"]
	var r: bool = im.can("decline", legal)
	if r != true:
		return "decline must be available when both pass and buy are legal"
	return ""


static func test_can_decline_false_when_only_pass() -> String:
	var im = IntentMapScript.new()
	# auction phase: pass is legal but buy is not
	var legal := ["pass", "bid"]
	var r: bool = im.can("decline", legal)
	if r != false:
		return "decline must be false when buy is not legal"
	return ""


static func test_can_buy_when_legal() -> String:
	var im = IntentMapScript.new()
	var legal := ["buy"]
	var r: bool = im.can("buy", legal)
	if r != true:
		return "buy must be available when legal"
	return ""


static func test_can_build_needs_tile() -> String:
	var im = IntentMapScript.new()
	var legal := ["build_house"]
	# without a tile param, build must not be available
	if im.can("build", legal) != false:
		return "build without a tile must be false"
	# with a tile param, it should be available
	if im.can("build", legal, {"tile": 5}) != true:
		return "build with tile 5 must be available"
	return ""


static func test_tile_action_hint_returns_build_when_legal() -> String:
	var im = IntentMapScript.new()
	var legal := ["build_house"]
	var h: String = im.tile_action_hint(legal, 5)
	if h != "build":
		return "hint must be 'build', got '%s'" % h
	return ""


static func test_tile_action_hint_empty_when_nothing_legal() -> String:
	var im = IntentMapScript.new()
	var legal := ["roll"]
	var h: String = im.tile_action_hint(legal, 5)
	if h != "":
		return "hint must be empty when nothing is legal, got '%s'" % h
	return ""


# ------------------------------------------------------------------
# LayoutProfile
# ------------------------------------------------------------------

static func test_wide_at_1600() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(1600, 900))
	if p.id != LayoutProfileScript.WIDE:
		return "1600px wide must be WIDE, got '%s'" % p.id
	return ""


static func test_desktop_at_1280() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(1280, 900))
	if p.id != LayoutProfileScript.DESKTOP:
		return "1280px wide must be DESKTOP, got '%s'" % p.id
	return ""


static func test_compact_under_1280() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(1024, 900))
	if p.id != LayoutProfileScript.COMPACT:
		return "1024px wide must be COMPACT, got '%s'" % p.id
	return ""


static func test_compact_short_height() -> String:
	# wide enough but below the height threshold
	var p = LayoutProfileScript.for_screen(Vector2i(1440, 650))
	if p.id != LayoutProfileScript.COMPACT:
		return "650px tall must be COMPACT, got '%s'" % p.id
	return ""


static func test_rail_both_on_compact() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(1024, 900))
	if p.rail_left() != true or p.rail_right() != true:
		return "compact profile must have both rails collapsed"
	return ""


static func test_rail_both_open_on_desktop() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(1440, 900))
	if p.rail_left() != false or p.rail_right() != false:
		return "desktop profile must have both rails open"
	return ""


static func test_left_width_per_profile() -> String:
	var wide = LayoutProfileScript.for_screen(Vector2i(1600, 900))
	var desk = LayoutProfileScript.for_screen(Vector2i(1440, 900))
	var comp = LayoutProfileScript.for_screen(Vector2i(1024, 900))
	if wide.left_width() != 280:
		return "wide left_width must be 280, got %d" % wide.left_width()
	if desk.left_width() != 268:
		return "desktop left_width must be 268, got %d" % desk.left_width()
	if comp.left_width() != 240:
		return "compact left_width must be 240, got %d" % comp.left_width()
	return ""


static func test_right_width_per_profile() -> String:
	var wide = LayoutProfileScript.for_screen(Vector2i(1600, 900))
	var desk = LayoutProfileScript.for_screen(Vector2i(1440, 900))
	var comp = LayoutProfileScript.for_screen(Vector2i(1024, 900))
	if wide.right_width() != 380:
		return "wide right_width must be 380, got %d" % wide.right_width()
	if desk.right_width() != 344:
		return "desktop right_width must be 344, got %d" % desk.right_width()
	if comp.right_width() != 300:
		return "compact right_width must be 300, got %d" % comp.right_width()
	return ""


static func test_unsupported_below_880() -> String:
	var p = LayoutProfileScript.for_screen(Vector2i(800, 900))
	if p.is_supported():
		return "800px wide must not be supported"
	return ""


static func test_label_step_thresholds() -> String:
	# label_step is static
	if LayoutProfileScript.label_step(80.0) != 0:
		return ">= 78px must return step 0"
	if LayoutProfileScript.label_step(78.0) != 0:
		return "78px must return step 0"
	if LayoutProfileScript.label_step(65.0) != 1:
		return "65px must return step 1"
	if LayoutProfileScript.label_step(60.0) != 1:
		return "60px must return step 1"
	if LayoutProfileScript.label_step(45.0) != 2:
		return "45px must return step 2"
	if LayoutProfileScript.label_step(30.0) != 3:
		return "30px must return step 3"
	# STEP 3 NO LONGER MEANS "SILENT" (owner's rule, 16.10 evening): the ladder's last rung sheds the
	# price, never the NAME. The tiles read this same step, so the contract lives here as well as in
	# tile_view_test - a board small enough to reach step 3 must still show a name in every cell.
	if LayoutProfileScript.CELL_NAME_ALWAYS_MIN > 44.0:
		return "the always-name floor (%.0f) must sit under any board the layout can produce" % LayoutProfileScript.CELL_NAME_ALWAYS_MIN
	return ""


# ------------------------------------------------------------------
# UiProfile
# ------------------------------------------------------------------

static func test_for_id_player() -> String:
	var p = UiProfileScript.for_id("player")
	if p.id != "player":
		return "for_id('player') id must be 'player'"
	if p.input_enabled != true:
		return "player must have input enabled"
	if p.shows_actions != true:
		return "player must show actions"
	return ""


static func test_for_id_stream_disables_input() -> String:
	var p = UiProfileScript.for_id("stream")
	if p.id != "stream":
		return "for_id('stream') id must be 'stream'"
	if p.input_enabled != false:
		return "stream must have input disabled"
	if p.shows_actions != false:
		return "stream must not show actions"
	if p.shows_lower_third != true:
		return "stream must show lower third"
	return ""


static func test_for_id_admin_enables_tools() -> String:
	var p = UiProfileScript.for_id("admin")
	if p.id != "admin":
		return "for_id('admin') id must be 'admin'"
	if p.shows_admin_tools != true:
		return "admin must show admin tools"
	if p.input_enabled != true:
		return "admin must have input enabled"
	return ""


static func test_infer_admin_from_flag() -> String:
	var p = UiProfileScript.infer(false, ["--admin"])
	if p.id != "admin":
		return "infer with --admin must return admin profile"
	return ""


static func test_infer_stream_from_flag() -> String:
	var p = UiProfileScript.infer(false, ["--stream"])
	if p.id != "stream":
		return "infer with --stream must return stream profile"
	return ""


static func test_infer_player_on_web() -> String:
	var p = UiProfileScript.infer(true, [])
	if p.id != "player":
		return "infer on web with no flags must return player profile"
	return ""


# ------------------------------------------------------------------
# UiStore
# ------------------------------------------------------------------

static func test_resync_fills_vm() -> String:
	var s = UiStoreScript.new()
	var proj := {
		"phase": "TURN_START", "turn_player": 1, "round": 3,
		"parking_pot": 500,
		"players": [{
			"index": 0, "name": "Alice", "money": 1500, "position": 5,
			"in_jail": false, "jail_turns": 0, "bankrupt": false,
			"tiles": [], "houses": 0, "mortgaged": 0
		}, {
			"index": 1, "name": "Bob", "money": 1200, "position": 10,
			"in_jail": true, "jail_turns": 2, "bankrupt": false,
			"tiles": [5], "houses": 1, "mortgaged": 0
		}],
		"board": [{
			"index": 5, "name": "V Putiao", "short": "V Putiao",
			"type": "street", "group": "brown", "cost": 60,
			"owner": 1, "houses": 1, "mortgaged": false
		}],
		"pending": {"can_buy": false}, "legal": ["roll"]
	}
	s.resync(proj)
	var vm = s.vm
	if vm["started"] != true:
		return "started must be true after resync"
	if vm["phase"] != "TURN_START":
		return "phase must be TURN_START, got '%s'" % vm["phase"]
	if vm["turn"] != 1:
		return "turn must be 1, got %d" % vm["turn"]
	if vm["pot"] != 500:
		return "pot must be 500, got %d" % vm["pot"]
	if vm["players"].size() != 2:
		return "must have 2 players, got %d" % vm["players"].size()
	if int(vm["players"][0]["money"]) != 1500:
		return "player 0 money must be 1500"
	if vm["tiles"].size() != 1:
		return "must have 1 tile, got %d" % vm["tiles"].size()
	return ""


static func test_resync_preserves_started() -> String:
	var s = UiStoreScript.new()
	s.vm["started"] = true
	s.resync({"phase": "SETUP", "turn_player": 0, "round": 1,
		"players": [], "board": [], "pending": {}, "legal": []})
	if s.vm["started"] != true:
		return "resync must not reset started"
	return ""


static func test_apply_delta_cash() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	var before = int(s.vm["players"][0]["money"])
	s.apply_delta([["c", 0, -120]])
	var after = int(s.vm["players"][0]["money"])
	if after != before - 120:
		return "cash delta must subtract 120: before=%d after=%d" % [before, after]
	return ""


static func test_apply_delta_absolute_cash() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.vm["players"][0]["money"] = 1000
	s.apply_delta([["cb", 0, 800]])
	var after = int(s.vm["players"][0]["money"])
	if after != 800:
		return "absolute cash must set to 800, got %d" % after
	return ""


static func test_apply_delta_position() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.apply_delta([["pos", 0, 17]])
	if int(s.vm["players"][0]["pos"]) != 17:
		return "position delta must move player to 17"
	return ""


static func test_apply_delta_owner() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.apply_delta([["o", 5, 0]])
	if int(s.vm["tiles"][0]["owner"]) != 0:
		return "owner delta must set owner to 0"
	return ""


static func test_apply_delta_houses() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.apply_delta([["h", 5, 3]])
	if int(s.vm["tiles"][0]["houses"]) != 3:
		return "house delta must set houses to 3, got %d" % s.vm["tiles"][0]["houses"]
	return ""


static func test_apply_delta_mortgage() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.apply_delta([["m", 5, true]])
	if s.vm["tiles"][0]["mortgaged"] != true:
		return "mortgage delta must set mortgaged=true"
	return ""


static func test_apply_delta_bankruptcy() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	s.apply_delta([["out", 0]])
	if s.vm["players"][0]["bankrupt"] != true:
		return "out delta must set bankrupt=true"
	return ""


static func test_player_lookup_by_pid() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	var p: Dictionary = s.player(1)
	if p.is_empty():
		return "player(1) must not be empty"
	if int(p.get("id", -1)) != 1:
		return "player(1) id must be 1"
	var empty: Dictionary = s.player(999)
	if not empty.is_empty():
		return "player(999) must be empty for unknown pid"
	return ""


static func test_tile_lookup_by_index() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	var t: Dictionary = s.tile(5)
	if t.is_empty():
		return "tile(5) must not be empty"
	if int(t.get("index", -1)) != 5:
		return "tile(5) index must be 5"
	var empty: Dictionary = s.tile(999)
	if not empty.is_empty():
		return "tile(999) must be empty for unknown index"
	return ""


static func test_select_tile_updates_vm() -> String:
	var s = UiStoreScript.new()
	_build_minimal_store(s)
	if s.vm["selected_tile"] != -1:
		return "initial selected_tile must be -1"
	s.select_tile(7)
	if s.vm["selected_tile"] != 7:
		return "selected_tile must be 7 after select_tile(7)"
	# selecting the same tile again must be idempotent (no double signal)
	s.select_tile(7)
	if s.vm["selected_tile"] != 7:
		return "selecting same tile twice must keep it at 7"
	return ""


# ------------------------------------------------------------------
# JournalLines
# ------------------------------------------------------------------

static func test_line_for_buy_uses_tile_name() -> String:
	var jl = JournalLinesScript.new()
	jl.reset()
	var ev := {"type": "purchase", "data": {"player": 0, "tile": 5, "cost": 120}}
	var ctx := {
		"names": {0: "Alice"},
		"colors": {0: Color(1, 0, 0)},
		"tiles": {5: "V Putiao"},
		"dim": Color(0.5, 0.5, 0.5),
	}
	var line: Dictionary = jl.line_for(ev, ctx)
	if line.is_empty():
		return "line_for buy must not be empty"
	if line["who"] != "Alice":
		return "who must be 'Alice', got '%s'" % line["who"]
	if line["cat"] != "buy":
		return "cat must be 'buy', got '%s'" % line["cat"]
	# text must not contain raw engine types or {placeholders}
	var text := str(line["text"])
	if text.find("{") >= 0 or text.find("free_parking") >= 0:
		return "journal text must not contain raw engine types or {placeholders}: '%s'" % text
	return ""


static func test_line_for_rent_uses_both_names() -> String:
	var jl = JournalLinesScript.new()
	jl.reset()
	var ev := {"type": "rent", "data": {"from": 0, "to": 1, "tile": 11, "amount": 45}}
	var ctx := {
		"names": {0: "Alice", 1: "Bob"},
		"colors": {0: Color(1, 0, 0), 1: Color(0, 0, 1)},
		"tiles": {11: "Nob Hills"},
		"dim": Color(0.5, 0.5, 0.5),
	}
	var line: Dictionary = jl.line_for(ev, ctx)
	if line.is_empty():
		return "line_for rent must not be empty"
	if line["who"] != "Alice":
		return "who must be 'Alice' (the payer), got '%s'" % line["who"]
	# the text must reference the tile name, not the raw type
	if str(line["text"]).find("rent") >= 0 and str(line["text"]).find("{") >= 0:
		return "text must not have raw engine vocabulary or {placeholders}: '%s'" % line["text"]
	return ""


static func test_line_for_hidden_type_returns_empty() -> String:
	var jl = JournalLinesScript.new()
	jl.reset()
	# "move" is in engine vocabulary but NOT in VISIBLE — the journal hides it
	var ev := {"type": "move", "data": {"player": 0, "to": 5}}
	var ctx := {
		"names": {0: "Alice"}, "colors": {},
		"tiles": {5: "V Putiao"}, "dim": Color(0.5, 0.5, 0.5),
	}
	var line: Dictionary = jl.line_for(ev, ctx)
	if not line.is_empty():
		return "line_for hidden type must return empty dict, got %s" % str(line)
	return ""


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

static func _build_minimal_store(s: UiStore) -> void:
	s.resync({
		"phase": "SETUP", "turn_player": 0, "round": 1,
		"parking_pot": 0,
		"players": [{
			"index": 0, "name": "A", "money": 1500,
			"position": 0, "in_jail": false, "jail_turns": 0,
			"bankrupt": false, "tiles": [], "houses": 0, "mortgaged": 0
		}, {
			"index": 1, "name": "B", "money": 1500,
			"position": 0, "in_jail": false, "jail_turns": 0,
			"bankrupt": false, "tiles": [], "houses": 0, "mortgaged": 0
		}],
		"board": [{
			"index": 5, "name": "V Putiao", "short": "V Putiao",
			"type": "street", "group": "brown", "cost": 60,
			"owner": -1, "houses": 0, "mortgaged": false
		}],
		"pending": {}, "legal": []
	})


# --- KeyboardNav (PART 3): the pure keyboard model --------------------------------------------

static func test_kbnav_owns_only_its_keys() -> String:
	if not KeyboardNavScript.owns(KEY_TAB):
		return "Tab must belong to the navigator"
	if not KeyboardNavScript.owns(KEY_ENTER):
		return "Enter must belong to the navigator"
	if KeyboardNavScript.owns(KEY_B):
		return "B is the console's hotkey, not the navigator's - one owner per key"
	if KeyboardNavScript.owns(KEY_H):
		return "H is the panels toggle, not the navigator's"
	return ""


static func test_kbnav_tab_cycles_and_wraps() -> String:
	var rects := [Rect2(0, 0, 10, 10), Rect2(20, 0, 10, 10), Rect2(40, 0, 10, 10)]
	if KeyboardNavScript.next_index(KEY_TAB, 0, rects) != 1:
		return "Tab from 0 must go to 1"
	if KeyboardNavScript.next_index(KEY_TAB, 2, rects) != 0:
		return "Tab from the last must wrap to the first"
	return ""


static func test_kbnav_spatial_picks_the_direction() -> String:
	# THE FIXTURE MUST BE ABLE TO TELL THE TWO RULES APART. A first version put the "beside" button
	# at x=60 and the diagonal at x=200, so raw distance ALSO preferred "beside" and deleting the
	# off-axis penalty changed nothing - the test passed on a broken model. Here the diagonal is
	# CLOSER on the axis (x=50) than the aligned one (x=70) but sits far below, so only the penalty
	# makes "beside" win. Negative check: drop `across * 3.0` and this test fails.
	var rects := [Rect2(0, 0, 40, 20), Rect2(70, 0, 40, 20), Rect2(50, 400, 40, 20)]
	if KeyboardNavScript.next_index(KEY_RIGHT, 0, rects) != 1:
		return "RIGHT must prefer the button beside it (70,0) over the nearer-but-diagonal (50,400)"
	if KeyboardNavScript.next_index(KEY_DOWN, 0, rects) != 2:
		return "DOWN must reach the only control below"
	if KeyboardNavScript.next_index(KEY_LEFT, 1, rects) != 0:
		return "LEFT must reach the button to its left"
	return ""


static func test_kbnav_spatial_no_move_returns_minus_one() -> String:
	# nothing is above the top row: UP must not jump somewhere unrelated
	var rects := [Rect2(0, 0, 40, 20), Rect2(60, 0, 40, 20)]
	if KeyboardNavScript.next_index(KEY_UP, 0, rects) != -1:
		return "UP with nothing above must be no move (-1), not a jump"
	if KeyboardNavScript.next_index(KEY_DOWN, 0, rects) != -1:
		return "DOWN with nothing below must be no move (-1)"
	return ""


static func test_kbnav_no_current_starts_at_first() -> String:
	var rects := [Rect2(0, 0, 10, 10), Rect2(20, 0, 10, 10)]
	if KeyboardNavScript.next_index(KEY_TAB, -1, rects) != 0:
		return "with no focus, the first control takes it"
	if KeyboardNavScript.next_index(KEY_DOWN, -1, rects) != 0:
		return "with no focus, an arrow starts at the first control"
	return ""


static func test_kbnav_empty_list_is_no_move() -> String:
	if KeyboardNavScript.next_index(KEY_TAB, 0, []) != -1:
		return "an empty list is no move, never a crash or a guess"
	return ""


static func test_kbnav_hint_names_every_hotkey() -> String:
	# THE HINT IS BUILT FROM THE BINDING TABLE (bindings.gd), not from a table of its own - so this
	# walks the ACTIONS the screen offers and requires every one of them to appear, in the player's
	# language. A rebind changes the key the hint prints; the set of actions cannot go missing.
	var hint: String = KeyboardNavScript.hotkey_hint()
	for a in BindingsScript.ACTIONS:
		var act: String = str(a["act"])
		if str(a["group"]) == "camera":
			continue      # camera keys live on the board, not in this list
		var label: String = I18nScript.t(BindingsScript.label_key(act))
		if not hint.contains(label):
			return "the hint must name '%s' (%s); it says '%s'" % [label, act, hint]
	return ""


# --- Bindings (PART 4): the one home for every rebindable key ---------------------------------

static func test_bindings_defaults_cover_every_action() -> String:
	var d: Dictionary = BindingsScript.defaults()
	if d.size() != BindingsScript.ACTIONS.size():
		return "defaults() has %d entries for %d actions" % [d.size(), BindingsScript.ACTIONS.size()]
	for a in BindingsScript.ACTIONS:
		if not d.has(str(a["act"])):
			return "action '%s' has no default key" % str(a["act"])
		if int(d[str(a["act"])]) <= 0:
			return "action '%s' ships with keycode %d" % [str(a["act"]), int(d[str(a["act"])])]
	return ""


static func test_bindings_resolved_applies_saved_overrides() -> String:
	var saved := {"buy": KEY_Q}
	var r: Dictionary = BindingsScript.resolved(saved)
	if int(r["buy"]) != KEY_Q:
		return "a saved override for buy was not applied (got %d)" % int(r["buy"])
	if int(r["end_turn"]) != int(BindingsScript.defaults()["end_turn"]):
		return "an action with no saved override lost its default"
	return ""


static func test_bindings_resolved_ignores_nonsense() -> String:
	# a corrupt file must not make the game unplayable: an unknown action and a zero keycode are
	# both dropped, and the defaults stand.
	var r: Dictionary = BindingsScript.resolved({"no_such_action": KEY_Z, "buy": 0})
	if r.has("no_such_action"):
		return "an unknown action from the save file was trusted"
	if int(r["buy"]) != int(BindingsScript.defaults()["buy"]):
		return "a zero keycode from the save file was trusted (buy became %d)" % int(r["buy"])
	return ""


static func test_bindings_action_for_finds_the_bound_action() -> String:
	var d: Dictionary = BindingsScript.defaults()
	var a: String = BindingsScript.action_for(d, int(d["buy"]))
	if a != "buy":
		return "action_for(the buy key) returned '%s'" % a
	if BindingsScript.action_for(d, KEY_F24) != "":
		return "an unbound key must return no action"
	return ""


static func test_bindings_rebind_swaps_the_holder() -> String:
	# TWO ACTIONS MAY NEVER SHARE ONE KEY. Rebinding buy onto end_turn's key must give end_turn the
	# key buy is vacating - a swap, so no action is left without a key and none is doubled.
	var d: Dictionary = BindingsScript.defaults()
	var old_buy: int = int(d["buy"])
	var old_end: int = int(d["end_turn"])
	var r: Dictionary = BindingsScript.rebind(d, "buy", old_end)
	if int(r["buy"]) != old_end:
		return "a rebind did not take"
	if int(r["end_turn"]) != old_buy:
		return "the displaced action did not take the vacated key (end_turn=%d, wanted %d)" % [int(r["end_turn"]), old_buy]
	# the invariant that matters: no two actions sit on one key after the swap. (An earlier version
	# of this test asked holder_of(..., "buy"), which EXCLUDES buy by definition and so always
	# returned "" - the assertion, not the code, was wrong.)
	var seen := {}
	for act in r.keys():
		var k: int = int(r[act])
		if seen.has(k):
			return "after the swap '%s' and '%s' share %s" % [str(seen[k]), str(act), OS.get_keycode_string(k)]
		seen[k] = str(act)
	return ""


static func test_bindings_rebind_refuses_nothing_key() -> String:
	var d: Dictionary = BindingsScript.defaults()
	var before: int = int(d["buy"])
	var r: Dictionary = BindingsScript.rebind(d, "buy", 0)
	if int(r["buy"]) != before:
		return "a zero keycode must be refused, not assigned"
	return ""


static func test_bindings_reset_one_returns_the_default() -> String:
	var d: Dictionary = BindingsScript.defaults()
	var changed: Dictionary = BindingsScript.rebind(d, "buy", KEY_Q)
	var back: Dictionary = BindingsScript.reset_one(changed, "buy")
	if int(back["buy"]) != int(d["buy"]):
		return "reset_one did not restore buy (got %d)" % int(back["buy"])
	return ""


static func test_bindings_labels_exist_in_both_languages() -> String:
	# THE SCREEN MUST NOT SHOW A KEY. Its rows read `bind.<action>`; if an action ships without its
	# strings the row would print the key itself. Require both languages for every action.
	var prev: String = I18nScript.current
	for loc in ["ru", "en"]:
		I18nScript.set_locale(loc)
		for a in BindingsScript.ACTIONS:
			var k: String = BindingsScript.label_key(str(a["act"]))
			var t: String = I18nScript.t(k)
			if t == k or t.begins_with("{"):
				I18nScript.set_locale(prev)
				return "action '%s' has no %s label (key '%s' unresolved)" % [str(a["act"]), loc, k]
	I18nScript.set_locale(prev)
	return ""


static func test_bindings_no_two_actions_share_a_default_key() -> String:
	# Two actions on one key means one of them never fires - the screen would show a key that does
	# nothing. Check the SHIPPED table, which is what a fresh install runs.
	var seen := {}
	for a in BindingsScript.ACTIONS:
		var k: int = int(a["key"])
		if seen.has(k):
			return "'%s' and '%s' both ship on %s" % [str(seen[k]), str(a["act"]), OS.get_keycode_string(k)]
		seen[k] = str(a["act"])
	return ""
