extends Node
## Randy soak driver for the Phase 2 SDK adapter.
##
## Runs a full game headless with the adapter wired to a live websocket (Randy
## on ws://localhost:8000). Seat 0 is the AI seat driven by the adapter (forced
## via the SDK); seats 1..N are driven by a local AutoDriver that submits the
## first legal action each decision point. The game runs until END_GAME or a
## max-turn cap, then quits with a pass/fail exit code.
##
## Usage:
##   NEURO_SDK_WS_URL=ws://localhost:8000 godot --headless --path game res://tools/soak.tscn
##
## Exit 0 = soak passed (game reached END_GAME or hit the turn cap without
## stalling); exit 1 = stall/timeout/error.

const EngineScript := preload("res://core/engine.gd")
const Settings := preload("res://core/game_settings.gd")
const SdkAdapter := preload("res://sdk/sdk_adapter.gd")

const MAX_TURNS := 12
const STALL_SECONDS := 20.0
const TURN_TIMER := 3   # short force window so Randy answers fast

var _engine
var _adapter
var _turn_count: int = 0
var _last_phase: String = ""
var _last_turn: int = -1
var _stall_elapsed: float = 0.0
var _started: bool = false
var _done: bool = false

func _ready() -> void:
	print("=== Randy soak: starting ===")
	var s = Settings.new()
	s.rng_seed = 12345
	s.turn_timer = TURN_TIMER
	s.auction_timer = TURN_TIMER
	# Auctions OFF: Randy (the mock Neuro) can't bid affordably — it retries
	# bid_auction with huge amounts forever and never switches to pass, which
	# stalls the soak. The auction path is already covered by Phase 1 headless
	# engine tests; this soak exercises the main turn loop (roll/move/buy/pass/
	# rent/jail/cards) through the adapter.
	s.auctions_on_refusal = false
	_engine = EngineScript.new()
	_engine.setup(s, ["Neuro", "Ada", "Bo", "Cy"])
	# Wire the adapter for seat 0 (the AI seat).
	_adapter = SdkAdapter.new()
	_adapter.name = "SdkAdapter"
	add_child(_adapter)
	_adapter.setup(_engine, 0)
	_started = true
	print("=== Randy soak: engine ready, adapter wired for seat 0 ===")

func _process(delta: float) -> void:
	if not _started or _done:
		return
	# Auto-drive non-AI seats (1..N): submit the first legal action.
	for pid in range(1, _engine.player_count()):
		_auto_drive(pid)
	# Stall detection: if the phase/turn/bidder hasn't changed for
	# STALL_SECONDS, fail. Include the auction bidder so auction progress is
	# detected (turn_player stays the auctioneer during an auction).
	var key: String = "%s|%d|%d" % [_engine.phase, _engine.turn_player, _engine._pending.get("bidder", -1)]
	if key == _last_phase:
		_stall_elapsed += delta
		if _stall_elapsed >= STALL_SECONDS:
			print("=== Randy soak: STALLED at %s (no progress for %.0fs) ===" % [key, STALL_SECONDS])
			print("=== pending: %s ===" % str(_engine._pending))
			var legal_all: Array = []
			for p in range(_engine.player_count()):
				legal_all.append(_engine.legal_actions(p))
			print("=== legal per seat: %s ===" % str(legal_all))
			_finish(false)
	else:
		_last_phase = key
		_stall_elapsed = 0.0
	# Turn counting + end detection. Count each time it becomes Neuro's turn
	# (turn_player transitions to 0).
	if _engine.turn_player == 0 and _last_turn != 0:
		_turn_count += 1
		_last_turn = 0
		if _turn_count % 5 == 0:
			print("=== Randy soak: turn %d, phase %s ===" % [_turn_count, _engine.phase])
		if _turn_count >= MAX_TURNS:
			print("=== Randy soak: reached turn cap %d ===" % MAX_TURNS)
			_finish(true)
	elif _engine.turn_player != 0:
		_last_turn = _engine.turn_player
	if _engine.phase == "END_GAME":
		print("=== Randy soak: game over ===")
		_finish(true)

func _auto_drive(pid: int) -> void:
	var legal: Array = _engine.legal_actions(pid)
	if legal.is_empty():
		return
	var action: String = legal[0]
	var params := {}
	match action:
		"bid":
			# bid just above the current high so the auction can progress; if the
			# player can't afford to outbid, pass instead (else it fails forever)
			var high: int = int(_engine._pending.get("high", 0))
			if _engine.player(pid).money <= high:
				action = "pass"
			else:
				params["amount"] = high + 1
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			# pick the first owned tile
			var tiles: Array = _engine.player(pid).owned_tiles()
			if tiles.size() == 0:
				return
			params["tile"] = int(tiles[0])
		"propose_trade":
			# skip trades in auto-drive (complex); just roll instead
			return
		"respond_trade":
			params["accept"] = false
	_engine.submit_intent(pid, action, params)

func _finish(passed: bool) -> void:
	_done = true
	if passed:
		print("=== Randy soak: PASSED ===")
		get_tree().quit(0)
	else:
		print("=== Randy soak: FAILED ===")
		get_tree().quit(1)
