extends RefCounted

const EM := preload("res://visual/event_messages.gd")

static func test_list() -> Array[String]:
	return ["test_describe_roll", "test_describe_purchase", "test_describe_pay",
			"test_spectator_no_private", "test_unknown_type_falls_through",
			"test_auction_win_player_field"]

static func test_describe_roll() -> String:
	var s := EM.describe({"type": "roll", "data": {"player": 2, "d1": 4, "d2": 3}})
	if not s.contains("p2"): return "roll line should mention player: %s" % s
	if not s.contains("4") or not s.contains("3"): return "roll should show dice: %s" % s
	return ""

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
	if not s.contains("p3"): return "auction win should use 'player' field: %s" % s
	return ""
