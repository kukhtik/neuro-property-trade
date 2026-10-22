extends RefCounted
## Headless tests for the LIVE UI-core modules — every one of them is preloaded by the product.
##
## Modules covered:
##   EventAdapter   — engine → UI event schema, deltas, round tracking
##   Money          — formatting (amount, signed, compact, name_of)
##   LayoutProfile  — window-size → layout-profile mapping + rail widths
##   UiProfile      — execution-role profiles (player/stream/admin)
##   JournalLines   — event + context → human-readable journal line
##   KeyboardNav    — the keyboard model: Tab/arrow focus, the hotkey hint
##   Bindings       — the one home for every rebindable key
##
## What is NOT covered here (needs a live scene tree or full engine run):
##   LaunchParams   — already covered by launch_params_test.gd (CLI/URL paths)
##
## Split out of `ui_core_test.gd` when the unused UiStore / EventPresenter / IntentMap
## architecture was deleted (438 lines, no product consumer). Their tests went with them;
## every test that exercises a module the product actually imports is preserved here.

const AdapterScript := preload("res://ui/core/event_adapter.gd")
const MoneyScript := preload("res://ui/core/money.gd")
const LayoutProfileScript := preload("res://ui/core/layout_profile.gd")
const UiProfileScript := preload("res://ui/core/ui_profile.gd")
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
		# the collapse control on the side panels names itself (owner, 17.10)
		"test_rail_tip_names_the_panel_and_the_action",
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
	# R-15: there is only ONE rail now (right: journal + inspector). The left rail was removed
	# because the panno's players zone carries its glance layer - so the test asks for the rail
	# that exists, and for the left one to be gone.
	var p = LayoutProfileScript.for_screen(Vector2i(1024, 900))
	if p.rail_right() != true:
		return "compact profile must have the right rail collapsed"
	if p.rail_left() != false:
		return "the left rail was removed by R-15, the profile still reports one"
	return ""


static func test_rail_both_open_on_desktop() -> String:
	# THE RULE THIS USED TO PIN WAS HARMLESS AT ITS OWN SIZE AND WRONG ABOVE IT.
	#
	# It asserted that a 1440x900 desktop keeps both rails OPEN. At 1440x900 that changes nothing: the
	# ring is height-capped at 764px whether the panels take 612px or 96px. But the rule generalised
	# the OTHER way too - a 1600x1200 window is also "desktop", so the panels stayed open there and
	# the ring was cut to 972px by the COLUMN, where rails would have let it reach its full 1048px.
	#
	# So the rule is now "the panels never cost the ring its size", and that is what is asserted - at
	# the size where it was hidden (1600x1200) as well as at the size where it never showed.
	var p = LayoutProfileScript.for_screen(Vector2i(1600, 1200))
	if not p.rail_right():
		return "at 1600x1200 the panels must rail: open, they cut the ring to the column width (972px) where rails give it its full 1048px - the board is a square, so the column is what binds"
	# the compact profile rails for its own reason (there is no room for docks at all)
	var c = LayoutProfileScript.for_screen(Vector2i(880, 600))
	if not c.rail_right():
		return "the compact profile must rail the right dock"
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


# --- the panel collapse control names itself -------------------------------------------------

static func test_rail_tip_names_the_panel_and_the_action() -> String:
	# The owner: "не просто кнопку оставлять, а кнопку с подписью что это". A collapsed rail is a
	# 48px strip; a tooltip that says only "collapse/expand" does not say WHICH panel comes back, and
	# the old one was a hard-coded Russian string (so an English reader got Russian).
	#
	# This asserts the CONTRACT the rail builds its tooltip from, without instantiating the widget:
	# both keys exist in both locales, and each names an action rather than repeating the word panel.
	var prev: String = I18nScript.current
	var seen := {}
	for loc in ["ru", "en"]:
		I18nScript.set_locale(loc)
		for k in ["rail.expand", "rail.collapse"]:
			var t: String = I18nScript.t(k)
			if t == k or t.begins_with("{"):
				I18nScript.set_locale(prev)
				return "no %s string for '%s' - the rail would show the raw key" % [loc, k]
			if seen.has(k) and seen[k] == t:
				I18nScript.set_locale(prev)
				return "'%s' reads the same in ru and en ('%s') - one of them is untranslated" % [k, t]
			seen[k] = t
	I18nScript.set_locale(prev)
	if seen["rail.expand"] == seen["rail.collapse"]:
		return "expand and collapse must not read identically ('%s')" % seen["rail.expand"]
	return ""
