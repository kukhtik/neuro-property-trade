extends RefCounted
## Chooses a trade an AI seat should PROPOSE.
##
## WHY IT EXISTS: the AI could already ANSWER a trade (`trade_evaluator`) but never
## offered one — `ai_driver` had `"propose_trade": return  # AI does not
## proactively propose trades this phase`. That is fine for a game with humans at
## the table and fatal for an automated one: measured over 6000 plies, four AI
## seats spread the colour groups between them, NO group ever completed
## (`sets_at_end=0` despite `build_house` being legal 5451 times), so no houses
## were ever built, rent stayed at the base rate, every seat's cash grew without
## bound and the match could never reach game-over.
##
## Trades are the mechanism that assembles a colour group in a multiplayer game.
## Humans and Neuro do it; the AI now does too.
##
## The offer is built to be ACCEPTED: it is checked against the same evaluator the
## recipient runs, so a proposal the counterparty would refuse is never sent.

const TradeEvaluator := preload("res://seats/trade_evaluator.gd")

## How much extra cash to sweeten an offer with, per step of shortfall.
const SWEETENER := 25
## Cash kept in hand, as a fraction of the starting balance, so a seat never
## trades itself into a position where it cannot pay rent.
const RESERVE_FRAC := 0.15


## The best trade for `pid` to propose, or {} when there is none worth making.
##
## Looks for a tile that would COMPLETE one of this seat's groups, and pays for it
## with a tile from the partner's own target group (the classic mutual-completion
## trade) or with cash.
static func choose(e, pid: int) -> Dictionary:
	if e == null or not e.settings.trades:
		return {}
	if e._pending_trade.size() != 0:
		return {}   # only one offer at a time, by the engine's own rule

	var target := _best_missing_tile(e, pid)
	if target < 0:
		return {}
	var holder: int = _owner_of(e, target)
	if holder < 0 or holder == pid:
		return {};

	var target_group: String = String(e._group_of(target))
	# prefer a MUTUAL completion: give the partner a tile that finishes one of
	# THEIR groups, which is what makes both sides better off
	var gift := _partner_gift(e, pid, holder, target_group)
	var give_tiles: Array = [] if gift < 0 else [gift]

	var want_value := _value(e, [target])
	var give_value := _value(e, give_tiles) if give_tiles.size() > 0 else 0
	var cash := _sweetener(e, pid, give_value, want_value)

	var offer := {
		"to": holder,
		"give_tiles": give_tiles,
		"give_cash": cash,
		"want_tiles": [target],
		"want_cash": 0,
	}
	# never send an offer the partner would refuse: the recipient runs exactly this
	# check, so sending a losing offer only wastes a turn and logs a decline
	if not TradeEvaluator.accept_with(e, holder, _as_pending(offer, pid)):
		return {}
	return offer


## The tile that would complete a group for `pid` — the one they are missing.
static func _best_missing_tile(e, pid: int) -> int:
	var best := -1
	var best_cost := -1
	for t in range(e.board.tile_count()):
		var group: String = String(e._group_of(t))
		if group == "":
			continue
		if _owner_of(e, t) < 0 or _owner_of(e, t) == pid:
			continue
		if not _one_short(e, pid, t):
			continue
		# the priciest missing piece is the one that matters most
		var cost: int = int(e.board.tile_at(t).get("cost", 0))
		if cost > best_cost:
			best_cost = cost
			best = t
	return best


## True when `pid` owns every tile of the group except `t`.
static func _one_short(e, pid: int, t: int) -> bool:
	var group: String = String(e._group_of(t))
	var missing := 0
	var tiles: Array = e.board.group_tiles(group)
	for other in tiles:
		var ti: int = int(other)
		if ti == t:
			continue
		if not e.players[pid].owns(ti):
			missing += 1
			if missing > 0:
				return false
	return true


## A tile to hand the partner that completes one of THEIR groups — the offer that
## is good for both sides. -1 when this seat has nothing they need.
static func _partner_gift(e, pid: int, partner: int, avoid_group: String) -> int:
	var best := -1
	var best_cost := -1
	for t in e.players[pid].owned_tiles():
		var tile: int = int(t)
		var group: String = String(e._group_of(tile))
		if group == "" or group == avoid_group:
			continue   # handing back from the same group would undo the trade
		if not _one_short(e, partner, tile):
			continue
		var cost: int = int(e.board.tile_at(tile).get("cost", 0))
		if cost > best_cost:
			best_cost = cost
			best = tile
	return best


## Cash added so the offer clears the recipient's `want >= give` test, without
## spending below the seat's reserve.
static func _sweetener(e, pid: int, give_value: int, want_value: int) -> int:
	var shortfall: int = want_value - give_value
	var cash := 0
	if shortfall > 0:
		# round up to the next step so the offer clears the bar
		cash = int(ceil(float(shortfall) / float(SWEETENER))) * SWEETENER
	var start: float = float(e.settings.starting_cash)
	# do not use the starting balance when it is unset in a test fixture
	var reserve: int = int(round(start * RESERVE_FRAC)) if start > 0.0 else 100
	var affordable: int = int(e.players[pid].money) - reserve
	if affordable < 0:
		affordable = 0
	if cash > affordable:
		cash = affordable
	return cash


static func _value(e, tiles: Array) -> int:
	var total := 0
	for t in tiles:
		total += int(e.board.tile_at(int(t)).get("cost", 0))
	return total


static func _owner_of(e, tile: int) -> int:
	for i in e.players.size():
		if e.players[i].owns(tile):
			return i
	return -1


## Shape the offer the way the engine stores a pending trade, so the recipient's
## own evaluator can be asked before anything is sent.
static func _as_pending(offer: Dictionary, proposer: int) -> Dictionary:
	return {
		"proposer": proposer,
		"recipient": int(offer.get("to", -1)),
		"give_tiles": offer.get("give_tiles", []),
		"give_cash": int(offer.get("give_cash", 0)),
		"want_tiles": offer.get("want_tiles", []),
		"want_cash": int(offer.get("want_cash", 0)),
	}
