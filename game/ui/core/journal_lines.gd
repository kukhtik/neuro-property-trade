extends RefCounted
## SG-06 — turns ONE engine event into ONE journal line a human can read.
##
## The journal used to bypass EventAdapter and ask i18n for `event_type.<raw engine type>`:
## rows showed raw vocabulary (`free_parking`, `card_draw`) or fell back to the key itself,
## with no tile names ("клетка 17"), no category tag and no money wording. Here the event
## goes through the adapter (the single translation point, engine vocabulary -> span), then
## through the `jrn.ev.<span>` family with the projection's tile NAMES and seat names.
##
## Output: {who, who_color, text, tag, cat, pid, round} or {} when the journal hides it.

const I18n := preload("res://i18n/i18n.gd")
const AdapterScript := preload("res://ui/core/event_adapter.gd")

var _adapter = AdapterScript.new()


## New match: the adapter's round tracker resets with it.
func reset() -> void:
	_adapter.reset()


## ctx: {"names": {pid: String}, "colors": {pid: Color}, "tiles": {index: String}, "dim": Color}
func line_for(ev: Dictionary, ctx: Dictionary) -> Dictionary:
	var row: Dictionary = _adapter.adapt(ev)
	if row.is_empty() or not bool(row.get("visible", false)):
		return {}
	var k: String = str(row.get("k", ""))
	var text := _text_for(k, row, ctx)
	if text == "":
		return {}
	var pid: int = int(row.get("p", -1))
	var who := ""
	var col: Color = ctx.get("dim", Color(0.62, 0.65, 0.7))
	if k != "start":
		who = _name_of(pid, ctx)
		var colors: Dictionary = ctx.get("colors", {})
		if colors.has(pid):
			col = colors[pid]
	return {
		"who": who,
		"who_color": col,
		"text": text,
		"tag": I18n.t("ty." + str(row.get("cat", "other"))),
		"cat": str(row.get("cat", "other")),
		"pid": pid,
		"round": int(row.get("round", 1)),
	}


func _text_for(k: String, row: Dictionary, ctx: Dictionary) -> String:
	var a := int(row.get("a", 0))
	var b := int(row.get("b", 0))
	var tile := _tile_name(int(row.get("ti", -1)), ctx)
	match k:
		"start":
			return I18n.t("jrn.ev.start", [a])
		"roll":
			return I18n.t("jrn.ev.roll", [a, b])
		"go":
			return I18n.t("jrn.ev.go", [a])
		"buy":
			return I18n.t("jrn.ev.buy", [_tile_or_partner(tile, row, ctx), a])
		"rent":
			return I18n.t("jrn.ev.rent", [a, _tile_or_partner(tile, row, ctx)])
		"tax":
			return I18n.t("jrn.ev.tax", [a])
		"park":
			return I18n.t("jrn.ev.park", [a])
		"card":
			return I18n.t("jrn.ev.card")
		"jail":
			return I18n.t("jrn.ev.jail")
		"aucstart":
			return I18n.t("jrn.ev.aucstart", [tile])
		"bid":
			return I18n.t("jrn.ev.bid", [a])
		"pass":
			return I18n.t("jrn.ev.pass")
		"aucwin":
			return I18n.t("jrn.ev.aucwin", [tile, a])
		"aucnone":
			return I18n.t("jrn.ev.aucnone", [tile])
		"build":
			return I18n.t("jrn.ev.build", [tile])
		"sell":
			return I18n.t("jrn.ev.sell", [tile])
		"mort":
			return I18n.t("jrn.ev.mort", [tile, a])
		"unmort":
			return I18n.t("jrn.ev.unmort", [tile, a])
		"trdoffer":
			# E-1/D9: a trade line must answer "what is being offered". It used to name only the
			# partner, so the reader saw "offers a trade: Neuro" and learned nothing about the
			# deal. The composition now renders in TILE NAMES (never indices).
			return I18n.t("jrn.ev.trdoffer", [_name_of(int(row.get("q", -1)), ctx),
				terms(row, ctx)])
		"trade":
			# the executed deal: both sides, in names. When the engine could not carry a side's
			# composition (an older log), _terms says so rather than printing a bare "trade".
			return I18n.t("jrn.ev.trade", [_name_of(int(row.get("p", -1)), ctx),
				_name_of(int(row.get("q", -1)), ctx), terms(row, ctx)])
		"trdno":
			return I18n.t("jrn.ev.trdno")
		"bank":
			return I18n.t("jrn.ev.bank")
		"over":
			return I18n.t("jrn.ev.over")
	return ""


## E-1: the composition of a trade, in words - "Harbor Stn, Palm Row + $200 <> $150 + Chest".
##
## ONE renderer for three surfaces (the journal line, the incoming-trade modal and the toast), so
## the reader cannot be told three different things about one deal. The arrow points from what the
## proposer GIVES to what they ASK; empty sides collapse to "nothing" rather than to an empty gap,
## because "$0 + 0 тайл(а)" is arithmetic where a sentence belongs.
func terms(row: Dictionary, ctx: Dictionary) -> String:
	var give := _side(int(row.get("gvc", 0)), row.get("giv", []), ctx)
	var want := _side(int(row.get("wnc", 0)), row.get("wnt", []), ctx)
	return I18n.t("trade.terms", [give, want])


## One side of a deal: tile names first (the thing a player recognises), then the cash.
func _side(cash: int, tiles: Variant, ctx: Dictionary) -> String:
	var names: Array = []
	if tiles is Array:
		for t in (tiles as Array):
			names.append(_tile_name(int(t), ctx))
	var parts: Array = []
	if not names.is_empty():
		parts.append(", ".join(names))
	if cash > 0:
		parts.append("$%d" % cash)
	if parts.is_empty():
		return I18n.t("trade.nothing")
	return " + ".join(parts)


## A tile the projection knows by name; when the adapter could not carry the index (rare
## engine shapes), fall back to the trade partner's name so the line still reads human.
func _tile_or_partner(tile: String, row: Dictionary, ctx: Dictionary) -> String:
	if tile != "":
		return tile
	return _name_of(int(row.get("q", -1)), ctx)


func _tile_name(ti: int, ctx: Dictionary) -> String:
	if ti < 0:
		return ""
	var tiles: Dictionary = ctx.get("tiles", {})
	return str(tiles.get(ti, ""))


func _name_of(pid: int, ctx: Dictionary) -> String:
	if pid < 0:
		return ""
	var names: Dictionary = ctx.get("names", {})
	if names.has(pid):
		return str(names[pid])
	return "P%d" % pid
