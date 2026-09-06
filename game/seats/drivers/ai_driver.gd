extends Node
## Internal AI driver: submits the first legal action each decision point.
## Reuses the soak's _auto_drive logic (bid-above-high-or-pass, decline trades).

var engine
var seat

func setup(eng, s) -> void:
	engine = eng
	seat = s

func act() -> void:
	if engine == null or seat == null:
		return
	var pid: int = seat.pid
	var legal: Array = engine.legal_actions(pid)
	if legal.is_empty():
		return
	var action: String = legal[0]
	var params := {}
	match action:
		"bid":
			var high: int = int(engine._pending.get("high", 0))
			if engine.player(pid).money <= high:
				action = "pass"
			else:
				params["amount"] = high + 1
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			var tiles: Array = engine.player(pid).owned_tiles()
			if tiles.size() == 0:
				return
			params["tile"] = int(tiles[0])
		"propose_trade":
			return   # AI does not proactively propose trades this phase
		"respond_trade":
			var TE = load("res://seats/trade_evaluator.gd")
			params["accept"] = TE.accept_with(engine, pid, engine._pending_trade)
	engine.submit_intent(pid, action, params)
