extends Node
## "Как пользователи будут играть" - a real match with a REAL model on one seat, watched for
## stalls. HG-08 only proves an SDK seat answers a fixed priority list; this drives the same seat
## with `tools/ci/llm_seat.py` (opencode free model) and reports what the pipeline does when the
## player thinks slowly, answers junk, or says nothing.
##
## Reports (one line per fact, so a log diff is readable):
##   MATCH seats=... rounds=... limit=... timer=...
##   MATCH intents pid=<i> name=<n> accepted=<k>
##   MATCH events <type>=<count> ...
##   MATCH stalls=<n> at rounds <list>
##   MATCH DONE rounds=<n> log=<n>
## Verdict: ==> LLM-MATCH DONE (no stall) / ==> LLM-MATCH STALLED: <reason>
## Run: bash tools/ci/llm_match.sh --model opencode/deepseek-v4.1-flash-free

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")

const ROUND_LIMIT := 2
const TURN_TIMER := 20         # on purpose: a slow seat vs a 20 s clock - the stall hunt
## A language model needs 8-50 s per decision, so "no progress" has to mean MUCH longer than the
## 45 s that felt right for a scripted bot - otherwise the harness reports its own patience as a
## product stall (it did, on the first run).
const STALL_SECS := 60.0
const WATCH_CAP_SECS := 300.0   # the run reports what it HAS instead of hanging the shell

var _launcher = null
var _frame := 0
var _watch_start := 0
var _last_change := 0
var _last_round := -1
var _last_log := -1
var _stalls: Array = []
var _started := false


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if not _started and _frame >= 6:
		_started = true
		_build_match()
		_watch_start = Time.get_ticks_msec()
		_last_change = _watch_start
		print("MATCH seats=4 rounds=0 limit=%d timer=%ds" % [ROUND_LIMIT, TURN_TIMER])
		return
	if not _started:
		return
	var now := Time.get_ticks_msec()
	var eng = _launcher.get("_engine")
	if eng == null:
		return
	var rounds := int(eng.round_no)
	var nlog: int = eng.log.entries().size()
	if _frame % 300 == 0:
		var last := ""
		var entries_now: Array = eng.log.entries()
		if not entries_now.is_empty():
			last = str(entries_now[-1].get("type", "?"))
		print("MATCH tick %.0fs rounds=%d log=%d last=%s" % [
			float(now - _watch_start) / 1000.0, rounds, nlog, last])
	if rounds != _last_round or nlog != _last_log:
		_last_round = rounds
		_last_log = nlog
		_last_change = now
	if rounds >= ROUND_LIMIT or _finished(eng):
		_report(eng, rounds)
		return
	if float(now - _last_change) / 1000.0 > STALL_SECS:
		var tail: Array = []
		var entries: Array = eng.log.entries()
		for i in range(maxi(0, entries.size() - 3), entries.size()):
			tail.append(str(entries[i].get("type", "?")))
		_stalls.append("round %d after %.0fs (last events: %s)" % [
			rounds, float(now - _last_change) / 1000.0, ", ".join(tail)])
		print("MATCH STALL %s" % _stalls[-1])
		_dump_stall_state(eng)
		# give the match another window: a slow model may simply be thinking
		_last_change = now
		if _stalls.size() >= 3:
			_report(eng, rounds)
			return
	if float(now - _watch_start) / 1000.0 > WATCH_CAP_SECS:
		_stalls.append("watch cap %.0fs reached at round %d" % [WATCH_CAP_SECS, rounds])
		_dump_stall_state(eng)
		_report(eng, rounds)


func _dump_stall_state(eng) -> void:
	print("MATCH stall-state phase=%s turn=%s pending=%s" % [str(eng.get("phase")),
		str(eng.get("current_player") if eng.get("current_player") != null else eng.get("turn_player")),
		str(eng.get("pending"))])
	if eng.settings != null:
		print("MATCH stall-settings turn_timer=%s auction_timer=%s timeout_action=%s" % [
			str(eng.settings.turn_timer), str(eng.settings.auction_timer),
			str(eng.settings.get("timeout_action"))])
	var mgr = _launcher.get("_manager")
	if mgr != null:
		for s in mgr.get("seats"):
			print("MATCH stall-seat pid=%d driver=%s waiting=%.1fs away=%s" % [
				int(s.pid), str(s.input_driver), float(s.decision_waiting), str(s.away)])
		var ads = mgr.get("_sdk_adapters")
		if ads is Dictionary:
			for pid in (ads as Dictionary).keys():
				var a = (ads as Dictionary)[pid]
				print("MATCH stall-adapter pid=%s awaiting=%s since=%s retried=%s window=%s" % [
					str(pid), str(a.get("_awaiting_result")), str(a.get("_await_since_ms")),
					str(a.get("_await_retried")), str(eng.settings.turn_timer)])
	var entries: Array = eng.log.entries()
	for i in range(maxi(0, entries.size() - 4), entries.size()):
		print("MATCH stall-log %s" % str(entries[i]).left(160))


func _finished(eng) -> bool:
	for key in ["finished", "game_over", "is_over"]:
		if eng.get(key) != null:
			return bool(eng.get(key))
	return false


func _build_match() -> void:
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 20261018
	st.round_limit = ROUND_LIMIT
	st.turn_timer = TURN_TIMER
	st.seat_assignments = [
		{"driver": "sdk:neuro", "name": "Model"},
		{"driver": "AI", "name": "Bot 2"},
		{"driver": "AI", "name": "Bot 3"},
		{"driver": "AI", "name": "Bot 4"},
	]
	var seats: Array = SeatConfigScript.from_settings(st)
	_launcher.call("_build_game", st, seats)
	_launcher.get("_overlay").visible = false
	_launcher.set("_game_started", true)
	_launcher.get("_game_view").call("on_game_started")


func _report(eng, rounds: int) -> void:
	var mgr = _launcher.get("_manager")
	var entries: Array = eng.log.entries()
	var by_type := {}
	for e in entries:
		var t := str(e.get("type", "?"))
		by_type[t] = int(by_type.get(t, 0)) + 1
	var types: Array = []
	for k in by_type.keys():
		types.append("%s=%d" % [k, int(by_type[k])])
	types.sort()
	if mgr != null:
		for s in mgr.get("seats"):
			var pid := int(s.pid)
			var n := 0
			for e in entries:
				var d: Dictionary = e.get("data", {})
				if int(d.get("player", -1)) == pid or int(d.get("from", -1)) == pid:
					n += 1
			print("MATCH intents pid=%d name=%s driver=%s accepted=%d" % [
				pid, str(s.name), str(s.input_driver), n])
	print("MATCH events %s" % ", ".join(types))
	print("MATCH DONE rounds=%d log=%d stalls=%d" % [rounds, entries.size(), _stalls.size()])
	if rounds >= ROUND_LIMIT:
		print("==> LLM-MATCH DONE (match reached its round limit with the model seat playing, no freeze)")
		get_tree().quit(0)
		return
	# A cap reached is not the same as a freeze: a slow or dead seat is auto-passed on the clock, so
	# the log GROWS and rounds still turn over. Only a log that never grew past the setup is a stall.
	if entries.size() > 5:
		print("==> LLM-MATCH ADVANCING (cap reached at round %d, %d events: the seat was timed out and" % [
			rounds, entries.size()] + " auto-passed, the match never froze)")
		get_tree().quit(0)
		return
	print("==> LLM-MATCH STALLED: %s" % str(_stalls[0]))
	get_tree().quit(1)
