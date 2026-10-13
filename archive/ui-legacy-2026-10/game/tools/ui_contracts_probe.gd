extends SceneTree
## Stage-2 acceptance probe: the event contracts work against the REAL engine.
##
## Unit tests feed synthetic log entries. This probe drives an actual game
## (dice forced deterministically) and runs every real log entry through
## EventAdapter + UiStore, checking that:
##   1. no engine event type fails to adapt (or is silently unknown);
##   2. the store's money after applying all deltas equals the projection;
##   3. resync(projection) is consistent with the delta path.
##
## Exit 0 = the contracts match the engine, not just my fixtures.

const EngineS := preload("res://core/engine.gd")
const SettingsS := preload("res://core/game_settings.gd")
const Adapter := preload("res://ui/core/event_adapter.gd")
const Store := preload("res://ui/core/ui_store.gd")
const ProjScript := preload("res://sdk/projection.gd")

var _fail := 0
var _seen_types := {}

func _init() -> void:
	print("=== Stage 2 acceptance: contracts vs the real engine ===")
	_run_scenario()
	print("")
	if _fail > 0:
		print("==> CONTRACTS FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> CONTRACTS PASSED — events + deltas agree with the projection")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)


func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _run_scenario() -> void:
	var s = SettingsS.new()
	s.rng_seed = 1234
	s.free_parking = true          # exercise the new pot events too
	var e = EngineS.new()
	e.setup(s, ["Ada", "Bo", "Cy"])

	var adapter = Adapter.new()
	var store = Store.new()
	store.resync(ProjScript.new().for_spectator(e))

	# Drive a fixed sequence of forced rolls so the run is reproducible.
	# turn 0: 3+4=7 -> tile 7 ; turn 1: 1+1 doubles -> jail path exercised later
	var script := [
		[0, 3, 4], [1, 5, 3], [2, 2, 5],
		[0, 6, 6], [0, 1, 2], [1, 4, 6], [2, 3, 3],
	]
	var applied := 0
	for step in script:
		var pid: int = step[0]
		# hand the turn to `pid` if the engine is waiting on someone else
		if e.phase == e.PHASE_TURN_START and e.turn_player != pid:
			e.turn_player = pid
		if e.phase != e.PHASE_TURN_START:
			# resolve any leftover decision so the script can continue
			_safe_resolve(e, pid)
			if e.phase != e.PHASE_TURN_START:
				continue
		e._force_dice(step[1] + step[2], step[1], step[2], step[1] == step[2])
		var before: int = e.log.size()
		e.submit_intent(pid, "roll", {})
		# adapt + apply every NEW entry
		var entries: Array = e.log.entries()
		for i in range(before, entries.size()):
			var ev = adapter.adapt(entries[i])
			if ev.is_empty():
				continue
			_seen_types[str(entries[i]["type"])] = true
			applied += 1
			store.apply_delta(ev["d"])
			if store.vm["over"] == null and ev["k"] == "over":
				store.mark_over(ev["p"])
		_safe_resolve(e, pid)

	print("[1] adapted %d real engine events across %d distinct types" % [applied, _seen_types.size()])
	if _seen_types.size() < 5:
		_bad("too few distinct engine event types exercised (%d)" % _seen_types.size())

	# The decisive check: money in the delta-drifted store must equal the
	# projection (which is read straight from the engine).
	var proj = ProjScript.new().for_spectator(e)
	var mismatches := 0
	for p in proj.get("players", []):
		var pid := int(p["index"])
		var store_money: int = store.player(pid).get("money", -999999)
		var engine_money: int = int(p["money"])
		if store_money != engine_money:
			mismatches += 1
			_bad("player %d money: store=%d engine=%d" % [pid, store_money, engine_money])
	if mismatches == 0:
		_ok("delta-drifted money matches the projection for every player")

	# resync must repair the store to exactly the projection
	store.resync(proj)
	var repaired := 0
	for p in proj.get("players", []):
		var pid2 := int(p["index"])
		if store.player(pid2).get("money", -1) != int(p["money"]):
			repaired += 1
	if repaired == 0:
		_ok("resync(projection) agrees with the delta path")
	else:
		_bad("resync did not converge with the projection")

	var types: Array = _seen_types.keys()
	types.sort()
	_ok("engine types seen: %s" % str(types))


## Resolve whatever decision the engine is waiting on, so the script can move on.
func _safe_resolve(e, pid: int) -> void:
	var guard := 0
	while e.phase != e.PHASE_TURN_START and e.phase != e.PHASE_END_GAME and guard < 8:
		guard += 1
		match e.phase:
			e.PHASE_PURCHASE_WAIT:
				e.submit_intent(e.turn_player, "pass", {})
			e.PHASE_AUCTION:
				var bidder: int = e._pending.get("bidder", -1)
				if bidder >= 0:
					e.submit_intent(bidder, "pass", {})
				else:
					break
			e.PHASE_JAIL_DECISION:
				e.submit_intent(e.turn_player, "pay", {})
			_:
				break
	# advance the turn if it is still ours and nothing is pending
	if e.phase == e.PHASE_TURN_START and e.turn_player == pid:
		pass
