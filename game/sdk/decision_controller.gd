extends RefCounted
## Decides whether an AI seat should be forced to act, and what to send.
## Pure: reads the engine + a projection, returns a Dictionary. No side effects.
##
## Returns {force: bool, query: String, actions: Array[String],
##          ephemeral_context: bool, priority: String}.
## force is true only when the seat has legal actions (its turn, it is the
## auction bidder, or it is a trade recipient). priority is always "low"
## (turn-based, per SDK best practices). ephemeral_context is true for the
## bulky per-turn board dump.
##
## Forced action set is phase-aware and deliberately SMALL:
##   - TURN_START (not in jail): force only "roll" — the primary turn action.
##     Management actions (build/sell/mortgage/unmortgage/propose_trade) stay
##     REGISTERED (stable set) but are not forced, so a random/naive driver
##     (Randy) doesn't spam them and stall on failures.
##   - TURN_START (in jail): force the jail legal set (roll/pay/use_card).
##   - PURCHASE_WAIT / AUCTION / trade-recipient: force the full legal set.

func decide(engine, pid: int, proj: Dictionary) -> Dictionary:
	var legal: Array = proj.get("legal", [])
	if legal.is_empty():
		return {
			"force": false,
			"query": "",
			"actions": [],
			"ephemeral_context": false,
			"priority": "low",
		}
	var forced: Array = _forced_actions(engine, pid, legal)
	if forced.is_empty():
		return {
			"force": false,
			"query": "",
			"actions": [],
			"ephemeral_context": false,
			"priority": "low",
		}
	return {
		"force": true,
		"query": _query(engine, pid, forced),
		"actions": forced,
		"ephemeral_context": true,
		"priority": "low",
	}

func _forced_actions(engine, pid: int, legal: Array) -> Array:
	# Cross-player seats (auction bidder, trade recipient) act outside their
	# own turn — force their full legal set.
	if pid != engine.turn_player:
		return legal
	match engine.phase:
		"TURN_START":
			if engine.players[pid].in_jail:
				return legal
			return ["roll"]
		_:
			return legal

func _query(engine, pid: int, legal: Array) -> String:
	var phase: String = engine.phase
	var name: String = engine.players[pid].name
	match phase:
		"TURN_START":
			if engine.players[pid].in_jail:
				return "It is %s's turn and you are in jail. Choose one: %s." % [name, ", ".join(legal)]
			return "It is %s's turn. Choose one: %s." % [name, ", ".join(legal)]
		"PURCHASE_WAIT":
			return "You landed on an unowned property. Choose one: %s." % ", ".join(legal)
		"AUCTION":
			return "It is your bid in the auction. Choose one: %s." % ", ".join(legal)
		_:
			return "Your turn. Choose one: %s." % ", ".join(legal)
