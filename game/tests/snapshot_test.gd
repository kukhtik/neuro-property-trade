extends RefCounted
## Phase 4 snapshot tests: engine.to_snapshot()/from_snapshot() round-trip and
## the thin core/snapshot.gd JSON file wrapper.

static func test_list() -> Array[String]:
	return [
		"test_roundtrip_setup", "test_roundtrip_purchase_pending",
		"test_roundtrip_auction", "test_roundtrip_trade_pending",
		"test_roundtrip_post_bankruptcy", "test_restore_deterministic_roll",
		"test_snapshot_file_save_load",
		"test_roundtrip_deck_mutation",
	]

static func _make_engine(names: Array = ["Ada", "Bo", "Cyd"]):
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.rng_seed = 424242
	var e = E.new()
	e.setup(s, names)
	return e

static func _assert_same(d1: Dictionary, d2: Dictionary) -> String:
	if d1 != d2:
		return "snapshots differ:\n%s\nvs\n%s" % [str(d1), str(d2)]
	return ""

static func test_roundtrip_setup() -> String:
	var e = _make_engine()
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	return _assert_same(snap, e2.to_snapshot())

static func test_roundtrip_purchase_pending() -> String:
	var e = _make_engine()
	# craft a live mid-turn state: PURCHASE_WAIT on tile 1 after a forced roll
	e.phase = "TURN_START"
	e.turn_player = 0
	e.admin_override("force_dice", {"d1": 1, "d2": 0})   # sum 1 -> lands tile 1 unowned
	var r = e.submit_intent(0, "roll", {})
	if not r.get("ok", false): return "roll failed: %s" % str(r)
	if e.phase != "PURCHASE_WAIT": return "expected PURCHASE_WAIT, got %s" % e.phase
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	return _assert_same(snap, e2.to_snapshot())

static func test_roundtrip_auction() -> String:
	var e = _make_engine(["Ada", "Bo"])
	# land on tile 1, pass -> auction (auctions_on_refusal default true)
	e.phase = "TURN_START"
	e.turn_player = 0
	e.admin_override("force_dice", {"d1": 1, "d2": 0})
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})
	if e.phase != "AUCTION": return "expected AUCTION, got %s" % e.phase
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	return _assert_same(snap, e2.to_snapshot())

static func test_roundtrip_trade_pending() -> String:
	var e = _make_engine()
	e.admin_override("grant_property", {"pid": 0, "tile": 6})
	var tr = e.submit_intent(0, "propose_trade", {"to": 1, "give_tiles": [6], "give_cash": 0, "want_tiles": [], "want_cash": 0})
	if not tr.get("ok", false): return "propose_trade failed: %s" % str(tr)
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	return _assert_same(snap, e2.to_snapshot())

static func test_roundtrip_post_bankruptcy() -> String:
	var e = _make_engine(["Ada", "Bo"])
	# Bo owns both brown + max houses; Ada lands and can't pay -> bankrupt
	e.admin_override("grant_property", {"pid": 1, "tile": 1})
	e.admin_override("grant_property", {"pid": 1, "tile": 3})
	e.admin_override("set_houses", {"tile": 1, "count": 5})
	e.admin_override("set_balance", {"pid": 0, "amount": 50})
	e.phase = "TURN_START"
	e.turn_player = 0
	e.admin_override("force_dice", {"d1": 1, "d2": 0})   # sum 1 -> tile 1, rent 250 > 50
	var r = e.submit_intent(0, "roll", {})
	if not r.get("ok", false): return "roll failed: %s" % str(r)
	if e.phase != "END_GAME": return "expected END_GAME, got %s" % e.phase
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	return _assert_same(snap, e2.to_snapshot())

static func test_restore_deterministic_roll() -> String:
	var e = _make_engine()
	e.admin_override("teleport", {"pid": 0, "tile": 1})
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	# Both engines share the same rng re-seed (settings.rng_seed 424242),
	# so the same next roll draws equal values.
	var r1 = e._next_roll()
	var r2 = e2._next_roll()
	if r1.get("sum", 0) != r2.get("sum", 0) or r1.get("d1", 0) != r2.get("d1", 0):
		return "restored rng diverged: %s vs %s" % [str(r1), str(r2)]
	return ""

static func test_snapshot_file_save_load() -> String:
	var e = _make_engine()
	e.admin_override("set_balance", {"pid": 1, "amount": 999})
	var SnapShot = load("res://core/snapshot.gd")
	var path: String = "user://test_snapshot.json"
	if not SnapShot.save(path, e):
		return "save failed"
	var e2 = SnapShot.load(path)
	if e2 == null:
		return "load failed -> null"
	if e2.player(1).money != 999:
		return "loaded balance want 999 got %d" % e2.player(1).money
	return ""

static func test_roundtrip_deck_mutation() -> String:
	var e = _make_engine()
	# deck_insert/remove mutate the live deck; the snapshot must preserve them
	e.admin_override("deck_insert", {"kind": "community", "card": {"name": "Admin Card", "effect": "collect", "value": 500}})
	e.admin_override("deck_remove", {"kind": "chance", "name": "Dividend"})
	var snap: Dictionary = e.to_snapshot()
	var e2 = e.from_snapshot(snap)
	# inserted card present in restored deck
	var found := false
	for card in e2.decks["community"].cards("community"):
		if card.get("name", "") == "Admin Card":
			found = true
	if not found: return "restored deck should contain inserted Admin Card"
	# removed card absent in restored deck
	for card in e2.decks["chance"].cards("chance"):
		if card.get("name", "") == "Dividend":
			return "restored deck should NOT contain removed Dividend"
	return _assert_same(snap, e2.to_snapshot())
