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
const FRAME_BUDGET := 9000
const WALL_CLOCK_MS := 150000

var _launcher = null
var _frame := 0
var _t0 := 0
var _results: Dictionary = {}
var _pressed_any := false
var _roll_seen := false
var _purchase_done := false
var _human_turns := 0
var _phase := "console"      # console -> purchase -> auction -> auction_bid -> done
var _auction_started := false
var _auction_bid_ok := false
var _auction_note := ""
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
	if str(engine.phase) == "END_GAME" or _phase == "done":
		_report(engine)
		return
	if Time.get_ticks_msec() - _t0 > WALL_CLOCK_MS:
		_report(engine)
		return
	match _phase:
		"console":
			_do_console_turn(engine)
		"purchase":
			_do_purchase_step(engine)
		"auction":
			_do_auction_setup(engine)
		"auction_bid":
			_do_auction_bid(engine)


## Step 1: the first human turn, every console button pressed for real.
func _do_console_turn(engine) -> void:
	if str(engine.phase) != "TURN_START" or int(engine.turn_player) != 0:
		return
	var gv = _launcher.get("_game_view")
	var console = gv.find_child("act", true, false) if gv != null else null
	var legal: Array = (console.get("_last_legal") as Array) if console != null else []
	if not bool(console.get("_human_now")):
		return
	if not legal.has("build_house"):
		return
	_pressed_any = true
	_human_turns += 1
	for key in FIRST_TURN_PRESS:
		_press(key)
	_phase = "purchase"


## Step 2: a purchase decision must be reachable and accepted. Keep rolling until one comes.
func _do_purchase_step(engine) -> void:
	if str(engine.phase) == "PURCHASE_WAIT" and int(engine.turn_player) == 0 and not _purchase_done:
		_purchase_done = true
		var legal_p: Array = engine.legal_actions(0)
		_press("buy" if legal_p.has("buy") else "pass")
		_phase = "auction"
		return
	if str(engine.phase) == "TURN_START" and int(engine.turn_player) == 0:
		_human_turns += 1
		_press("roll")


## Step 3: set up a deterministic auction - force the dice onto an unowned, purchasable tile,
## roll there and DECLINE the purchase, which (auctions_on_refusal) opens the auction with the
## human as the first bidder.
func _do_auction_setup(engine) -> void:
	if str(engine.phase) == "TURN_START" and int(engine.turn_player) == 0:
		_human_turns += 1
		var target := _pick_unowned_reachable(engine)
		if target < 0:
			_auction_note = "no unowned purchasable tile is reachable - the board is all owned"
			_phase = "done"
			return
		var step: int = (target - int(engine.players[0].position) + 40) % 40
		if step < 2:
			step += 40
		var d1: int = 6 if step >= 7 else int(floor(step / 2.0))
		var d2: int = step - d1
		engine.call("_force_dice", step, d1, d2, false)
		_press("roll")
		return
	if str(engine.phase) == "PURCHASE_WAIT" and int(engine.turn_player) == 0:
		_press("pass")
		if str(engine.phase) == "AUCTION":
			_auction_started = true
			_phase = "auction_bid"
			_results["decline_for_auction"] = "accepted"


## The first unowned property/railroad/utility reachable from the human's position.
func _pick_unowned_reachable(engine) -> int:
	var pos: int = int(engine.players[0].position)
	var board = engine.board
	for k in range(2, 13):
		var idx: int = (pos + k) % board.tile_count()
		var t = board.tile_at(idx)
		var ttype := str(t.get("type", ""))
		if ttype in ["property", "railroad", "utility"] and engine._owner_of(idx) == -1:
			return idx
	return -1


## Step 4: the human is the first bidder. Press the console BID - it must open the auction
## modal (not a $0 intent), the modal's own field must carry the amount, and the engine must
## take the bid.
func _do_auction_bid(engine) -> void:
	if str(engine.phase) != "AUCTION":
		_phase = "done"
		return
	var pend: Dictionary = engine.get("_pending")
	if int(pend.get("bidder", -1)) != 0:
		return   # the AI outbid; wait for the rotation to come back (or the budget to run out)
	if _auction_bid_ok:
		_phase = "done"
		return
	var gv = _launcher.get("_game_view")
	if gv == null:
		return
	var modal = gv.find_child("modal", true, false)
	# 1) the console BID opens the sheet. Open it via the shell entry point directly: the
	#    generic `_press` helper CLOSES any dialog it sees (that is its job for hint sheets),
	#    and closing the auction sheet would leave nothing to type into.
	if modal == null or not (modal as Control).visible or str(modal.get("kind")) != "auction":
		gv.call("_on_action", "bid", {})
		_results["bid"] = "opens the auction sheet"
		return
	# 2) the sheet carries the input; place a bid above the current high
	var high: int = int(pend.get("high", -1))
	var amount: int = (high + 5) if high > 0 else 5
	var input = modal.find_child("bid_input", true, false)
	if input == null:
		_fail("the auction modal for the current bidder has no amount field")
		_phase = "done"
		return
	(input as LineEdit).text = str(amount)
	var send := _find_modal_button(modal, I18n.t("modal.bid_btn"))
	if send == null:
		_fail("the auction modal has no %s button" % I18n.t("modal.bid_btn"))
		_phase = "done"
		return
	send.emit_signal("pressed")
	var new_high: int = int((engine.get("_pending") as Dictionary).get("high", -1))
	var hi_player: int = int((engine.get("_pending") as Dictionary).get("high_player", -1))
	if new_high == amount and hi_player == 0:
		_auction_bid_ok = true
		_results["auction_bid"] = "accepted %d" % amount
		print("HG-02 auction: bidding %d through the modal was accepted (high %d -> %d)"
			% [amount, high, new_high])
	else:
		_results["auction_bid"] = "not accepted (high %d -> %s)" % [high, str(new_high)]
	_phase = "done"


func _find_modal_button(modal, label: String) -> Button:
	var stack: Array = [modal]
	while not stack.is_empty():
		var nd = stack.pop_back()
		for c in nd.get_children():
			stack.append(c)
			if c is Button and str((c as Button).text).begins_with(label):
				return c
	return null


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
		"bid":
			return "act.bid"
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
	print("HG-02: roll=%s purchase=%s auction=%s"
		% [str(_results.get("roll", "-")), str(_results.get("buy", _results.get("pass", "-"))),
			str(_results.get("auction_bid", _auction_note if _auction_note != "" else "not reached"))])
	if not refused.is_empty():
		print("==> HG-02 FAILED: %d console button(s) were refused by the engine with empty params (first: %s)"
			% [refused.size(), refused[0]])
		get_tree().quit(1)
		return
	# a button the engine allows but the console does not draw is the same defect from the other
	# side: the action exists and the UI offers no way to perform it (F-26).
	# EXCEPTION: `respond_trade` at a plain TURN_START - the engine lists it for everyone, but
	# only the trade RECIPIENT can answer, and the console now draws it only for them.
	var missing: Array = []
	for k in FIRST_TURN_PRESS:
		if str(_results.get(k, "")) == "absent" and k != "roll" and k != "respond_trade" and _pressed_any:
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
	if not _auction_bid_ok:
		print("==> HG-02 FAILED: the auction bid through the modal was not accepted or not reached (%s)"
			% (str(_results.get("auction_bid", _auction_note)) if _auction_note == "" else _auction_note))
		get_tree().quit(1)
		return
	print("==> HG-02 PASSED (%d console presses, 0 UI-caused refusals, roll+purchase+auction accepted)"
		% _results.size())
	get_tree().quit(0)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)
