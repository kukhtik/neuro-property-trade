extends RefCounted
## Per-seat projection of engine state. Pure: reads the engine, returns a
## Dictionary. Never mutates. Isolates private info per seat (e.g. a seat's
## get-out-of-jail cards are only shown to that seat). Used by the SDK adapter
## to build the markdown context and to decide what to force.

## Build the full public+private view for one seat.
## Returns a Dictionary with keys: board, players, phase, turn_player,
## pending, legal, private.
func for_player(engine, pid: int) -> Dictionary:
	var out := {}
	out["phase"] = engine.phase
	out["turn_player"] = engine.turn_player
	out["board"] = _board_view(engine)
	out["players"] = _players_view(engine, pid)
	out["pending"] = _pending_view(engine)
	out["legal"] = engine.legal_actions(pid)
	out["private"] = _private_view(engine, pid)
	return out

func _board_view(engine) -> Array:
	var tiles: Array = []
	for i in engine.board.tile_count():
		var t = engine.board.tile_at(i)
		var entry := {
			"index": i,
			"name": t.get("name", ""),
			"type": t.get("type", "property"),
			"group": t.get("group", ""),
			"cost": int(t.get("cost", 0)),
			"owner": engine._owner_of(i),
			"houses": engine._houses_on(i),
			"mortgaged": engine._mortgaged.has(i),
		}
		tiles.append(entry)
	return tiles

func _players_view(engine, pid: int) -> Array:
	var players: Array = []
	for i in engine.players.size():
		var p = engine.players[i]
		var entry := {
			"index": i,
			"name": p.name,
			"money": p.money,
			"position": p.position,
			"in_jail": p.in_jail,
			"jail_turns": p.jail_turns,
			"bankrupt": p.bankrupt,
			"tiles": p.owned_tiles(),
		}
		players.append(entry)
	return players

func _pending_view(engine) -> Dictionary:
	var pending := {}
	if engine.phase == "PURCHASE_WAIT":
		pending["type"] = "purchase"
		pending["tile"] = engine._pending.get("tile", -1)
	elif engine.phase == "AUCTION":
		pending["type"] = "auction"
		pending["tile"] = engine._pending.get("tile", -1)
		pending["high"] = engine._pending.get("high", -1)
		pending["high_player"] = engine._pending.get("high_player", -1)
		pending["bidder"] = engine._pending.get("bidder", -1)
	elif engine._pending_trade.size() != 0:
		pending["type"] = "trade"
		pending["proposer"] = engine._pending_trade.get("proposer", -1)
		pending["recipient"] = engine._pending_trade.get("recipient", -1)
		pending["give_tiles"] = engine._pending_trade.get("give_tiles", [])
		pending["give_cash"] = engine._pending_trade.get("give_cash", 0)
		pending["want_tiles"] = engine._pending_trade.get("want_tiles", [])
		pending["want_cash"] = engine._pending_trade.get("want_cash", 0)
	return pending

func _private_view(engine, pid: int) -> Dictionary:
	# Only this seat's own hidden info. Currently: get-out-of-jail cards.
	var p = engine.players[pid]
	return {
		"get_out_of_jail_cards": p.get_out_of_jail_cards,
	}
