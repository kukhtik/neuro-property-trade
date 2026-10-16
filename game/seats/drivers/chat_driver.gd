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
var _queue: Array = []   # of {action, params}
var _empty := 0          # consecutive decision points with nothing usable in the box

func setup(eng, s) -> void:
	engine = eng
	seat = s

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
		if _empty >= EMPTY_ROUNDS_BEFORE_PASS and legal.has("pass"):
			_empty = 0
			engine.submit_intent(seat.pid, "pass", {})
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
	engine.submit_intent(seat.pid, best, chosen.get("params", {}))
