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
	out["parking_pot"] = engine.parking_pot()
	out["round"] = engine.round_no
	# GLOBAL PAUSE: the seat must know the match is paused too (its force carries actions it is not
	# allowed to take; the adapter freezes its own timeout on this flag).
	out["paused"] = engine.paused
	out["paused_by"] = engine.paused_by
	return out

## E-3: what the engine would charge a lander on `i` right now.
## `_property_rent`, so the projection never re-implements a game rule (and cannot silently
## disagree with what a player is actually charged).
func _rent_now(engine, i: int) -> int:
	var owner: int = engine._owner_of(i)
	if owner < 0:
		# unowned: the engine's function returns a meaningless 0 for "no owner"; report the base
		# card rent instead, which is the honest answer to "what would this cost" before a sale.
		return int(engine.board.tile_at(i).get("rent", 0))
	return int(engine._property_rent(i, owner))


func _board_view(engine) -> Array:
	var tiles: Array = []
	for i in engine.board.tile_count():
		var t = engine.board.tile_at(i)
		var entry := {
			"index": i,
			"name": t.get("name", ""),
			"short": t.get("short", t.get("name", "")),
			"type": t.get("type", "property"),
			"group": t.get("group", ""),
			"cost": int(t.get("cost", 0)),
			"amount": int(t.get("amount", 0)),
			"rent": int(t.get("rent", 0)),
			"rent_set": int(t.get("rent_set", 0)),
			# E-3/D11: the rent that would be charged RIGHT NOW - with this tile's houses and with
			# the monopoly doubling the settings allow. The base `rent` is what the tile costs when
			# nobody has built; a viewer looking at a 3-house hotel plot and reading "$2" is being
			# told the wrong number, because that is what the card says, not what the game charges.
			#
			# IT IS THE ENGINE'S OWN FUNCTION, called with the owner, so there is exactly ONE rent
			# formula in the project. Re-deriving it here would be a second source of truth that
			# drifts the first time a house rule changes - and this repo has been bitten by exactly
			# that (the `pot` vs `parking_pot` rename that left a chip reading $0 forever).
			"rent_now": _rent_now(engine, i),
			"owner": engine._owner_of(i),
			"owner_name": _owner_name(engine, engine._owner_of(i)),
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
			"houses": _player_houses(engine, p.owned_tiles()),
			"mortgaged": _player_mortgaged(engine, p.owned_tiles()),
		}
		players.append(entry)
	return players

func _player_houses(engine, tiles: Array) -> int:
	var total := 0
	for t in tiles:
		total += engine._houses_on(t)
	return total

func _player_mortgaged(engine, tiles: Array) -> int:
	var n := 0
	for t in tiles:
		if engine._mortgaged.has(t):
			n += 1
	return n

## Resolve a player's display name from a pid (empty when unowned).
func _owner_name(engine, pid: int) -> String:
	if pid < 0 or pid >= engine.players.size():
		return ""
	return str(engine.players[pid].name)

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

## Full public view for a spectator / stream overlay — NO private section and
## no hidden per-seat info (auction high/bidder ARE public; jail cards are not).
func for_spectator(engine) -> Dictionary:
	var out := {}
	out["phase"] = engine.phase
	out["turn_player"] = engine.turn_player
	out["board"] = _board_view(engine)
	out["players"] = _spectator_players_view(engine)
	out["pending"] = _pending_view(engine)
	out["parking_pot"] = engine.parking_pot()
	out["round"] = engine.round_no
	# GLOBAL PAUSE: every screen (seat, spectator, admin) reads the same two keys, so a pause is
	# visible and identical everywhere instead of being a local freeze.
	out["paused"] = engine.paused
	out["paused_by"] = engine.paused_by
	# NOTE: no "legal" and no "private" — a spectator is not a decision holder.
	return out


func _spectator_players_view(engine) -> Array:
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
			"houses": _player_houses(engine, p.owned_tiles()),
			"mortgaged": _player_mortgaged(engine, p.owned_tiles()),
		}
		players.append(entry)
	return players
