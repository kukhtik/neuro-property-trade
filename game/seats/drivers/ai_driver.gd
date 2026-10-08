extends Node
## Internal AI driver. Every decision it makes is shaped by the seat's CHARACTER
## (seats/ai_persona.gd) — buying, bidding, trading and building all read that
## seat's own numbers instead of one hardcoded policy.
##
## WHY THIS EXISTS: with a single policy for all seats, four AI players behaved
## identically and the economy died — ownership froze, no colour group ever
## completed, no house was ever built, cash grew without bound and the match could
## not end. Character is what makes the seats differ, and differing seats are what
## makes auctions CLOSE and trades actually happen.

const Persona := preload("res://seats/ai_persona.gd")
const TradeEvaluator := preload("res://seats/trade_evaluator.gd")
const TradeNegotiator := preload("res://seats/trade_negotiator.gd")

var engine
var seat

## Look for a trade every Nth decision point.
##
## MEASURED at 3: 4476 proposals produced 197 trades and 4279 declines — 96% refused.
## At 25: ZERO proposals in an entire match, because a look that rarely coincides
## with a completable group never happens.
## The negotiator only offers when it can complete a group, so most looks find
## nothing anyway; checking rarely costs little and stops the flood.
const TRADE_LOOK_EVERY := 8
var _turns := 0

func setup(eng, s) -> void:
	engine = eng
	seat = s


## This seat's character. Falls back to the rotating default when a match never
## assigned one, so an unconfigured seat is never identical to its neighbour.
func persona_id() -> String:
	if seat == null:
		return Persona.TYCOON
	var p: String = str(seat.persona)
	return p if Persona.has(p) else Persona.default_for_index(int(seat.pid))

func act() -> void:
	if engine == null or seat == null:
		return
	var pid: int = seat.pid
	var legal: Array = engine.legal_actions(pid)
	if legal.is_empty():
		return
	var action: String = legal[0]
	var params := {}
	# CHOOSE by priority, do not just take legal[0]. The legal list always starts
	# with "roll", so matching on legal[0] made every other branch — build, trade,
	# mortgage — unreachable code. Measured: a match ran 3000 turns with a completed
	# colour group and built ZERO houses, because the driver never looked at
	# build_house even though the engine offered it.
	if legal.has("build_house"):
		var bt := _build_tile(pid)
		if bt >= 0:
			engine.submit_intent(pid, "build_house", {"tile": bt})
			return
	if legal.has("propose_trade"):
		var offer := _offer(pid)
		if not offer.is_empty():
			engine.submit_intent(pid, "propose_trade", offer)
			return
	match action:
		"bid":
			var d := _decide_bid(pid)
			action = str(d.get("action", "pass"))
			params = d.get("params", {})
		"buy", "pass":
			action = "buy" if _should_buy(pid) else "pass"
		"build_house":
			var bt := _build_tile(pid)
			if bt < 0:
				return   # nothing worth building: let the engine offer something else
			params["tile"] = bt
		"sell_house", "mortgage_property", "unmortgage_property":
			var tiles: Array = engine.player(pid).owned_tiles()
			if tiles.size() == 0:
				return
			params["tile"] = int(tiles[0])
		"propose_trade":
			# Offer a trade that assembles a colour group. This was a stub
			# ("AI does not proactively propose trades this phase"), which left an
			# automated match with no way to complete a group: measured, four AI
			# seats never formed a single set, so nothing was ever built and the
			# game could not end. The negotiator only returns an offer the partner's
			# own evaluator would accept.
			var offer := _offer(pid)
			if offer.is_empty():
				return   # nothing worth proposing: take another action
			params = offer
			action = "propose_trade"
		"respond_trade":
			params["accept"] = TradeEvaluator.accept_with(engine, pid, engine._pending_trade)
		"roll":
			_turns += 1
	engine.submit_intent(pid, action, params)


## What this seat bids, and whether it bids at all.
##
## The ceiling comes from the character: a Tycoon stretches to 2.5x the lot's
## price, a Miser quits at 0.8x. Different ceilings are what let an auction CLOSE —
## and the step size is what stops one auction running thousands of rounds.
func _decide_bid(pid: int) -> Dictionary:
	var high: int = int(engine._pending.get("high", -1))
	var tile: int = int(engine._pending.get("tile", -1))
	var cost: int = int(engine.board.tile_at(tile).get("cost", 0))
	var me = engine.player(pid)
	var who := persona_id()
	var completes: bool = _completes_set(pid, tile)
	var ceiling: int = Persona.bid_ceiling(who, cost, completes)

	var amount: int
	if high == -1:
		amount = maxi(1, int(round(float(cost) * 0.5)))
	else:
		amount = high + Persona.bid_step(who, cost)
	if amount > int(me.money) or amount > ceiling:
		return {"action": "pass", "params": {}}
	return {"action": "bid", "params": {"amount": amount}}


func _should_buy(pid: int) -> bool:
	var tile: int = int(engine._pending.get("tile", -1))
	var cost: int = int(engine.board.tile_at(tile).get("cost", 0))
	var me = engine.player(pid)
	return Persona.will_buy(persona_id(), int(me.money), cost,
		int(engine.settings.starting_cash), _completes_set(pid, tile))


## The cheapest tile worth building on, or -1. The character decides how much cash
## to keep in hand before building.
func _build_tile(pid: int) -> int:
	var who := persona_id()
	var money: int = int(engine.player(pid).money)
	var best := -1
	var best_h := 99
	for t in engine.player(pid).owned_tiles():
		var tile: int = int(t)
		var group: String = String(engine._group_of(tile))
		if group == "" or not engine._owns_set(pid, group):
			continue
		var h: int = engine._houses_on(tile)
		if h >= 5:
			continue
		if engine.settings.even_build and h > engine._set_min_houses(group):
			continue
		var house_cost: int = int(engine.board.tile_at(tile).get("house_cost", 0))
		if not Persona.will_build(who, money, house_cost):
			continue
		if h < best_h:
			best_h = h
			best = tile
	return best


## A trade to propose, or {} when this character does not trade or has nothing to
## offer. The negotiator checks the offer against the RECIPIENT's own evaluator, so
## a doomed proposal is never sent.
func _offer(pid: int) -> Dictionary:
	if not Persona.trades_eagerly(persona_id()):
		return {}
	if _turns % TRADE_LOOK_EVERY != 0:
		return {}
	return TradeNegotiator.choose(engine, pid)


## True when buying `tile` would COMPLETE a colour group for `pid`.
func _completes_set(pid: int, tile: int) -> bool:
	if tile < 0:
		return false
	var group: String = String(engine._group_of(tile))
	if group == "":
		return false
	for other in engine.board.group_tiles(group):
		var ti: int = int(other)
		if ti == tile:
			continue
		if not engine.player(pid).owns(ti):
			return false
	return true
