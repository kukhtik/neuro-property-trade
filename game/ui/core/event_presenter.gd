class_name EventPresenter
extends Node
## The presentation queue (spec §8.1). The engine emits events instantly; this
## plays them back one at a time so the player can follow what happened.
##
## Contract:
##   1. Events play strictly in order. Each is a short sequence of steps.
##   2. If `animations` is off, OR the queue is longer than `queue_max`, events
##      apply instantly instead of animating.
##   3. When the queue drains we call `UiStore.resync(projection)`. The PROJECTION
##      is the truth: an animation may never leave the view out of sync, so a
##      mismatch is repaired here and logged.
##   4. The queue never blocks input. Actions that are illegal during the show are
##      disabled by the action panel; everything else keeps working.
##   5. The presenter never touches the engine. It consumes adapted events and
##      drives callbacks the scene hands it.
##
## It is deliberately transport-agnostic: `set_sink()` takes a Dictionary of
## callables so the presenter can drive the board, the effects layer, the sound
## and the store without importing any of them (keeps it headless-testable).

signal presenting(ev: Dictionary)
signal drained

## Queue length above which we stop animating and just apply (spec §8.1).
const QUEUE_MAX := 6

var animations := true
var queue_max := QUEUE_MAX

var _q: Array = []
var _busy := false
var _sink := {}          # name -> Callable
var _resync: Callable    # called with no args; must refresh the store
var _projection: Callable

var _played := 0
var _skipped := 0


## Wire the presenter's outputs. Recognised keys:
##   play(ev, instant)  — animate/apply one event (required)
##   resync()           — refresh the view model from the projection (required)
##   on_drained()       — optional extra hook
func set_sink(sink: Dictionary) -> void:
	_sink = sink


## The store refresh. Called once per drained queue.
func set_resync(fn: Callable) -> void:
	_resync = fn


## Supply the projection so a skip can jump straight to the truth.
func set_projection_source(fn: Callable) -> void:
	_projection = fn


## Queue one adapted event (EventAdapter output). Playback starts on the NEXT
## frame so that a burst of pushes (one engine turn emits several events) is
## treated as ONE queue: a single drain, and a single resync at the end of it.
func push(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	_q.append(ev)
	if not _busy:
		_busy = true
		call_deferred("_run")


## True while events are still being shown.
func is_busy() -> bool:
	return _busy or not _q.is_empty()


func pending() -> int:
	return _q.size()


## Drop everything and jump to the truth. Bound to Space / a click (spec §8.1).
func skip_all() -> void:
	_skipped += _q.size()
	# apply every remaining delta without effects, then let resync() correct any
	# drift — the projection is authoritative
	var apply: Callable = _sink.get("apply", Callable())
	while not _q.is_empty():
		var ev: Dictionary = _q.pop_front()
		if apply.is_valid():
			apply.call(ev, true)
	# the run may already be deferred; cancelling the flag stops it from
	# presenting an empty queue and firing a second drain
	_busy = false
	_do_resync()
	drained.emit()


## Statistics for the tests/probes.
func stats() -> Dictionary:
	return {"played": _played, "skipped": _skipped, "pending": _q.size(), "busy": _busy}


## Reset for a fresh match.
func clear() -> void:
	_q.clear()
	_busy = false
	_played = 0
	_skipped = 0


func _run() -> void:
	# Process until the queue is empty. `play` is synchronous from our point of
	# view: it either applies instantly or awaits its own tween; either way the
	# next event follows after it returns.
	while not _q.is_empty():
		var ev: Dictionary = _q.pop_front()
		# instant when animations are off, OR the backlog is too long to show
		var instant: bool = (not animations) or _q.size() >= queue_max
		presenting.emit(ev)
		var play: Callable = _sink.get("play", Callable())
		if play.is_valid():
			play.call(ev, instant)
		_played += 1
	_busy = false
	_do_resync()
	var hook: Callable = _sink.get("on_drained", Callable())
	if hook.is_valid():
		hook.call()
	drained.emit()


## Refresh the view model from the projection and shout if they disagree.
func _do_resync() -> void:
	if _resync.is_valid():
		_resync.call()
