extends RefCounted
## Picks the minimal non-stalling intent for a seat that timed out (spec §3 auto-pass).
## Uses engine.legal_actions as the source of truth for what is actually available.

static func pick(engine, pid: int) -> Dictionary:
	var legal: Array = engine.legal_actions(pid)
	if legal.size() == 0:
		return {}   # END_GAME or not this seat's turn -> do nothing
	if engine.phase == "PURCHASE_WAIT":
		return {"action": "pass", "params": {}}
	if engine.phase == "AUCTION":
		return {"action": "pass", "params": {}}
	# Respond path: only when a REAL pending trade targets this seat (legal_actions
	# always lists respond_trade on TURN_START as a management action, so gate on
	# the engine's _pending_trade state, not just the legal list).
	if engine._pending_trade.size() != 0 and engine._pending_trade.get("recipient", -1) == pid:
		return {"action": "respond_trade", "params": {"accept": false}}
	# Jail decision: prefer roll while attempts remain, then pay, then use_card.
	# (legal for a jailed seat omits "roll" once jail_turns >= 3.)
	if engine.phase == "TURN_START" and engine.player(pid).in_jail:
		if legal.has("roll"):
			return {"action": "roll", "params": {}}
		if legal.has("pay"):
			return {"action": "pay", "params": {}}
		if legal.has("use_card"):
			return {"action": "use_card", "params": {}}
		return {}
	if legal.has("roll"):
		return {"action": "roll", "params": {}}
	return {}
