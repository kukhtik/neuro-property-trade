class_name EventMessages
extends RefCounted
## Maps an event-log entry (type + data) to a short human-readable line.
## Pure — scene-free, so it's unit-testable headless and spectator-safe
## (never reads private projection keys). P5: wording is localized through the
## I18n dictionary in the current locale, so journal + overlay + toast agree.

const I18n := preload("res://i18n/i18n.gd")

static func describe(entry: Dictionary) -> String:
	var t: String = entry.get("type", "?")
	var d: Dictionary = entry.get("data", {})
	match t:
		"roll":
			return I18n.t("event.roll", [_who(d, "player"), int(d.get("d1", 0)), int(d.get("d2", 0))])
		"move":
			return I18n.t("event.move", [_who(d, "player"), _moved_to(d)])
		"land":
			return I18n.t("event.land", [_who(d, "player"), int(d.get("tile", -1))])
		"purchase":
			return I18n.t("event.purchase", [_who(d, "player"), int(d.get("tile", 0)), int(d.get("cost", 0))])
		"pass":
			return I18n.t("event.pass", [_who(d, "player"), int(d.get("tile", -1))])
		"pay":
			return I18n.t("event.pay", [_who(d, "from"), int(d.get("amount", 0))])
		"rent":
			return I18n.t("event.rent", [_who(d, "from")])
		"build":
			return I18n.t("event.build", [_who(d, "player"), int(d.get("tile", 0))])
		"sell":
			return I18n.t("event.sell", [_who(d, "player"), int(d.get("tile", 0))])
		"mortgage":
			return I18n.t("event.mortgage", [_who(d, "player"), int(d.get("tile", 0))])
		"bankrupt":
			return I18n.t("event.bankrupt", [_who(d, "player")])
		"jail":
			return I18n.t("event.jail", [_who(d, "player")])
		"go_bonus":
			return I18n.t("event.go_bonus", [_who(d, "player")])
		"tax":
			return I18n.t("event.tax", [_who(d, "from")])
		"card_draw":
			return I18n.t("event.card_draw", [_who(d, "player")])
		"card_land":
			return I18n.t("event.card_land", [_who(d, "player"), int(d.get("tile", -1))])
		"winner":
			if d.has("name"):
				return I18n.t("event.winner", [str(d["name"])])
			return I18n.t("event.winner", [_who(d, "player")])
		"trade":
			return I18n.t("event.trade")
		"auction_win":
			return I18n.t("event.auction_win", [_who(d, "player"), int(d.get("tile", -1))])
		"auction_start":
			return I18n.t("event.auction_start", [int(d.get("tile", -1))])
		"admin_override":
			return I18n.t("event.admin_override", [_who(d, "op")])
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
