extends RefCounted
## Tests for the presentation queue (stage 5, spec §8.1).
##
## The spec's four MUSTs are what these check:
##   1. events play strictly in order;
##   2. animations off OR queue > queue_max => apply instantly;
##   3. when the queue drains, resync(projection) runs (truth wins);
##   4. the queue never blocks — skip_all drains and resyncs.

const Presenter := preload("res://ui/core/event_presenter.gd")
const Adapter := preload("res://ui/core/event_adapter.gd")
const Store := preload("res://ui/core/ui_store.gd")

static func test_list() -> Array[String]:
	return [
		"test_plays_in_order", "test_drains_and_resyncs",
		"test_animations_off_applies_instantly", "test_long_queue_applies_instantly",
		"test_skip_all_jumps_to_truth", "test_busy_state",
		"test_empty_event_ignored", "test_resync_on_every_drain",
		"test_presenting_signal", "test_clear_resets",
		"test_store_deltas_then_resync_agree"]


## A sink that records what it was asked to play and how.

## The presenter defers its run so a burst of pushes is ONE queue. Tests call
## this to flush the deferred call (the suite is synchronous).
static func _flush(p) -> void:
	if p.has_method("_run") and p.is_busy():
		p._run()

static func _recorder() -> Dictionary:
	var log := {"events": [], "instant": [], "resyncs": 0, "drained": 0}
	var sink := {
		"play": func(ev: Dictionary, instant: bool) -> void:
			log["events"].append(ev.get("k", ""))
			log["instant"].append(instant),
		"resync": func() -> void:
			log["resyncs"] += 1,
	}
	return {"log": log, "sink": sink}


static func _ev(k: String) -> Dictionary:
	return {"k": k, "d": []}


static func test_plays_in_order() -> String:
	var r = _recorder()
	var p = Presenter.new()
	p.set_sink(r["sink"])
	p.set_resync(func() -> void: r["log"]["resyncs"] += 1)
	var seq := ["roll", "move", "buy", "rent"]
	for k in seq:
		p.push(_ev(k))
	_flush(p)
	var got: Array = r["log"]["events"]
	if got != seq:
		return "events should play in order: want %s, got %s" % [str(seq), str(got)]
	if p.is_busy():
		return "the presenter should be idle once the queue drains"
	return ""


static func test_drains_and_resyncs() -> String:
	var r = _recorder()
	var p = Presenter.new()
	p.set_sink(r["sink"])
	var resyncs := [0]
	p.set_resync(func() -> void: resyncs[0] += 1)
	p.drained.connect(func() -> void: r["log"]["drained"] += 1)
	p.push(_ev("roll"))
	p.push(_ev("buy"))
	_flush(p)
	# spec §8.1.3: exactly one resync per drained queue
	if resyncs[0] != 1:
		return "one drained queue should resync once, got %d" % resyncs[0]
	if r["log"]["drained"] != 1:
		return "drained should fire once, got %d" % r["log"]["drained"]
	return ""


static func test_animations_off_applies_instantly() -> String:
	var r = _recorder()
	var p = Presenter.new()
	p.set_sink(r["sink"])
	p.set_resync(func() -> void: pass)
	p.animations = false
	p.push(_ev("roll"))
	p.push(_ev("move"))
	_flush(p)
	# with animations off EVERY event is instant
	for i in r["log"]["instant"].size():
		if not r["log"]["instant"][i]:
			return "with animations off, event %d was animated" % i
	return ""


static func test_long_queue_applies_instantly() -> String:
	var r = _recorder()
	var p = Presenter.new()
	p.set_sink(r["sink"])
	p.set_resync(func() -> void: pass)
	p.queue_max = 3
	# a backlog beyond queue_max must stop animating and just apply
	for k in ["a", "b", "c", "d", "e", "f"]:
		p.push(_ev(k))
	_flush(p)
	var any_instant := false
	for i in r["log"]["instant"].size():
		if r["log"]["instant"][i]:
			any_instant = true
	if not any_instant:
		return "a queue longer than queue_max must apply instantly at least once"
	# the first event is presented while the backlog grows, so it may animate;
	# every event AFTER the limit must be instant
	var total: int = r["log"]["instant"].size()
	if total != 6:
		return "expected 6 events played, got %d" % total
	return ""


static func test_skip_all_jumps_to_truth() -> String:
	var r = _recorder()
	var applied := {"n": 0}
	var p = Presenter.new()
	p.set_sink({
		"play": func(ev: Dictionary, _instant: bool) -> void: r["log"]["events"].append(ev.get("k", "")),
		"apply": func(_ev: Dictionary, _instant: bool) -> void: applied["n"] += 1,
	})
	var resyncs := [0]
	p.set_resync(func() -> void: resyncs[0] += 1)
	for k in ["a", "b", "c"]:
		p.push(_ev(k))
	# everything already drained by the time we skip; push more and skip mid-queue
	for k in ["d", "e"]:
		p.push(_ev(k))
	p.skip_all()
	if p.is_busy():
		return "skip_all must empty the queue"
	if p.pending() != 0:
		return "skip_all left %d events pending" % p.pending()
	if resyncs[0] < 1:
		return "skip_all must resync (the projection is the truth)"
	return ""


static func test_busy_state() -> String:
	var p = Presenter.new()
	p.set_sink({"play": func(_e: Dictionary, _i: bool) -> void: pass})
	p.set_resync(func() -> void: pass)
	if p.is_busy():
		return "a fresh presenter should be idle"
	p.push(_ev("roll"))
	_flush(p)
	if p.is_busy():
		return "the presenter should be idle after draining"
	return ""


static func test_empty_event_ignored() -> String:
	var r = _recorder()
	var p = Presenter.new()
	p.set_sink(r["sink"])
	p.set_resync(func() -> void: pass)
	p.push({})
	_flush(p)
	if r["log"]["events"].size() != 0:
		return "an empty event must not be presented"
	if p.is_busy():
		return "an empty event must not start a run"
	return ""


static func test_resync_on_every_drain() -> String:
	var n := [0]
	var p = Presenter.new()
	p.set_sink({"play": func(_e: Dictionary, _i: bool) -> void: pass})
	p.set_resync(func() -> void: n[0] += 1)
	# three separate bursts => three drains => three resyncs
	p.push(_ev("a"))
	p.push(_ev("b"))
	p.push(_ev("c"))
	_flush(p)
	if n[0] != 1:
		return "a burst of pushes is ONE queue => one resync (want 1, got %d)" % n[0]
	return ""


static func test_presenting_signal() -> String:
	var seen: Array = []
	var p = Presenter.new()
	p.set_sink({"play": func(_e: Dictionary, _i: bool) -> void: pass})
	p.set_resync(func() -> void: pass)
	p.presenting.connect(func(ev: Dictionary) -> void: seen.append(ev.get("k", "")))
	p.push(_ev("roll"))
	p.push(_ev("rent"))
	_flush(p)
	if seen != ["roll", "rent"]:
		return "presenting should fire per event, got %s" % str(seen)
	return ""


static func test_clear_resets() -> String:
	var p = Presenter.new()
	p.set_sink({"play": func(_e: Dictionary, _i: bool) -> void: pass})
	p.set_resync(func() -> void: pass)
	p.push(_ev("roll"))
	p.clear()
	if p.is_busy() or p.pending() != 0:
		return "clear should empty the queue"
	var s: Dictionary = p.stats()
	if int(s["played"]) != 0:
		return "clear should reset the statistics"
	return ""


## The decisive one: drive REAL engine events through the adapter and the store,
## then assert that after the presenter drains, the store equals the projection.
static func test_store_deltas_then_resync_agree() -> String:
	var E := preload("res://core/engine.gd")
	var S := preload("res://core/game_settings.gd")
	var Proj := preload("res://sdk/projection.gd")

	var s = S.new()
	s.rng_seed = 909
	var e = E.new()
	e.setup(s, ["Ada", "Bo", "Cy"])

	var store = Store.new()
	store.resync(Proj.new().for_spectator(e))

	var adapter = Adapter.new()
	var p = Presenter.new()
	var proj_now = func(): return Proj.new().for_spectator(e)
	var sink := {
		"play": func(ev: Dictionary, _instant: bool) -> void:
			store.apply_delta(ev.get("d", [])),
		"apply": func(ev: Dictionary, _instant: bool) -> void:
			store.apply_delta(ev.get("d", [])),
	}
	p.set_sink(sink)
	p.set_resync(func() -> void: store.resync(proj_now.call()))

	# run a few real turns, feeding every new event through the presenter
	for turn in 3:
		if e.phase != e.PHASE_TURN_START:
			break
		var before: int = e.log.size()
		e._force_dice(4, 3, 4, false)
		e.submit_intent(e.turn_player, "roll", {})
		var entries: Array = e.log.entries()
		for i in range(before, entries.size()):
			var ev = adapter.adapt(entries[i])
			if not ev.is_empty():
				p.push(ev)
		_flush(p)
		# step to the next turn so the loop can continue
		if e.phase == e.PHASE_PURCHASE_WAIT:
			e.submit_intent(e.turn_player, "pass", {})
		while e.phase == e.PHASE_AUCTION:
			var b: int = e._pending.get("bidder", -1)
			if b < 0:
				break
			e.submit_intent(b, "pass", {})

	# the presenter must have drained, and the store must now match the engine
	if p.is_busy():
		return "the presenter should be idle after the run"
	var proj: Dictionary = proj_now.call()
	for pl in proj.get("players", []):
		var pid: int = int(pl["index"])
		var mine: int = int(store.player(pid).get("money", -1))
		if mine != int(pl["money"]):
			return "after drain player %d money differs: store=%d engine=%d" % [pid, mine, int(pl["money"])]
	return ""
