extends RefCounted
## Tests for the modal host (stage 6, spec §6).
##
## The spec's four requirements, and the defects they close:
##   - ONE modal instance: open() is idempotent, never a stack;
##   - the dim dismisses only the informational modals (auction / game-over are
##     protected);
##   - auction buttons follow legal_actions, so only the engine's current bidder
##     gets them (public bids only);
##   - the trade modal offers REAL tiles + cash and refuses an empty offer.

const Modal := preload("res://ui/modal_host.gd")
const SkinMgr := preload("res://visual/skin_manager.gd")
const UiTheme := preload("res://ui/theme.gd")

static func _host():
	# the theme needs a skin before any widget is built
	var sk = SkinMgr.new()
	sk.load_skin("neuro")
	UiTheme.use_skin(sk)
	var h = Modal.new()
	return h


static func _proj() -> Dictionary:
	return {
		"phase": "PURCHASE_WAIT",
		"turn_player": 0,
		"pending": {"type": "purchase", "tile": 1},
		"board": [
			{"index": 0, "name": "Start", "type": "go", "owner": -1, "houses": 0},
			{"index": 1, "name": "Sunset Blvd", "type": "property", "group": "brown",
				"cost": 60, "owner": -1, "houses": 0, "house_cost": 50},
			{"index": 2, "name": "Cedar Ave", "type": "property", "group": "lightblue",
				"cost": 100, "owner": 0, "houses": 0, "house_cost": 50},
			{"index": 3, "name": "Mint Ave", "type": "property", "group": "lightblue",
				"cost": 100, "owner": 1, "houses": 0, "house_cost": 50},
		],
	}


static func _seats() -> Array:
	# seat objects expose pid/name (what the host reads)
	return [
		{"pid": 0, "name": "Ada"},
		{"pid": 1, "name": "Bo"},
	]


static func test_list() -> Array[String]:
	return [
		"test_open_is_idempotent", "test_never_stacks_panels",
		"test_kind_and_is_open", "test_close_clears",
		"test_dim_dismisses_informational", "test_dim_does_not_dismiss_auction",
		"test_dim_does_not_dismiss_game_over", "test_auction_buttons_need_legal",
		"test_auction_spectator_sees_no_buttons", "test_trade_lists_real_tiles",
		"test_trade_rejects_empty_offer", "test_trade_accepts_real_offer",
		"test_trade_response_shows_breakdown", "test_rerender_on_relocale",
		"test_build_buttons_follow_legal"]


static func test_open_is_idempotent() -> String:
	var h = _host()
	h.open("rules", {"text": "hello"})
	var first = h._panel
	# re-opening the SAME kind must update in place, not build a second panel
	h.open("rules", {"text": "world"})
	if h.panel_count() != 1:
		return "re-opening the same modal stacked %d panels" % h.panel_count()
	h.open("message", {"title": "T", "msg": "M"})
	if h.panel_count() != 1:
		return "switching kind stacked %d panels" % h.panel_count()
	h.free()
	return ""


static func test_never_stacks_panels() -> String:
	var h = _host()
	# hammer it: opening many different modals in a row must always leave one
	for k in ["rules", "message", "settings", "rules", "message"]:
		h.open(k, {"text": "x", "title": "t", "msg": "m", "cats": []})
		var n: int = h.panel_count()
		if n > 1:
			return "after opening '%s' there are %d panels" % [k, n]
	h.free()
	return ""


static func test_kind_and_is_open() -> String:
	var h = _host()
	if h.is_open():
		return "a fresh host should not be open"
	h.open("rules", {"text": "x"})
	if not h.is_open():
		return "after open() the host should be open"
	if h.kind() != "rules":
		return "kind should be 'rules', got '%s'" % h.kind()
	h.free()
	return ""


static func test_close_clears() -> String:
	var h = _host()
	h.open("rules", {"text": "x"})
	h.close()
	if h.is_open():
		return "close() left the host open"
	if h.kind() != "":
		return "close() did not clear the kind"
	if h.panel_count() != 0:
		return "close() left %d panels" % h.panel_count()
	h.free()
	return ""


static func test_dim_dismisses_informational() -> String:
	var h = _host()
	for k in ["rules", "trade", "message", "settings"]:
		h.open(k, {"text": "x", "proj": _proj(), "seats": _seats(), "pid": 0,
			"title": "t", "msg": "m", "cats": []})
		if k not in Modal.DISMISSABLE:
			return "'%s' should be dismissable" % k
		h._on_dim_input(_click())
		if h.is_open():
			return "the dim should have closed '%s'" % k
	h.free()
	return ""


static func test_dim_does_not_dismiss_auction() -> String:
	var h = _host()
	h.open("auction", {"proj": _proj(), "seats": _seats(), "legal": []})
	h._on_dim_input(_click())
	if not h.is_open():
		return "a background click must NOT dismiss the auction (spec 6)"
	h.free()
	return ""


static func test_dim_does_not_dismiss_game_over() -> String:
	var h = _host()
	h.open("game_over", {"winner": "Ada", "turns": 3, "capital": 10, "players": 2})
	h._on_dim_input(_click())
	if not h.is_open():
		return "a background click must NOT dismiss game-over (spec 6)"
	h.free()
	return ""


static func test_auction_buttons_need_legal() -> String:
	var h = _host()
	# the engine offers [bid, pass] only to the current bidder
	h.open("auction", {"proj": _auction_proj(), "seats": _seats(), "legal": ["bid", "pass"]})
	var bid_btns := _find_buttons(h, "modal.bid_btn")
	if bid_btns == 0:
		h.free()
		return "with legal [bid,pass] the bid button must be present"
	h.free()
	return ""


static func test_auction_spectator_sees_no_buttons() -> String:
	var h = _host()
	# an empty legal set means the engine is not asking THIS player
	h.open("auction", {"proj": _auction_proj(), "seats": _seats(), "legal": []})
	var bid_btns := _find_buttons(h, "modal.bid_btn")
	var pass_btns := _find_buttons(h, "modal.pass_btn")
	if bid_btns != 0 or pass_btns != 0:
		h.free()
		return "a spectator must get no bid/pass buttons (got %d/%d)" % [bid_btns, pass_btns]
	h.free()
	return ""


static func test_trade_lists_real_tiles() -> String:
	var h = _host()
	var proj := _proj()
	# player 0 owns tile 2 and nothing else, with no houses
	h.open_trade(proj, _seats(), 0)
	var boxes := _collect_checkboxes(h)
	var mine := 0
	for cb in boxes:
		if str(cb.get_meta("tag", "")) == "give":
			mine += 1
	if mine != 1:
		h.free()
		return "the give side should list exactly the 1 tradeable tile player 0 owns, got %d" % mine
	# a tile WITH houses must not be offered (the engine rejects it)
	var proj2 := _proj()
	proj2["board"][2]["houses"] = 2
	h.open_trade(proj2, _seats(), 0)
	var any := false
	for cb in _collect_checkboxes(h):
		if str(cb.get_meta("tag", "")) == "give":
			any = true
	if any:
		h.free()
		return "a tile with houses must not be tradeable"
	h.free()
	return ""


static func test_trade_rejects_empty_offer() -> String:
	var h = _host()
	h.open_trade(_proj(), _seats(), 0)
	var got := []
	h.trade_proposed.connect(func(to, g, gc, w, wc): got.append([to, g, gc, w, wc]))
	# nothing selected and 0 cash -> the host must refuse locally
	h._emit_trade(h._find_recipient(), h._find_spin(0), h._find_spin(1),
		h._find_by_tag("give"), h._find_by_tag("want"), h._find_err())
	if got.size() != 0:
		h.free()
		return "an empty offer must not be proposed"
	h.free()
	return ""


static func test_trade_accepts_real_offer() -> String:
	var h = _host()
	h.open_trade(_proj(), _seats(), 0)
	var got := []
	h.trade_proposed.connect(func(to, g, gc, w, wc): got.append({"to": to, "g": g, "gc": gc, "w": w, "wc": wc}))
	# tick the tile player 0 owns on the give side, and add cash
	for cb in _collect_checkboxes(h):
		if str(cb.get_meta("tag", "")) == "give":
			cb.button_pressed = true
	h._find_spin(0).value = 25
	h._emit_trade(h._find_recipient(), h._find_spin(0), h._find_spin(1),
		h._find_by_tag("give"), h._find_by_tag("want"), h._find_err())
	if got.size() != 1:
		h.free()
		return "a real offer should be emitted (got %d)" % got.size()
	var o: Dictionary = got[0]
	if o["gc"] != 25:
		h.free()
		return "the cash amount was lost: %d" % o["gc"]
	if (o["g"] as Array).size() != 1:
		h.free()
		return "the selected tile was lost: %s" % str(o["g"])
	h.free()
	return ""


static func test_trade_response_shows_breakdown() -> String:
	var h = _host()
	var proj := _proj()
	proj["pending"] = {"type": "trade", "proposer": 0, "recipient": 1,
		"give_tiles": [2], "give_cash": 30, "want_tiles": [3], "want_cash": 0}
	h.open_trade_response(proj, _seats())
	# the body must name the tiles, not just count them
	var text := _all_text(h)
	if not text.contains("Cedar Ave"):
		h.free()
		return "the trade offer should name the offered tile, body=%s" % text
	if not text.contains("30"):
		h.free()
		return "the trade offer should show the cash amount, body=%s" % text
	h.free()
	return ""


static func test_rerender_on_relocale() -> String:
	var h = _host()
	h.open("rules", {"text": "hello"})
	var before = h._panel
	# re-rendering must replace the panel (a fresh node), never leak the old one
	h._on_locale_changed("en")
	if h.panel_count() != 1:
		h.free()
		return "a locale change left %d panels" % h.panel_count()
	if h._panel == before:
		h.free()
		return "a locale change should re-render the modal"
	h.free()
	return ""


static func test_build_buttons_follow_legal() -> String:
	var h = _host()
	var proj := _proj()
	# the engine offers only 'build' at this tile
	h.open_build(2, proj, "Ada", ["roll", "build_house", "sell_house"])
	var enabled := _enabled_label_buttons(h)
	if not enabled.has("act.build"):
		h.free()
		return "the build button should be enabled when build_house is legal"
	# an action missing from legal_actions must be DISABLED
	h.open_build(2, proj, "Ada", ["build_house"])
	var mortgage_enabled := _label_button_disabled(h, "act.mortgage")
	if not mortgage_enabled:
		h.free()
		return "mortgage should be DISABLED when mortgage_property is not legal"
	h.free()
	return ""


# --- helpers ------------------------------------------------------------------

static func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	return ev


static func _auction_proj() -> Dictionary:
	var p := _proj()
	p["pending"] = {"type": "auction", "tile": 1, "high": 70, "high_player": 1, "bidder": 0}
	return p


## All nodes under a host. Uses the host's own depth-first walk (a recursive
## Callable inside a static helper did not traverse, so lookups found nothing).
static func _all(h) -> Array:
	return h.nodes()


static func _find_buttons(h, key: String) -> int:
	var n := 0
	for c in _all(h):
		if c is Button and not (c is CheckBox) and str(c.get_meta("i18n_key", "")) == key:
			n += 1
	return n


static func _collect_checkboxes(h) -> Array:
	var out: Array = []
	for c in _all(h):
		if c is CheckBox:
			out.append(c)
	return out


static func _all_text(h) -> String:
	var parts: Array = []
	for c in _all(h):
		if c is Label:
			parts.append(str((c as Label).text))
		elif c is Button:
			parts.append(str((c as Button).text))
	return " ".join(parts)


## Buttons carry their i18n key as metadata, so a lookup is locale-independent.
static func _button_by_key(h, key: String) -> Button:
	for c in _all(h):
		if c is Button and not (c is CheckBox) and str(c.get_meta("i18n_key", "")) == key:
			return c
	return null


static func _enabled_label_buttons(h) -> Array:
	var out: Array = []
	for c in _all(h):
		if c is Button and not (c is CheckBox) and not (c as Button).disabled:
			out.append(str(c.get_meta("i18n_key", "")))
	return out


static func _label_button_disabled(h, key: String) -> bool:
	var b := _button_by_key(h, key)
	return b != null and b.disabled
