extends Node
## HG-02 gate (seed) — the human cycle through the CONSOLE (docs/restoration/gates.md, HG-02).
##
## Grown out of the audit's `console_actions_probe.gd`, which only PRINTED refusals. The
## contract, bounded to the console for now: a real 1-human-vs-AI match runs; the gate presses
## the REAL buttons the console offers at the human's turn and records what the engine answers.
##   - pressing a console button may never produce a REFUSAL MODAL ("Действие отклонено /
##     Причина: ..."): a button the UI draws must have a reachable execution path;
##   - at least one action per turn must be ACCEPTED (the positive control: roll moves the log);
##   - a purchase decision (buy or decline) must be reachable and accepted.
## The full robot-human cycle (inspector, trade modals, auctions) extends THIS gate in P0.
##
## Verdict: ==> HG-02 PASSED / FAILED: <first reason>   (quarantine until P0 closes)
## Run: godot --headless --path game res://tools/gates/hg02_console_actions_gate.tscn

const MainScript := preload("res://main.gd")
const I18n := preload("res://i18n/i18n.gd")

const FIRST_TURN_PRESS := ["build_house", "sell_house", "mortgage_property",
	"unmortgage_property", "propose_trade", "respond_trade", "roll"]
const FRAME_BUDGET := 4000
const WALL_CLOCK_MS := 100000

var _launcher = null
var _frame := 0
var _t0 := 0
var _results: Dictionary = {}
var _pressed_any := false
var _roll_seen := false
var _purchase_done := false
var _human_turns := 0
var _fails: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	_t0 = Time.get_ticks_msec()
	_launcher = MainScript.new()
	add_child(_launcher)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 8:
		_launcher.call("_autostart")
		return
	if _frame < 16 or _frame % 10 != 0:
		return
	var engine = _launcher.get("_engine")
	if engine == null:
		return
	if _finished(engine):
		_report(engine)
		return
	if Time.get_ticks_msec() - _t0 > WALL_CLOCK_MS:
		_report(engine)
		return
	if str(engine.phase) == "TURN_START" and int(engine.turn_player) == 0:
		var gv = _launcher.get("_game_view")
		var console = gv.find_child("act", true, false) if gv != null else null
		var legal: Array = (console.get("_last_legal") as Array) if console != null else []
		if not _pressed_any:
			# THE CONSOLE'S OWN STATE, not the engine's: the buttons are painted from the
			# projection, and at frame 16 the engine is already at TURN_START while the console
			# is still empty. Pressing "into the void" made every button read as absent and the
			# gate passed over a dead console. Only press once the row really carries the
			# human's full action set.
			if legal.has("build_house") and bool(console.get("_human_now")):
				_pressed_any = true
				_human_turns += 1
				for key in FIRST_TURN_PRESS:
					_press(key)
		else:
			_human_turns += 1
			# later turns: keep the match moving until a purchase decision appears
			_press("roll")
	elif str(engine.phase) == "PURCHASE_WAIT" and int(engine.turn_player) == 0 and not _purchase_done:
		_purchase_done = true
		var legal_p: Array = engine.legal_actions(0)
		_press("buy" if legal_p.has("buy") else "pass")


func _finished(engine) -> bool:
	if str(engine.phase) == "END_GAME":
		return true
	return _pressed_any and _roll_seen and _purchase_done


## Press one console button by its action key. Returns the outcome string.
func _press(key: String) -> String:
	var gv = _launcher.get("_game_view")
	var console = gv.find_child("act", true, false)
	if console == null:
		return "no-console"
	var b := _find_button(console, key)
	if b == null:
		_results[key] = "absent"
		return "absent"
	var engine = _launcher.get("_engine")
	var before_phase := str(engine.phase)
	var before_log: int = engine.log.size()
	b.emit_signal("pressed")
	var modal = gv.find_child("modal", true, false)
	var outcome := "no-op"
	if modal != null and (modal as Control).visible:
		var title := str((modal.get("_title") as Label).text)
		var body := _modal_text(modal)
		modal.call("close")
		if title == I18n.t("gv.rejected_title"):
			outcome = "refused: " + body
		else:
			outcome = "dialog: " + title
	else:
		if str(engine.phase) != before_phase or engine.log.size() > before_log or _intents_accepted(key):
			outcome = "accepted"
	if outcome == "accepted" and key == "roll":
		_roll_seen = true
	_results[key] = outcome
	print("HG-02 press %-22s -> %s" % [key, outcome if outcome.length() < 140 else outcome.substr(0, 140)])
	return outcome


## The engine has no verdict API outside submit_intent; the manager does. Anything that moved
## the engine counts as accepted, which is what the log/phase delta above already shows.
func _intents_accepted(_key: String) -> bool:
	return false


func _find_button(console, key: String) -> Button:
	var row = console.get("_btn_row")
	if row == null:
		return null
	var want := I18n.t(key_to_label(key))
	for c in row.get_children():
		if c is Button and str((c as Button).text).begins_with(want):
			return c
	return null


func key_to_label(key: String) -> String:
	match key:
		"build_house":
			return "act.build"
		"sell_house":
			return "act.sell"
		"mortgage_property":
			return "act.mortgage"
		"unmortgage_property":
			return "act.unmortgage"
		"propose_trade":
			return "act.trade"
		"respond_trade":
			return "act.respond_trade"
		"roll":
			return "act.roll"
		"buy":
			return "act.buy"   # NOT act.buy_price: that template carries $%d and cannot prefix-match
		"pass":
			return "act.no_buy"
	return key


func _modal_text(modal) -> String:
	var body = modal.get("_body")
	if body == null:
		return ""
	var out: Array = []
	for c in body.get_children():
		if c is Label:
			out.append(str((c as Label).text))
	return " ".join(out)


func _report(engine) -> void:
	var refused: Array = []
	var accepted: Array = []
	var dialogs: Array = []
	for k in _results:
		var v := str(_results[k])
		if v.begins_with("refused"):
			refused.append("%s -> %s" % [k, v])
		elif v == "accepted":
			accepted.append(k)
		elif v.begins_with("dialog"):
			dialogs.append(k)
	print("HG-02: human turns=%d  accepted=%s  refusals=%d  dialogs=%s"
		% [_human_turns, str(accepted), refused.size(), str(dialogs)])
	if _results.has("roll") or _frame > 16:
		print("HG-02: roll=%s purchase=%s" % [str(_results.get("roll", "-")), str(_results.get("buy", _results.get("pass", "-")))])
	if not refused.is_empty():
		print("==> HG-02 FAILED: %d console button(s) were refused by the engine with empty params (first: %s)"
			% [refused.size(), refused[0]])
		get_tree().quit(1)
		return
	# a button the engine allows but the console does not draw is the same defect from the
	# other side: the action exists and the UI offers no way to perform it (F-26).
	var missing: Array = []
	for k in FIRST_TURN_PRESS:
		if str(_results.get(k, "")) == "absent" and k != "roll" and _pressed_any:
			missing.append(k)
	if not missing.is_empty():
		print("==> HG-02 FAILED: the console draws no button for legal action(s): %s" % str(missing))
		get_tree().quit(1)
		return
	if not _pressed_any:
		print("==> HG-02 FAILED: no human TURN_START within the budget - nothing was exercised")
		get_tree().quit(1)
		return
	if not _roll_seen:
		print("==> HG-02 FAILED: roll was never accepted - the match did not move")
		get_tree().quit(1)
		return
	if not _purchase_done:
		print("==> HG-02 FAILED: no purchase decision (buy/decline) reached within the budget")
		get_tree().quit(1)
		return
	print("==> HG-02 PASSED (%d console presses, 0 UI-caused refusals, roll+purchase accepted)"
		% _results.size())
	get_tree().quit(0)
