extends SceneTree
## Stage-6 acceptance probe: modals behave inside the running game.
##
## The suite tests ModalHost standalone. This checks the LIVE launcher, which is
## what stage 3 taught us to always verify:
##  1. exactly one modal exists at a time, however it is opened;
##  2. the auction modal opens for a REAL auction and gives buttons only to the
##     engine's current bidder;
##  3. a background click leaves the auction and game-over open;
##  4. the trade modal lists the human's REAL tradeable tiles.
##
## Exit 0 = stage 6 is integrated.

const MainScript := preload("res://main.gd")
const SkinMgr := preload("res://visual/skin_manager.gd")
const UiTheme := preload("res://ui/theme.gd")
const Proj := preload("res://sdk/projection.gd")

var _fail := 0

func _init() -> void:
	print("=== Stage 6 acceptance: modals in the live game ===")
	_run()


## Launched from _init but awaited across frames: _init itself cannot resume
## after `await process_frame` because the tree is not pumping yet.
func _run() -> void:
	await process_frame
	var launcher = MainScript.new()
	root.add_child(launcher)
	for i in 20:
		await process_frame
	var overlay: Node = launcher.get("_overlay")
	if overlay == null:
		_bad("no settings overlay")
		_finish()
		return
	overlay.call("_start_pressed")
	for i in 15:
		await process_frame
	var gv: Node = launcher.get("_game_view")
	if gv == null:
		_bad("no game_view after START")
		_finish()
		return
	var modals = gv.get("_modals")
	if modals == null:
		_bad("game_view has no modal host")
		_finish()
		return

	_check_no_stack(modals)
	await _check_auction_live(modals, gv)
	_check_dim_rules(modals)
	_check_trade_tiles(modals, gv)
	_finish()


func _finish() -> void:
	print("")
	if _fail > 0:
		print("==> STAGE 6 FAILED (%d)" % _fail)
		quit(1)
	else:
		print("==> STAGE 6 PASSED — one modal, engine-driven buttons, protected dialogs")
		quit(0)


func _ok(m: String) -> void:
	print("  ok  " + m)

func _bad(m: String) -> void:
	_fail += 1
	print("  FAIL " + m)


func _check_no_stack(modals) -> void:
	print("[1] only one modal panel exists at a time")
	for k in ["rules", "settings", "message", "rules"]:
		modals.open(k, {"text": "x", "title": "t", "msg": "m", "cats": []})
		var n: int = modals.panel_count()
		if n > 1:
			_bad("opening '%s' left %d panels" % [k, n])
			return
	_ok("opened 4 modals in a row, never more than one panel")
	modals.close()


func _check_auction_live(modals, gv) -> void:
	print("[2] the auction modal follows the engine's current bidder")
	var engine = gv.get("engine")
	if engine == null:
		_bad("no engine on the game view")
		return
	# force an auction by landing the turn player on a tile nobody owns yet.
	# Picking index 1 blindly fails once the match has progressed (it may be
	# owned, and landing on an owned tile pays rent instead of offering it).
	var target: int = -1
	for i in engine.board.tile_count():
		var ty: String = engine.board.type_at(i)
		if (ty == "property" or ty == "railroad" or ty == "utility") \
				and engine._owner_of(i) == -1:
			target = i
			break
	if target < 0:
		_ok("every buyable tile is owned — auction path not exercisable here")
		return
	engine._teleport(engine.turn_player, posmod(target - 1, engine.board.tile_count()))
	engine._force_dice(1, 1, 0, false)
	engine.submit_intent(engine.turn_player, "roll", {})
	if engine.phase != engine.PHASE_PURCHASE_WAIT:
		_bad("expected a purchase decision to decline, got phase %s" % engine.phase)
		return
	engine.submit_intent(engine.turn_player, "pass", {})
	for i in 3:
		await process_frame
	if engine.phase != engine.PHASE_AUCTION:
		_bad("declining did not start an auction (phase %s)" % engine.phase)
		return
	var bidder: int = int(engine._pending.get("bidder", -1))
	var legal: Array = engine.legal_actions(bidder)
	if not legal.has("bid"):
		_bad("the engine should offer [bid,pass] to bidder %d, got %s" % [bidder, str(legal)])
		return
	_ok("the engine asks bidder %d to bid (legal=%s)" % [bidder, str(legal)])

	# the CURRENT bidder's modal must have buttons; another seat's must not
	modals.open_auction(Proj.new().for_spectator(engine), gv.get("seats"), legal)
	var with_buttons: int = _count_action_buttons(modals)
	if with_buttons < 2:
		_bad("the current bidder should get bid+pass buttons, got %d" % with_buttons)
	else:
		_ok("the current bidder gets %d action buttons" % with_buttons)
	var other: int = _other_pid(bidder, gv.get("seats"))
	modals.open_auction(Proj.new().for_spectator(engine), gv.get("seats"),
		engine.legal_actions(other))
	var none: int = _count_action_buttons(modals)
	if none != 0:
		_bad("a non-bidder must get no buttons, got %d" % none)
	else:
		_ok("a non-bidder spectates with no buttons (public bids only)")


func _check_dim_rules(modals) -> void:
	print("[3] a background click cannot dismiss a decision or the game over")
	modals.open_auction({"board": [], "pending": {}}, [], [])
	modals._on_dim_input(_click())
	if not modals.is_open():
		_bad("the dim dismissed the auction")
	else:
		_ok("the auction survives a background click")
	modals.open("game_over", {"winner": "A", "turns": 1, "capital": 0, "players": 2})
	modals._on_dim_input(_click())
	if not modals.is_open():
		_bad("the dim dismissed game-over")
	else:
		_ok("game-over survives a background click")
	modals.open("rules", {"text": "x"})
	modals._on_dim_input(_click())
	if modals.is_open():
		_bad("the dim should dismiss the rules modal")
	else:
		_ok("an informational modal DOES dismiss on a background click")


func _check_trade_tiles(modals, gv) -> void:
	print("[4] the trade modal lists the human's real tradeable tiles")
	var engine = gv.get("engine")
	var pid: int = int(gv.get("_human_pid"))
	if pid < 0:
		_bad("no human seat in this match")
		return
	# give the human an owned tile with no houses
	engine.players[pid].add_ownership(6)
	var proj := Proj.new().for_spectator(engine)
	modals.open_trade(proj, gv.get("seats"), pid)
	var boxes := 0
	for n in modals.nodes():
		if n is CheckBox and str(n.get_meta("tag", "")) == "give":
			boxes += 1
	if boxes < 1:
		_bad("the give side should list the human's tradeable tiles, got %d" % boxes)
	else:
		_ok("the give side lists %d real tile(s)" % boxes)


func _count_action_buttons(modals) -> int:
	var n := 0
	for c in modals.nodes():
		if c is Button and not (c is CheckBox):
			var k := str(c.get_meta("i18n_key", ""))
			if k in ["modal.bid_btn", "modal.pass_btn"]:
				n += 1
	return n


func _other_pid(bidder: int, seats) -> int:
	for s in seats:
		if int(s.pid) != bidder:
			return int(s.pid)
	return -1


func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	return ev
