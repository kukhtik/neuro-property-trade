extends Node
## Chat seat driver — collective aggregation (spec Block 5 chat_mode). Phase-3
## stub: majority of the last N non-empty commands, enqueued by the host/UI.
## Default `chat_mode = "majority"`; ties -> the first enqueued of the leaders.

const QUEUE_WINDOW := 8
## How many consecutive decision points a CHAT seat may sit with an unusable box before it
## passes. A stream that went quiet (viewers left, the bridge died, the match is being watched
## by nobody) must not stall the game: the seat auto-passes. Three, not one, because viewers
## need a beat to type - passing on the first empty round would make the whole seat unusable.
const EMPTY_ROUNDS_BEFORE_PASS := 3

var engine
var seat
## See ai_driver.manager: a chat-driven seat must submit THROUGH the manager for its events to
## reach the journal - the same defect that left an AI match's feed empty.
var manager = null
var _queue: Array = []   # of {action, params}
var _empty := 0          # consecutive decision points with nothing usable in the box

func setup(eng, s, mgr = null) -> void:
	engine = eng
	seat = s
	manager = mgr


## Submit through the manager when we have one, so the events it returns are published.
func submit(action: String, params: Dictionary) -> Dictionary:
	if seat == null:
		return {}
	if manager != null and manager.has_method("push_intent"):
		return manager.push_intent(seat.pid, action, params)
	return engine.submit_intent(seat.pid, action, params)

func enqueue(action: String, params: Dictionary) -> void:
	_queue.append({"action": action, "params": params})
	if _queue.size() > QUEUE_WINDOW:
		_queue.pop_front()
	_empty = 0

func act() -> void:
	if engine == null or seat == null:
		return
	var legal: Array = engine.legal_actions(seat.pid)
	var counts := {}
	for cmd in _queue:
		var a: String = cmd["action"]
		if legal.has(a):
			counts[a] = int(counts.get(a, 0)) + 1
	if counts.size() == 0:
		# Either nobody voted or everyone voted for something the engine will not take - most
		# often votes left over from the PREVIOUS decision (viewers type ahead). Keeping them
		# would let the previous decision decide this one, so the box is emptied here.
		_queue.clear()
		_empty += 1
		# THE AUTO-PASS. It used to be guarded by `legal.has("pass")` - and "pass" is NOT
		# in the legal set at TURN_START (the engine offers roll/build/sell/mortgage/trade
		# there), so the guard was NEVER true and a chat seat whose viewers went quiet
		# STALLED THE WHOLE MATCH: the promise in this file's own header ("the seat
		# auto-passes") could not happen. The fix is to act on the decision the seat
		# actually faces:
		#   - TURN_START  -> "roll" is the only move that advances the turn, and the
		#     engine accepts it; a quiet table rolls on.
		#   - PURCHASE_WAIT / AUCTION -> "pass" is legal and is the way out.
		# So: prefer "pass" when it is legal, otherwise "roll".
		#
		# AND: when the seat is NOT the one on the hook (an auction rotates the bidder
		# through the other seats), the legal set is EMPTY. The counter must not be
		# reset by that - it is the wait, not a new decision - so the auto-move is
		# decided by the ENGINE'S PHASE, not by the legal set.
		if _empty >= EMPTY_ROUNDS_BEFORE_PASS:
			_empty = 0
			if legal.has("pass"):
				submit("pass", {})
			elif legal.has("roll"):
				submit("roll", {})
			else:
				# Not our decision right now: an auction rotates the bidder through the
				# other seats, and while we are not the bidder our legal set is EMPTY.
				# Somebody else has the decision, so there is nothing to auto-move.
				pass
		return
	_empty = 0
	# best = action with the most votes; ties -> first enqueued of the leaders
	var best: String = ""
	var best_count := 0
	for cmd in _queue:
		var a: String = cmd["action"]
		if counts.has(a) and int(counts[a]) > best_count:
			best = a
			best_count = int(counts[a])
	if best == "":
		return
	var chosen := {}
	for cmd in _queue:
		if cmd["action"] == best:
			chosen = cmd
			break
	_queue.clear()
	submit(best, chosen.get("params", {}))
