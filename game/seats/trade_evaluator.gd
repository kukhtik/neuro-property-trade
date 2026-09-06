extends RefCounted
## Simple heuristic for an AI seat deciding whether to accept a proposed trade.
## Value = sum of tile cost (from board) + cash. Accept if received value >=
## given value. Kept as the Phase-3 stub; a smarter economic model is later.

static func accept_with(engine, recipient_pid: int, trade: Dictionary) -> bool:
	var give: int = _value(engine, trade.get("give_tiles", [])) + int(trade.get("give_cash", 0))
	var want: int = _value(engine, trade.get("want_tiles", [])) + int(trade.get("want_cash", 0))
	return want >= give

static func _value(engine, tiles: Array) -> int:
	var total := 0
	for t in tiles:
		total += int(engine.board.tile_at(int(t)).get("cost", 0))
	return total
