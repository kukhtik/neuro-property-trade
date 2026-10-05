class_name IntentMap
extends RefCounted
## The single mapping between UI actions and the engine's intent vocabulary.
##
## The engine accepts (verified against engine.gd submit_intent):
##   roll | buy | pass | pay | use_card
##   build_house{tile} | sell_house{tile}
##   mortgage_property{tile} | unmortgage_property{tile}
##   propose_trade{to, give_tiles, give_cash, want_tiles, want_cash}
##   respond_trade{accept}
##   bid{amount} | pass   (auction; the engine decides whose bid it is)
##
## The UI never re-implements a rule: availability comes from legal_actions,
## and `can()` here only narrows that set for presentation (e.g. a build button
## needs a selected tile). The engine remains authoritative.
##
## Pure + headless-testable.

## UI action -> engine action.
const MAP := {
	"roll": "roll",
	"buy": "buy",
	"decline": "pass",
	"end": "",              # no engine call: the engine ends the turn itself
	"build": "build_house",
	"sell": "sell_house",
	"mortgage": "mortgage_property",
	"unmortgage": "unmortgage_property",
	"trade_open": "",       # opens the modal; no intent
	"trade_offer": "propose_trade",
	"trade_accept": "respond_trade",
	"trade_reject": "respond_trade",
	"auction_bid": "bid",
	"auction_pass": "pass",
	"jail_pay": "pay",
	"jail_card": "use_card",
}

## UI actions that carry a {tile} param.
const TILE_ACTIONS := ["build", "sell", "mortgage", "unmortgage"]


## Translate a UI action + params into the engine call, or return {} when the
## action is UI-only (trade_open), engine-owned (end), or unknown.
## Returns {"action": String, "params": Dictionary}.
func to_engine(ui_action: String, params: Dictionary = {}) -> Dictionary:
	if not MAP.has(ui_action):
		return {}
	var engine_action: String = MAP[ui_action]
	if engine_action == "":
		return {}
	var out: Dictionary = {}

	match ui_action:
		"build", "sell", "mortgage", "unmortgage":
			out["tile"] = int(params.get("tile", -1))
		"auction_bid":
			out["amount"] = int(params.get("amount", 0))
		"trade_offer":
			out["to"] = int(params.get("to", -1))
			out["give_tiles"] = _int_array(params.get("give_tiles", []))
			out["give_cash"] = int(params.get("give_cash", 0))
			out["want_tiles"] = _int_array(params.get("want_tiles", []))
			out["want_cash"] = int(params.get("want_cash", 0))
		"trade_accept":
			out["accept"] = true
		"trade_reject":
			out["accept"] = false
	return {"action": engine_action, "params": out}


## Is this UI action currently offered by the engine?
## `legal` is engine.legal_actions(pid). `extra` carries presentation context
## (e.g. {"tile": selected}) that narrows the set further.
func can(ui_action: String, legal: Array, extra: Dictionary = {}) -> bool:
	if ui_action == "end":
		# the engine advances the turn from any non-decision phase
		return not legal.is_empty() and not legal.has("buy") and not legal.has("bid")
	if ui_action == "trade_open":
		return legal.has("propose_trade")
	if ui_action == "decline":
		return legal.has("pass") and legal.has("buy")
	if ui_action == "auction_bid":
		return legal.has("bid")
	if ui_action == "auction_pass":
		return legal.has("pass") and not legal.has("buy")
	if not MAP.has(ui_action):
		return false
	var engine_action: String = MAP[ui_action]
	if engine_action == "":
		return false
	if not legal.has(engine_action):
		return false
	# a tile-scoped action also needs a chosen tile
	if TILE_ACTIONS.has(ui_action):
		var tile: int = int(extra.get("tile", -1))
		if tile < 0:
			return false
		# the engine validates ownership/even-build; we only check a tile exists
	return true


## The UI action that a plain click on a tile should offer next, if any.
## Used to pick the primary button label; never a rule decision.
func tile_action_hint(legal: Array, tile: int) -> String:
	for a in ["build", "sell", "mortgage", "unmortgage"]:
		if can(a, legal, {"tile": tile}):
			return a
	return ""


func _int_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			out.append(int(x))
	return out
