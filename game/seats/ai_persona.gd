class_name AiPersona
extends RefCounted
## An AI seat's CHARACTER, as data.
##
## WHY: every AI seat used to play identically — same buying threshold, same bid
## ceiling, same refusal to propose a trade. Four clones produced a dead economy:
## measured on the smoke's seed, ownership froze, no colour group ever completed,
## no house was ever built, every seat's cash grew without bound and the match
## could not reach game-over. The auction was the visible symptom (29 million bids
## across a match) but the cause was that nobody differed from anybody.
##
## A persona is a set of NUMBERS, not code. The driver reads them; nothing in the
## driver knows a persona's name. Adding a sixth character must not require
## touching the driver.
##
## Pure data + pure helpers, so every threshold is unit-testable.

## Personality ids. Stored on a seat, so a match can mix them.
const TYCOON := "tycoon"            # buys hard, bids high, builds early
const CAUTIOUS := "cautious"        # buys only with a cushion, quits auctions early
const COLLECTOR := "collector"      # chases groups, trades the most
const MISER := "miser"              # hoards cash, rarely buys, never trades
const AGGRESSOR := "aggressor"      # outbids everyone, builds to ruin others

const ALL := [TYCOON, CAUTIOUS, COLLECTOR, MISER, AGGRESSOR]

## The order a match with no explicit assignment uses, so an automatic game is
## never four clones.
const DEFAULT_ROTATION := [COLLECTOR, AGGRESSOR, CAUTIOUS, TYCOON, MISER]


## The numbers that define a character.
##
##  buy_reserve_frac  cash kept back after a purchase, as a fraction of the
##                    starting balance — the single biggest lever on how fast the
##                    board develops
##  bid_ceiling_mult  the most this seat pays for a plain lot, as a multiple of
##                    its price
##  bid_ceiling_set   the same for a lot that COMPLETES its colour group
##  bid_step_frac     how much the price moves per bid (bigger = auctions end sooner)
##  trades_eagerly    whether it looks for a mutual-completion trade at all
##  trade_cash_frac   cash it will add to sweeten an offer, of its balance
##  build_min_cash    it will not build below this multiple of the house cost
##  builds_early      builds at the first opportunity rather than hoarding
static func spec(persona_id: String) -> Dictionary:
	match persona_id:
		TYCOON:
			return {
				"buy_reserve_frac": 0.03, "bid_ceiling_mult": 2.5, "bid_ceiling_set": 3.5,
				"bid_step_frac": 0.15, "trades_eagerly": true, "trade_cash_frac": 0.25,
				"build_min_cash": 2, "builds_early": true,
			}
		CAUTIOUS:
			return {
				"buy_reserve_frac": 0.25, "bid_ceiling_mult": 1.1, "bid_ceiling_set": 1.8,
				"bid_step_frac": 0.05, "trades_eagerly": false, "trade_cash_frac": 0.10,
				"build_min_cash": 6, "builds_early": false,
			}
		COLLECTOR:
			return {
				"buy_reserve_frac": 0.12, "bid_ceiling_mult": 2.0, "bid_ceiling_set": 4.0,
				"bid_step_frac": 0.10, "trades_eagerly": true, "trade_cash_frac": 0.35,
				"build_min_cash": 3, "builds_early": true,
			}
		MISER:
			return {
				"buy_reserve_frac": 0.45, "bid_ceiling_mult": 0.8, "bid_ceiling_set": 1.2,
				"bid_step_frac": 0.05, "trades_eagerly": false, "trade_cash_frac": 0.05,
				"build_min_cash": 8, "builds_early": false,
			}
		AGGRESSOR:
			return {
				"buy_reserve_frac": 0.05, "bid_ceiling_mult": 3.0, "bid_ceiling_set": 4.5,
				"bid_step_frac": 0.20, "trades_eagerly": false, "trade_cash_frac": 0.15,
				"build_min_cash": 1, "builds_early": true,
			}
		_:
			return spec(TYCOON)   # unknown id degrades to a sane, known character


static func has(persona_id: String) -> bool:
	return ALL.has(persona_id)


## The persona a seat gets when the match did not assign one. Rotates by seat
## index so an automatic four-AI game is varied rather than four clones — which is
## precisely the situation that produced the dead economy.
static func default_for_index(i: int) -> String:
	if DEFAULT_ROTATION.is_empty():
		return TYCOON
	return str(DEFAULT_ROTATION[posmod(i, DEFAULT_ROTATION.size())])


## A short human-readable label key for i18n (never a literal in the UI).
static func label_key(persona_id: String) -> String:
	return "persona." + persona_id


# --- the decisions a persona drives -------------------------------------------

## Cash this seat keeps in hand after buying, in absolute units.
static func buy_reserve(persona_id: String, starting_cash: int) -> int:
	var f: float = float(spec(persona_id).get("buy_reserve_frac", 0.1))
	var base: int = starting_cash if starting_cash > 0 else 1500
	return int(round(float(base) * f))


## The most this seat will pay for `tile`: its price times the character's
## multiple, lifted further when the lot completes a colour group.
static func bid_ceiling(persona_id: String, tile_cost: int, completes_set: bool) -> int:
	if tile_cost <= 0:
		return 0
	var s := spec(persona_id)
	var mult: float = float(s.get("bid_ceiling_set", 3.0)) if completes_set \
		else float(s.get("bid_ceiling_mult", 2.0))
	return int(round(float(tile_cost) * mult))


## How far the price moves per bid. A bigger step closes an auction in fewer
## rounds, which is what stops one auction eating an entire match.
static func bid_step(persona_id: String, tile_cost: int) -> int:
	var f: float = float(spec(persona_id).get("bid_step_frac", 0.1))
	var base: int = tile_cost if tile_cost > 0 else 100
	var step: int = int(round(float(base) * f))
	return maxi(1, step)


static func trades_eagerly(persona_id: String) -> bool:
	return bool(spec(persona_id).get("trades_eagerly", false))


## Cash this seat will put into a trade to make it acceptable.
static func trade_cash_limit(persona_id: String, money: int) -> int:
	if not trades_eagerly(persona_id):
		return 0
	var f: float = float(spec(persona_id).get("trade_cash_frac", 0.1))
	return int(round(float(maxi(money, 0)) * f))


## May this seat build, given its cash and the cost of a house?
static func will_build(persona_id: String, money: int, house_cost: int) -> bool:
	if house_cost <= 0:
		return false
	var need: int = house_cost * int(spec(persona_id).get("build_min_cash", 3))
	return money >= need


static func builds_early(persona_id: String) -> bool:
	return bool(spec(persona_id).get("builds_early", false))


## May this seat buy, given its cash and the lot's price?
static func will_buy(persona_id: String, money: int, cost: int, starting_cash: int,
		completes_set: bool) -> bool:
	if cost <= 0:
		return false
	if completes_set:
		# a lot that finishes a group is worth stretching for
		return money >= cost
	return money - cost >= buy_reserve(persona_id, starting_cash)
