class_name EventMessages
extends RefCounted
## Maps an event-log entry (type + data) to a short human-readable line.
## Pure — scene-free, so it's unit-testable headless and spectator-safe
## (never reads private projection keys).

static func describe(entry: Dictionary) -> String:
	var t: String = entry.get("type", "?")
	var d: Dictionary = entry.get("data", {})
	match t:
		"roll":
			return "%s rolls %d+%d" % [_who(d, "player"), int(d.get("d1", 0)), int(d.get("d2", 0))]
		"move":
			return "%s moves → %d" % [_who(d, "player"), _moved_to(d)]
		"land":
			return "%s lands on tile %d" % [_who(d, "player"), int(d.get("tile", -1))]
		"purchase":
			return "%s buys tile %d ($%d)" % [_who(d, "player"), int(d.get("tile", 0)), int(d.get("cost", 0))]
		"pass":
			return "%s passes tile %d" % [_who(d, "player"), int(d.get("tile", -1))]
		"pay":
			return "%s pays $%d" % [_who(d, "from"), int(d.get("amount", 0))]
		"rent":
			return "%s pays rent" % [_who(d, "from")]
		"build":
			return "%s builds on tile %d" % [_who(d, "player"), int(d.get("tile", 0))]
		"sell":
			return "%s sells from tile %d" % [_who(d, "player"), int(d.get("tile", 0))]
		"mortgage":
			return "%s mortgages tile %d" % [_who(d, "player"), int(d.get("tile", 0))]
		"bankrupt":
			return "%s is bankrupt" % _who(d, "player")
		"jail":
			return "%s goes to jail" % _who(d, "player")
		"go_bonus":
			return "%s collects GO bonus" % _who(d, "player")
		"tax":
			return "%s pays tax" % _who(d, "from")
		"card_draw":
			return "%s draws a card" % _who(d, "player")
		"card_land":
			return "%s card → tile %d" % [_who(d, "player"), int(d.get("tile", -1))]
		"winner":
			if d.has("name"): return "%s WINS!" % str(d["name"])
			return "%s WINS!" % _who(d, "player")
		"trade":
			return "trade complete"
		"auction_win":
			return "%s wins auction of tile %d" % [_who(d, "player"), int(d.get("tile", -1))]
		"auction_start":
			return "auction starts on tile %d" % int(d.get("tile", -1))
		"admin_override":
			return "admin: %s" % _who(d, "op")
		_:
			return "[%s]" % t

## helper — read a name-ish field; ints become p<int>, strings pass through.
static func _who(d: Dictionary, key: String) -> String:
	var v = d.get(key, "?")
	if v is String: return str(v)
	return "p%s" % str(v)

static func _moved_to(d: Dictionary) -> int:
	if d.has("to"): return int(d["to"])
	if d.has("new_pos"): return int(d["new_pos"])
	return -1
