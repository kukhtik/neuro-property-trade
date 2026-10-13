extends RefCounted

const EM := preload("res://visual/event_messages.gd")

static func test_list() -> Array[String]:
	return ["test_describe_roll", "test_describe_uses_player_name",
			"test_describe_purchase", "test_describe_pay",
			"test_spectator_no_private", "test_unknown_type_falls_through",
			"test_auction_win_player_field"]

## The brief forbids raw seat tags: a user must see a NAME, never "p0"/"p2"
## (defect #7). With no engine bound there is no name to look up, so the
## fallback is a 1-based seat label, never the raw index.
static func test_describe_roll() -> String:
	var s := EM.describe({"type": "roll", "data": {"player": 2, "d1": 4, "d2": 3}})
	if s.contains("p2"): return "roll line must NOT print the raw seat tag: %s" % s
	if not s.contains("P3"): return "roll should fall back to a seat label: %s" % s
	if not s.contains("4") or not s.contains("3"): return "roll should show dice: %s" % s
	return ""


## With an engine bound the line carries the player's real name.
static func test_describe_uses_player_name() -> String:
	var eng = _fake_engine(["Ada", "Bo", "Cy", "Di"])
	EM.bind_engine(eng)
	var s := EM.describe({"type": "roll", "data": {"player": 2, "d1": 4, "d2": 3}})
	EM.bind_engine(null)
	if not s.contains("Cy"):
		return "roll should name the player: %s" % s
	if s.contains("p2") or s.contains("P3"):
		return "the name must replace the seat tag entirely: %s" % s
	return ""


static func _fake_engine(names: Array):
	# only `players[i].name` is read by the formatter
	var players: Array = []
	for n in names:
		players.append({"name": n})
	return {"players": players}

static func test_describe_purchase() -> String:
	var s := EM.describe({"type": "purchase", "data": {"player": 0, "tile": 5, "cost": 200}})
	if not s.contains("$200"): return "should show cost: %s" % s
	return ""

static func test_describe_pay() -> String:
	var s := EM.describe({"type": "pay", "data": {"from": 1, "amount": 50}})
	if not s.contains("50"): return "pay line should show amount: %s" % s
	return ""

static func test_spectator_no_private() -> String:
	var s := EM.describe({"type": "roll", "data": {"player": 0, "d1": 1, "d2": 1}})
	if s.contains("private") or s.contains("jail_card"):
		return "overlay must not leak private info: %s" % s
	return ""

static func test_unknown_type_falls_through() -> String:
	var s := EM.describe({"type": "weird", "data": {}})
	if not s.contains("weird"): return "unknown type should echo: %s" % s
	return ""


static func test_auction_win_player_field() -> String:
	var s := EM.describe({"type": "auction_win", "data": {"player": 3, "tile": 7, "amount": 120}})
	# it must read the 'player' field (not silently fall back to a default) and
	# must not print the raw seat tag
	if s.contains("p3"): return "auction win must NOT print the raw seat tag: %s" % s
	if not s.contains("P4"): return "auction win should use the 'player' field: %s" % s
	return ""
