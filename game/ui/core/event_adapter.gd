class_name EventAdapter
extends RefCounted
## Normalises authoritative engine events into the UI's event schema.
##
## The engine logs its own vocabulary (`purchase`, `pass_on_purchase`,
## `auction_unwon`, `card_draw`, `trade_proposed`, `bankrupt`, `winner`, ...)
## and its fields are NOT uniform: `rent` carries {from,to}, `buy` carries
## {player,cost}, `tax` carries {player,amount}. The UI must not care.
##
## This is the single translation point. Verified against engine.gd's actual
## `log.append(...)` calls (see docs/ui_migration_notes.md §3).
##
## Output schema (per spec §3.2):
##   k      UI event kind ("roll", "buy", "rent", ...)
##   p      actor player id
##   q      second player id (rent payee, trade partner)
##   ti     tile index
##   a, b   numbers (amount, dice faces)
##   c      card id
##   deck   card deck ("chance" | "community")
##   d      UiStore deltas
##   round  round number
##   visible  whether the journal shows it
##   cat    filter category ("money", "buy", ...)
##
## Pure + headless-testable.

## Engine event type -> UI kind. Types absent here are not surfaced to the
## journal (move/land/cash are presentation or accounting noise).
const TYPE_MAP := {
	"setup": "start",
	"roll": "roll",
	"move": "move",
	"teleport": "move",
	"go_bonus": "go",
	"purchase": "buy",
	"rent": "rent",
	"tax": "tax",
	"free_parking": "park",
	"card_draw": "card",
	"card_gain": "card",
	"card_land": "card",
	"card_null": "card",
	"jail": "jail",
	"auction_start": "aucstart",
	"auction_bid": "bid",
	"auction_pass": "pass",
	"auction_win": "aucwin",
	"auction_unwon": "aucnone",
	"build": "build",
	"sell": "sell",
	"mortgage": "mort",
	"unmortgage": "unmort",
	"trade_proposed": "trdoffer",
	"trade": "trade",
	"trade_declined": "trdno",
	"bankrupt": "bank",
	"winner": "over",
}

## UI kind -> journal filter category.
const CATEGORY := {
	"roll": "roll",
	"go": "money", "rent": "money", "tax": "money", "park": "money",
	"buy": "buy",
	"card": "card",
	"aucstart": "auction", "bid": "auction", "pass": "auction",
	"aucwin": "auction", "aucnone": "auction",
	"build": "build", "sell": "build", "mort": "build", "unmort": "build",
	"trdoffer": "trade", "trade": "trade", "trdno": "trade",
}

## Kinds the journal renders (move/land are board effects only).
const VISIBLE := [
	"start", "roll", "go", "buy", "rent", "tax", "park", "card", "jail",
	"aucstart", "bid", "pass", "aucwin", "aucnone",
	"build", "sell", "mort", "unmort",
	"trdoffer", "trade", "trdno", "bank", "over",
]

## Engine types that move money but are NOT journal lines. They must still be
## adapted so their cash delta is applied — the engine logs `cash` for card
## "collect"/"pay" and card landings, and dropping them drifted the view model
## away from the projection.
const MONEY_ONLY := {
	"cash": "cash",
	"pay": "pay",
}

## Engine types that indicate the round counter advanced is NOT derivable from
## a single event — the adapter tracks turn wraparound instead (see adapt()).

var _round := 1
var _last_turn := -1


## Reset the round tracker (new game).
func reset() -> void:
	_round = 1
	_last_turn = -1


## Convert one engine log entry into the UI event dict. Returns an empty dict
## for entry types the UI does not surface (the caller drops those).
func adapt(entry: Dictionary) -> Dictionary:
	var etype: String = str(entry.get("type", ""))
	var data: Dictionary = entry.get("data", {})
	var k: String = ""

	if TYPE_MAP.has(etype):
		k = TYPE_MAP[etype]
	elif MONEY_ONLY.has(etype):
		k = MONEY_ONLY[etype]   # adapts for its deltas, never shown
	else:
		return {}

	var out := {
		"k": k,
		"p": -1, "q": -1, "ti": -1,
		"a": 0, "b": 0,
		"c": "", "deck": "",
		"d": [],
		"round": _round,
		"visible": VISIBLE.has(k),
		"cat": CATEGORY.get(k, "other"),
		"raw": etype,
	}

	_round_track(etype, data, out)
	_fill(etype, k, data, out)
	out["d"] = _deltas(etype, data)
	# absolute correction last, so it wins over any derived amount
	var corr := _balance_correction(data)
	for c in corr:
		out["d"].append(c)
	return out


## Round tracking: the engine does not log a round number, so bump it when the
## turn index wraps back to (or past) the first player.
func _round_track(etype: String, data: Dictionary, out: Dictionary) -> void:
	if etype == "setup":
		_round = 1
		_last_turn = -1
		out["round"] = _round
		return
	if etype == "roll":
		var p := int(data.get("player", -1))
		if _last_turn >= 0 and p == 0 and p <= _last_turn:
			_round += 1
		_last_turn = p
	out["round"] = _round


## Copy engine fields onto the UI schema, absorbing the shape differences.
func _fill(etype: String, k: String, data: Dictionary, out: Dictionary) -> void:
	match etype:
		"setup":
			out["p"] = int(data.get("players", 0))   # used as a count, not a pid
		"roll":
			out["p"] = int(data.get("player", -1))
			out["a"] = int(data.get("d1", 0))
			out["b"] = int(data.get("d2", 0))
		"move", "teleport":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("to", data.get("tile", -1)))
		"go_bonus":
			out["p"] = int(data.get("player", -1))
			out["a"] = int(data.get("amount", 0))
		"purchase":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("cost", 0))
		"rent":
			out["p"] = int(data.get("from", -1))
			out["q"] = int(data.get("to", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("amount", 0))
		"tax":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("amount", 0))
		"free_parking":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("amount", 0))
		"card_draw":
			out["p"] = int(data.get("player", -1))
			out["deck"] = str(data.get("kind", ""))
			out["c"] = _card_id(data)
			out["a"] = int(data.get("value", 0))
		"card_gain", "card_land", "card_null":
			out["p"] = int(data.get("player", -1))
			out["deck"] = str(data.get("kind", ""))
		"jail":
			out["p"] = int(data.get("player", -1))
			out["a"] = int(data.get("amount", 0))   # fine paid, when present
		"auction_start":
			out["ti"] = int(data.get("tile", -1))
		"auction_bid":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("amount", 0))
		"auction_pass":
			out["p"] = int(data.get("player", -1))
		"auction_win":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("amount", 0))
		"auction_unwon":
			out["ti"] = int(data.get("tile", -1))
		"build":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("cost", 0))
			out["b"] = int(data.get("houses", 0))
		"sell":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("refund", 0))
			out["b"] = int(data.get("houses", 0))
		"mortgage":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("loan", 0))
		"unmortgage":
			out["p"] = int(data.get("player", -1))
			out["ti"] = int(data.get("tile", -1))
			out["a"] = int(data.get("owe", 0))
		"trade_proposed", "trade":
			out["p"] = int(data.get("proposer", -1))
			out["q"] = int(data.get("to", data.get("recipient", -1)))
		"trade_declined":
			out["p"] = int(data.get("proposer", -1))
			out["q"] = int(data.get("recipient", -1))
		"bankrupt":
			out["p"] = int(data.get("player", -1))
			out["q"] = int(data.get("creditor", -1))
			out["a"] = int(data.get("cash", 0))
		"winner":
			out["p"] = int(data.get("player", -1))


## A stable card id for i18n lookup: card.<deck>.<id>. The engine logs a
## display name, so slugify it and keep the deck.
func _card_id(data: Dictionary) -> String:
	var deck := str(data.get("kind", "chance"))
	var prefix := "cc" if deck == "community" else "ch"
	var name := str(data.get("name", ""))
	var slug := ""
	for ch in name.to_lower():
		if ch >= "a" and ch <= "z":
			slug += ch
		elif ch >= "0" and ch <= "9":
			slug += ch
		elif slug.length() > 0 and slug[-1] != "_":
			slug += "_"
	slug = slug.strip_edges().trim_suffix("_")
	if slug == "":
		slug = "unknown"
	return "%s_%s" % [prefix, slug]


## Build UiStore deltas from an engine event. The store applies these while the
## presenter animates; a final resync() from the projection is authoritative.
##
## IMPORTANT: several engine money paths do NOT log a `cash` event — card
## "collect"/"pay" call _credit/_charge and only the card_draw is logged, and a
## card that lands you on a taxed/property tile charges you silently. So where
## the engine logs a `balance`, we emit an absolute cash delta from it; that is
## exact and needs no guessing. Only then do we fall back to explicit amounts.
func _deltas(etype: String, data: Dictionary) -> Array:
	var d: Array = []
	match etype:
		"purchase":
			d.append(["c", int(data.get("player", -1)), -int(data.get("cost", 0))])
			d.append(["o", int(data.get("tile", -1)), int(data.get("player", -1))])
		"rent":
			d.append(["c", int(data.get("from", -1)), -int(data.get("amount", 0))])
			d.append(["c", int(data.get("to", -1)), int(data.get("amount", 0))])
		"tax":
			d.append(["c", int(data.get("player", -1)), -int(data.get("amount", 0))])
		"free_parking":
			d.append(["c", int(data.get("player", -1)), int(data.get("amount", 0))])
		"go_bonus":
			d.append(["c", int(data.get("player", -1)), int(data.get("amount", 0))])
		"cash":
			d.append(["c", int(data.get("player", -1)), int(data.get("amount", 0))])
		"pay":
			d.append(["c", int(data.get("from", -1)), -int(data.get("amount", 0))])
			d.append(["c", int(data.get("to", -1)), int(data.get("amount", 0))])
		"jail":
			# entering jail moves the token to the jail tile (index = N/4)
			if str(data.get("reason", "")) == "entered":
				d.append(["pos", int(data.get("player", -1)), 10])
		"move", "teleport":
			d.append(["pos", int(data.get("player", -1)), int(data.get("to", data.get("tile", -1)))])
		"build":
			d.append(["c", int(data.get("player", -1)), -int(data.get("cost", 0))])
			d.append(["h", int(data.get("tile", -1)), int(data.get("houses", 0))])
		"sell":
			d.append(["c", int(data.get("player", -1)), int(data.get("refund", 0))])
			d.append(["h", int(data.get("tile", -1)), int(data.get("houses", 0))])
		"mortgage":
			d.append(["c", int(data.get("player", -1)), int(data.get("loan", 0))])
			d.append(["m", int(data.get("tile", -1)), true])
		"unmortgage":
			d.append(["c", int(data.get("player", -1)), -int(data.get("owe", 0))])
			d.append(["m", int(data.get("tile", -1)), false])
		"auction_win":
			d.append(["c", int(data.get("player", -1)), -int(data.get("amount", 0))])
			d.append(["o", int(data.get("tile", -1)), int(data.get("player", -1))])
		"bankrupt":
			d.append(["out", int(data.get("player", -1))])
	return d


## If the engine logged a post-change `balance`, express the cash as an absolute
## correction. Returns a delta, or an empty array when no balance is present.
## This catches money moved by card effects and card landings that log no `cash`.
func _balance_correction(data: Dictionary) -> Array:
	if not data.has("balance"):
		return []
	var pid := int(data.get("player", -1))
	if pid < 0:
		return []
	return [["cb", pid, int(data["balance"])]]


## Adapt a whole log. Returns only the entries the UI surfaces.
func adapt_all(entries: Array) -> Array:
	reset()
	var out: Array = []
	for entry in entries:
		var ev := adapt(entry)
		if not ev.is_empty():
			out.append(ev)
	return out


## Journal text key for a UI kind (i18n templates live in i18n/data_event.gd).
static func text_key(k: String) -> String:
	return "event." + k
