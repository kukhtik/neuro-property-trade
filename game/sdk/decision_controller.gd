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
	return {
		"force": true,
		"query": _query(engine, pid, legal),
		"actions": legal,
		"ephemeral_context": true,
		"priority": "low",
	}

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
