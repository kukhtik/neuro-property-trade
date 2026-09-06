extends Node
## Chat seat driver — collective aggregation (spec Block 5 chat_mode). Phase-3
## stub: majority of the last N non-empty commands, enqueued by the host/UI.
## Default `chat_mode = "majority"`; ties -> the first enqueued of the leaders.

const QUEUE_WINDOW := 8

var engine
var seat
var _queue: Array = []   # of {action, params}

func setup(eng, s) -> void:
	engine = eng
	seat = s

func enqueue(action: String, params: Dictionary) -> void:
	_queue.append({"action": action, "params": params})
	if _queue.size() > QUEUE_WINDOW:
		_queue.pop_front()

func act() -> void:
	if engine == null or seat == null or _queue.size() == 0:
		return
	var legal: Array = engine.legal_actions(seat.pid)
	var counts := {}
	for cmd in _queue:
		var a: String = cmd["action"]
		if legal.has(a):
			counts[a] = int(counts.get(a, 0)) + 1
	if counts.size() == 0:
		return
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
