extends Node
## HG-13 gate — hotkeys and the turn timer (docs/restoration/gates.md HG-13).
##
## What the live match must prove:
##   1. the decision zone shows a ticking remainder while a seat waits (it DECREASES) — the
##      projection has carried timer_window/elapsed/active since the seat manager existed,
##      nobody painted them;
##   2. B presses the real BUY button (the engine takes the purchase);
##   3. the N PROMISE: engine.legal_actions never lists `end_turn` (turns advance by themselves,
##      `_end_turn_or_continue`) — so no N badge may be drawn. If a future engine DOES offer it,
##      this gate demands the hotkey test instead of letting the promise rot;
##   4. turn_timer=0 -> no timer widget at all;
##   5. the manager's own timeout really fires: with turn_timer=1 the waiting seat is marked
##      away and an automatic action lands (auto-pass by setting).
##
## All waits are WALL-CLOCK: headless does not run at 60 fps, frame counts lie about seconds
## (the first version of this gate failed its own tick test on exactly that).
## Key events go through the REAL handler (the convention HG-12 uses for F12).
##
## Verdict: ==> HG-13 PASSED (...) / FAILED: <first reason>
## Run: godot --headless --path game res://tools/gates/hg13_hotkeys_timer_gate.tscn

const MainScript := preload("res://main.gd")

const MIN_CHECKS := 6

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 6
var _deadline := 0
var _fails: Array = []
var _checks := 0
var _budget := 0
var _did_buy := false
var _saw_end_turn_legal := false
var _did_end := false
var _saw_n_badge := false
var _t_before := ""
var _log_size := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	match _state:
		"boot":
			_wait -= 1
			if _wait > 0:
				return
			_launcher.call("_autostart")
			_state = "to_human"
			_deadline = Time.get_ticks_msec() + 6000
		"to_human":
			# the match parks on the LOCAL seat without --smoke-drive: that IS the waiting seat
			if _human_turn() or Time.get_ticks_msec() >= _deadline:
				_state = "timer_show"
				_wait = 4
		"timer_show":
			_wait -= 1
			if _wait > 0:
				return
			var txt := _decision_text()
			if txt == "" or not _is_clock(txt):
				_fail("the waiting seat shows no timer remainder in the decision zone (got `%s`)" % txt)
				_state = "drive"
				_wait = 6
				_budget = 2400
				return
			_checks += 1
			_t_before = txt
			print("HG-13: timer shows `%s`" % txt)
			_state = "timer_tick"
			_deadline = Time.get_ticks_msec() + 2200
		"timer_tick":
			if Time.get_ticks_msec() < _deadline:
				return
			var after := _decision_text()
			if not _is_clock(after) or _clock_secs(after) >= _clock_secs(_t_before):
				_fail("the timer does not tick (`%s` -> `%s` after ~2.2s)" % [_t_before, after])
			else:
				_checks += 1
				print("HG-13: timer ticks `%s` -> `%s`" % [_t_before, after])
			_state = "drive"
			_wait = 6
			_budget = 2400
		"drive":
			_wait -= 1
			if _wait > 0:
				return
			_wait = 3
			_budget -= 1
			_drive_and_test()
			if (_did_buy and (_did_end or not _saw_end_turn_legal)) or _budget <= 0:
				if not _did_buy:
					_fail("no purchase ever offered the human a BUY within the budget - B untested")
				if _saw_end_turn_legal and not _did_end:
					_fail("end_turn WAS legal but the N press was never exercised - the promise is live")
				if not _saw_end_turn_legal:
					_checks += 1
					print("HG-13: the N promise stays void (end_turn never legal) and no badge is drawn")
				if _saw_n_badge:
					_fail("an N badge is drawn for an action the engine never offers")
				_state = "timer_off"
				_wait = 6
		"timer_off":
			_wait -= 1
			if _wait > 0:
				return
			var eng = _launcher.get("_engine")
			var mgr = _launcher.get("_manager")
			if eng == null or mgr == null:
				_fail("engine/manager gone before the timer-off test")
				_report()
				return
			eng.settings.turn_timer = 0
			mgr.call("emit_spectator")
			_state = "timer_off_check"
			_wait = 6
		"timer_off_check":
			_wait -= 1
			if _wait > 0:
				return
			var d = _decision()
			if d != null and (d as Control).visible and _is_clock(_decision_text()):
				_fail("turn_timer=0 still shows a timer (`%s`)" % _decision_text())
			else:
				_checks += 1
				print("HG-13: turn_timer=0 -> no timer widget")
			_state = "expiry_set"
			_wait = 4
		"expiry_set":
			_wait -= 1
			if _wait > 0:
				return
			var eng2 = _launcher.get("_engine")
			var mgr2 = _launcher.get("_manager")
			# BOTH windows, because the human may be inside an auction right now (the first
			# version set only turn_timer and then sat in an AUCTION whose auction_timer was
			# still long - a self-inflicted red). The auction untangles on its own 1s window,
			# then we wait for a CLEAN turn decision (legal has `roll`).
			eng2.settings.turn_timer = 1
			eng2.settings.auction_timer = 1
			mgr2.call("emit_spectator")
			_state = "expiry_wait"
			_deadline = Time.get_ticks_msec() + 25000
		"expiry_wait":
			# wait until the human HOLDS A PURE TURN DECISION (roll) - not an auction lot - and
			# only then start measuring; the parked window is what must fire on its own
			if _human_turn():
				var gvw = _launcher.get("_game_view")
				var actw = gvw.find_child("act", true, false) if gvw != null else null
				var legalw: Array = actw.get("_last_legal") if actw != null else []
				if legalw.has("roll"):
					_log_size = _engine_log_size()
					_state = "expiry_watch"
					_deadline = Time.get_ticks_msec() + 8000
					return
			if Time.get_ticks_msec() >= _deadline:
				_fail("the human never held a clean turn decision again for the expiry test")
				_report()
		"expiry_watch":
			# give the 1s window + the poll interval + the auto-action time; poll for the effect
			var seats: Array = _launcher.get("_seats_cache")
			var pid := _human_pid()
			var away := false
			for s in seats:
				if int(s.pid) == pid:
					away = bool(s.away)
			var grew: bool = _engine_log_size() > _log_size
			var moved_on: bool = not _human_turn()
			if away and (grew or moved_on):
				_checks += 1
				print("HG-13: the 1s window fired - seat marked away, the engine moved on its own (log grew=%s, holder moved=%s)" % [str(grew), str(moved_on)])
				_report()
				return
			if Time.get_ticks_msec() >= _deadline:
				var eng3 = _launcher.get("_engine")
				var gv3 = _launcher.get("_game_view")
				var act3 = gv3.find_child("act", true, false) if gv3 != null else null
				var legal3: Array = act3.get("_last_legal") if act3 != null else []
				_fail("turn_timer=1 did not fire: away=%s, log grew=%s, holder moved=%s; phase=%s action=%s legal=%s pending=%s" % [str(away), str(grew), str(moved_on), str(eng3.phase), str(eng3.settings.timeout_action), str(legal3), str(eng3._pending) if eng3 else "?"])
				_report()


func _drive_and_test() -> void:
	var gv = _launcher.get("_game_view")
	var eng = _launcher.get("_engine")
	var mgr = _launcher.get("_manager")
	if gv == null or eng == null or mgr == null:
		return
	if not _human_turn():
		return
	var act = gv.find_child("act", true, false)
	if act == null:
		return
	var legal: Array = act.get("_last_legal")
	if legal.has("end_turn"):
		_saw_end_turn_legal = true
	for c in (act.get("_btn_row") as Container).get_children():
		if c is Button:
			if str((c as Button).get_meta("act", "")) == "end_turn":
				_saw_n_badge = true
			if str((c as Button).text).ends_with("  N"):
				_saw_n_badge = true
	var pid := _human_pid()
	if legal.has("buy") and not _did_buy:
		var ev := InputEventKey.new()
		ev.keycode = KEY_B
		ev.pressed = true
		var ph0: String = str(eng.phase)
		gv.call("_unhandled_key_input", ev)
		var ph1: String = str(eng.phase)
		if ph1 == ph0 and ph0 == "PURCHASE_WAIT":
			_fail("B did not take the purchase (phase stayed %s)" % ph1)
			_budget = 0
		else:
			_did_buy = true
			_checks += 1
			print("HG-13: B took the purchase (%s -> %s)" % [ph0, ph1])
		return
	if legal.has("end_turn") and not _did_end:
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_N
		ev2.pressed = true
		var tp0: int = int(eng.turn_player)
		gv.call("_unhandled_key_input", ev2)
		var tp1: int = int(eng.turn_player)
		if tp1 == tp0 and str(eng.phase) != "TURN_END":
			_fail("N did not hand the turn over (turn_player stayed %d)" % tp1)
			_budget = 0
		else:
			_did_end = true
			_checks += 1
			print("HG-13: N handed the turn over (%d -> %d)" % [tp0, tp1])
		return
	if legal.has("roll"):
		mgr.call("push_intent", pid, "roll", {})
		return
	if legal.has("pass"):
		mgr.call("push_intent", pid, "pass", {})
	elif legal.has("end_turn"):
		mgr.call("push_intent", pid, "end_turn", {})


func _human_turn() -> bool:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return false
	var act = gv.find_child("act", true, false)
	return act != null and bool(act.get("_human_now"))


func _human_pid() -> int:
	var gv = _launcher.get("_game_view")
	return int(gv.get("_human_pid")) if gv != null else -1


func _decision():
	var gv = _launcher.get("_game_view")
	if gv == null:
		return null
	var top = gv.find_child("top", true, false)
	return top.get("_decision") if top != null else null


func _decision_text() -> String:
	var d = _decision()
	return str((d as Label).text) if d != null else ""


## `0:07`-style remainder.
func _is_clock(s: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[0-9]+:[0-9][0-9]$")
	return rx.search(s.strip_edges()) != null


func _clock_secs(s: String) -> int:
	var parts := s.strip_edges().split(":")
	if parts.size() != 2:
		return -1
	return int(parts[0]) * 60 + int(parts[1])


func _engine_log_size() -> int:
	var eng = _launcher.get("_engine")
	if eng == null:
		return 0
	var lg = eng.get("log")
	return int((lg as Array).size()) if lg is Array else 0


func _report() -> void:
	print("HG-13: %d checks" % _checks)
	if _checks < MIN_CHECKS and _fails.is_empty():
		_fail("only %d check(s) ran - the gate aborted silently (want >= %d)" % [_checks, MIN_CHECKS])
	if _fails.is_empty():
		print("==> HG-13 PASSED (B takes the purchase, the timer ticks, hides at 0 and fires at expiry; the N promise is void and no badge lies)")
		get_tree().quit(0)
	else:
		print("==> HG-13 FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
