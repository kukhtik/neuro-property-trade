extends Node
## SG-07 capture — the app's own SCREENSHOT SERIES (docs/restoration/gates.md SG-07).
##
## WHY IT EXISTS: the mockup's renders (`design/renders/<skin>/*.png`) are GENERATED from the
## design package and are always current; the APP had no series at all. The only app frames in
## the tree came from a role smoke that last ran a day earlier, so `side_by_side.py` compared
## today's mockup against yesterday's build - the HG-11 defect with a picture instead of a number.
##
## This scene photographs the shipping application itself: it boots the REAL `MainScript`, drives
## it to a named state through the same seams the behavioral gates use, and saves the root
## viewport as PNG. It does NOT re-prove behaviour (HG-02/05/07/13 do that); it produces the
## material a human reviews. The verdict about the frames (blank? stale? right size?) belongs to
## the shell wrapper `tools/ci/gates/sg07_shots_gate.sh`.
##
## NOT headless: real pixels are required (headless textures are blank) - the wrapper runs Godot
## with `--rendering-driver opengl3` and a real window.
##
## Usage:
##   godot --path game --rendering-driver opengl3 res://tools/gates/sg07_capture.tscn -- \
##         --seq=<pre|invite|match|over|compact|observer|admin> --skin=<id> --outdir=<abs dir>
##
## Prints one `SG-07 CAPTURED <state> <path> <w>x<h> skin=<id>` line per state it reached and
## `SG-07 DONE seq=<seq> skin=<id> states=<n>`, then quits 0. A state it could not reach inside
## its budget is printed as `SG-07 MISS <state> <reason>` - the wrapper decides whether that is
## tolerable (it is not: the series is the gate).
const MainScript := preload("res://main.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const I18n := preload("res://i18n/i18n.gd")

## How long a state may take to appear before it is declared missed. The match walk waits for
## the engine's own phases; the AI moves at its own pace.
const STEP_BUDGET_MS := 45000
## Frames to let a newly opened sheet/animation settle before the shutter.
const SETTLE := 14

var _seq := "pre"
var _skin := ""
var _outdir := "user://renders"
var _launcher = null
var _human := 0
var _shots := 0
var _misses: Array = []
var _t0 := 0
var _done := false


## Nothing in this scene may hang: the shell would report a killed capture as an environment
## SKIP and the series would quietly lose a state. The watchdog turns a hang into a verdict line.
const WATCHDOG_MS := 240000


func _process(_dt: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_miss("watchdog", "the capture did not finish in %ds" % (WATCHDOG_MS / 1000))
		_finish()


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1440, 900))
	get_tree().root.size = Vector2i(1440, 900)
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seq="):
			_seq = s.substr(6)
		elif s.begins_with("--skin="):
			_skin = s.substr(7)
		elif s.begins_with("--outdir="):
			_outdir = s.substr(9)
	DirAccess.make_dir_recursive_absolute(_outdir)
	if _skin != "":
		SkinManager.chosen = _skin
	_t0 = Time.get_ticks_msec()
	_launcher = MainScript.new()
	add_child(_launcher)
	_run()


func _run() -> void:
	await _frames(12)
	_human = _derive_human()
	match _seq:
		"pre":
			await _seq_pre()
		"invite":
			await _seq_invite()
		"match":
			await _seq_match()
		"compact":
			await _seq_compact()
		"observer":
			await _seq_match_like("observer")
		"admin":
			await _seq_match_like("admin")
		"over":
			await _seq_over()
		_:
			_fail("unknown sequence `%s`" % _seq)
			return
	_finish()


## --- sequences ------------------------------------------------------------------------------

## The launcher: the cold board with nothing on it, the settings sheet, and the join screen a
## friend sees when the link carries no seat.
func _seq_pre() -> void:
	var overlay = _launcher.get("_overlay")
	if overlay != null:
		(overlay as Control).visible = false
	await _frames(SETTLE)
	await _shoot("cold")
	if overlay != null:
		_launcher.call("_open_overlay")
		await _frames(SETTLE)
		await _shoot("settings")
		(overlay as Control).visible = false
	_launcher.call("_open_join_lobby")
	await _frames(SETTLE + 6)
	await _shoot("join-none")


## The host's invitation screen: the real ws:// address and the seat tokens the server minted.
func _seq_invite() -> void:
	_launcher.call("_on_host_invite")
	var invite = null
	for _i in range(300):
		invite = _launcher.get("_host_invite")
		if invite != null and is_instance_valid(invite):
			break
		await _frames(1)
	if invite == null or not is_instance_valid(invite):
		_miss("invite", "the invitation screen never appeared")
		return
	await _frames(SETTLE)
	await _shoot("invite")


## A real match, walked through the states a player lives in.
##
## THE ORDER MATTERS, and it is the order a real player lives in: the human's turn, their sheets, a
## bot's turn after they roll, and only THEN the purchase decision and the auction. The auction is
## LAST on purpose: once it opens the human is the first bidder and the table legitimately waits for
## a person who is not there, so nothing may be photographed after it. (The previous revision closed
## the bid sheet and waited for a bot's turn that could never come - and hung on the wait.)
func _seq_match() -> void:
	_launcher.call("_autostart")
	await _frames(20)
	# THE SEAT LIST EXISTS ONLY AFTER THE MATCH IS BUILT: deriving the human at boot read an empty
	# cache and fell back to "seat 0 by convention" - and in the default fixture a BOT is seat 0
	# while the human is seat 1, so the walk waited 45s for a turn that was already on screen.
	_human = _derive_human()
	_freeze_decision_timers()
	var gv = _game_view()
	if gv == null:
		_miss("turn-human", "no game view after autostart")
		return
	# 1. the human's own turn: the decision bar is up
	if not await _reach("turn-human", 45.0):
		return
	await _shoot("turn-human")
	# 2. the trade sheet (the real entry point the console button calls)
	gv.call("_on_action", "propose_trade", {})
	await _frames(SETTLE + 6)
	_note("trade state: %s" % _modal_desc())
	await _shoot("trade")
	_close_modal()
	# 3. the inspector with a tile selected
	var insp = gv.find_child("inspector", true, false)
	if insp != null:
		insp.call("select", 1)
		await _frames(SETTLE)
		await _shoot("inspector")
		insp.call("clear")
	# 4. roll normally: the turn passes and a BOT plays - the board from the other side of the table
	_note("roll -> %s" % _press("roll"))
	if not await _reach("ai", 60.0):
		return
	await _shoot("ai")
	# 5. the human's next turn, then a purchase decision forced onto a real purchasable tile
	if not await _reach("turn-human", 90.0):
		return
	var target := _pick_unowned_reachable()
	if target < 0:
		_miss("purchase", "no unowned purchasable tile is reachable")
		return
	var step := _dice_step_to(target)
	if step < 0:
		_miss("purchase", "the target tile is not reachable with two dice")
		return
	_engine().call("_force_dice", step, _d1_for(step), step - _d1_for(step), false)
	_note("roll -> %s (forced dice onto tile %d)" % [_press("roll"), target])
	if not await _reach("purchase", 30.0):
		return
	_note("purchase state: phase=%s tile=%d" % [str(_engine().phase), target])
	await _shoot("purchase")
	# 6. the auction: declining opens it (auctions_on_refusal) and the human bids first - the walk
	#    STOPS here, because the next move belongs to the player (see the note above the function).
	_note("decline -> %s (phase now %s)" % [_press("pass"), str(_engine().phase)])
	if not await _reach("auction", 20.0):
		return
	# The bid sheet is NOT thrown at the player: they ask for it with the console's BID, which is
	# also how the HG-02 gate reaches it. Press it, then photograph the sheet.
	_note("bid -> %s" % _press("bid"))
	await _soft_wait(func() -> bool:
		var m = _modal()
		return m != null and (m as Control).visible and str(m.get("kind")) == "auction", 15.0)
	_note("auction state: phase=%s %s" % [str(_engine().phase), _modal_desc()])
	await _shoot("auction")

## The end of a match. A SEPARATE run: with a human seat in the walk above, the match waits for a
## keyboard that is not there, so the finish is photographed by a run that lets the host play its
## own seats (`--smoke-drive --round-limit=N`), which is also what the perf smoke does.
func _seq_over() -> void:
	_launcher.call("_autostart")
	await _frames(20)
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		var e = _engine()
		if e != null and str(e.phase) == "END_GAME":
			await _frames(SETTLE + 6)
			_note("end of match: phase=%s round=%d %s" % [str(e.phase), int(e.round_no), _modal_desc()])
			await _shoot("win")
			return
		await _frames(6)
	_miss("win", "the match did not reach END_GAME inside the budget")


## The compact profile: the same app in a small window (rails + drawers replace the docks).
func _seq_compact() -> void:
	_launcher.call("_autostart")
	await _frames(30)
	_human = _derive_human()
	_freeze_decision_timers()
	DisplayServer.window_set_size(Vector2i(880, 600))
	get_tree().root.size = Vector2i(880, 600)
	await _frames(SETTLE + 20)
	var gv = _game_view()
	if gv != null and gv.has_method("_sync_all"):
		gv.call("_sync_all")
	await _frames(SETTLE)
	if not await _reach("compact", 30.0):
		return
	await _shoot("compact")


## The two other roles: an observer window and the admin panel over a live match.
func _seq_match_like(state: String) -> void:
	_launcher.call("_autostart")
	await _frames(40)
	_human = _derive_human()
	_freeze_decision_timers()
	if state == "admin":
		var panel = _launcher.get("_panel")
		if panel == null:
			_miss("admin", "this role built no admin panel")
			return
		(panel as Control).visible = true
		(panel as Control).move_to_front()
		await _frames(SETTLE + 10)
	await _reach_human_or_bot(30.0)
	await _frames(SETTLE)
	await _shoot(state)


## --- driving ---------------------------------------------------------------------------------

## Wait until the human's decision point is on screen; the state is what the shutter needs.
func _reach(state: String, budget_s: float) -> bool:
	if state == "turn-human":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "TURN_START" and int(e.turn_player) == _human, budget_s, state)
	if state == "purchase":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "PURCHASE_WAIT", budget_s, state)
	if state == "auction":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "AUCTION", budget_s, state)
	if state == "ai":
		return await _wait_for(func() -> bool:
			var e = _engine()
			return e != null and str(e.phase) == "TURN_START" and int(e.turn_player) != _human, budget_s, state)
	if state == "compact":
		return await _wait_for(func() -> bool:
			var gv = _game_view()
			return gv != null and bool(gv.call("_is_compact")), budget_s, state)
	return true


func _reach_human_or_bot(budget_s: float) -> void:
	await _wait_for(func() -> bool:
		var e = _engine()
		return e != null and str(e.phase) != "SETUP", budget_s, "match")


func _wait_for(cond: Callable, budget_s: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await _frames(1)
	_miss(label, "not reached within %.0fs (engine phase=%s, turn_player=%s, human=%d, seats=%s)"
		% [budget_s, str(_engine_phase()), str(_engine_turn()), _human, _seats_desc()])
	return false


func _engine_turn() -> String:
	var e = _engine()
	return str(int(e.turn_player)) if e != null else "?"


## The match's own seat list in words - a capture that cannot find the human's turn has to say who
## IS holding it, or the reason line is a guess.
func _seats_desc() -> String:
	var seats: Array = _launcher.get("_seats_cache")
	var out: Array = []
	for s in seats:
		out.append("%d:%s/%s" % [int(s.pid), str(s.name), str(s.input_driver)])
	return ", ".join(out) if not out.is_empty() else "none cached"


## --- the shutter ----------------------------------------------------------------------------

## Photograph the CURRENT state under the skin this run was launched with. A frame the engine drew
## but the OS never composited (an occluded window) comes out flat; that is retried a few times
## here and then REPORTED, not swallowed - the verdict belongs to the shell wrapper, which measures
## the file it can actually read (a blank frame must be a red gate, not a missing state).
func _shoot(state: String) -> void:
	await _frames(SETTLE)
	var path := "%s/%s_%s.png" % [_outdir, state, SkinManager.chosen]
	var img := await _grab()
	var tries := 0
	while _is_flat(img) and tries < 4:
		tries += 1
		await _frames(20)
		img = await _grab()
	var flat := _is_flat(img)
	var err := img.save_png(path)
	if err != OK:
		_miss(state, "save_png failed rc=%d" % err)
		return
	_shots += 1
	print("SG-07 CAPTURED %s %s %dx%d skin=%s flat=%d"
		% [state, path, img.get_width(), img.get_height(), SkinManager.chosen, 1 if flat else 0])


## The shutter. NO `await RenderingServer.frame_post_draw` here on purpose: a window the OS stops
## compositing stops emitting that signal, and the coroutine waited for it forever - the capture
## hung until the shell's timeout killed it (observed: `match/neuro` died with no verdict line).
## The frame that IS drawn is read straight from the viewport instead.
func _grab() -> Image:
	return get_viewport().get_texture().get_image()


## A flat frame is one the compositor never filled. The grid is deliberately FINER than a
## "is it one colour" test: a legitimate screen can be 99% background and still carry a few
## hundred pixels of text (`join-none` measured 1289748/1296000 background pixels and passed),
## and a coarse sampler called that blank. The real verdict on blankness lives in the wrapper.
func _is_flat(img: Image) -> bool:
	if img == null:
		return true
	var seen := {}
	var step: int = 6
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			seen[img.get_pixel(x, y).to_rgba32()] = true
			if seen.size() > 12:
				return false
			x += step
		y += step
	return true


## --- engine helpers (the same seams the behavioral gates use) --------------------------------

## WHO PLAYS HERE - the same rule the view uses (`input_driver` LOCAL/ADMIN, not "seat 0 by
## convention"): the engine's first turn goes to a RANDOM player, so a hard-coded 0 waited for a
## human turn that was never coming while the phase already said TURN_START.
func _derive_human() -> int:
	var seats: Array = _launcher.get("_seats_cache")
	for s in seats:
		var d := str(s.input_driver)
		if d == "LOCAL" or d == "ADMIN":
			return int(s.pid)
	var gv = _game_view()
	if gv != null and int(gv.get("_human_pid")) >= 0:
		return int(gv.get("_human_pid"))
	return 0


func _game_view():
	return _launcher.get("_game_view")


func _engine():
	return _launcher.get("_engine")


func _engine_phase() -> String:
	var e = _engine()
	return str(e.phase) if e != null else "?"


## Press a REAL console button by its action key - the same path a player's finger takes, and
## the one HG-02 proved opens an auction. `gv._on_action()` would call the shell's entry point
## directly and skip whatever bookkeeping the console does around the press.
func _press(key: String) -> String:
	var gv = _game_view()
	if gv == null:
		return "no-view"
	var console = gv.find_child("act", true, false)
	if console == null:
		return "no-console"
	var row = console.get("_btn_row")
	if row == null:
		return "no-button-row"
	var want := I18n.t(_label_key(key))
	for c in row.get_children():
		if c is Button and str((c as Button).text).begins_with(want):
			(c as Button).emit_signal("pressed")
			return "pressed"
	return "absent"


func _label_key(key: String) -> String:
	match key:
		"roll":
			return "act.roll"
		"pass":
			return "act.no_buy"
		"buy":
			return "act.buy"      # NOT act.buy_price: that template carries $%d
	return key


func _close_modal() -> void:
	var gv = _game_view()
	if gv == null:
		return
	var modal = gv.find_child("modal", true, false)
	if modal != null and (modal as Control).visible:
		modal.call("close")


## The first unowned property/railroad/utility reachable from the human's position.
func _pick_unowned_reachable() -> int:
	var e = _engine()
	if e == null:
		return -1
	var pos: int = int(e.players[_human].position)
	var board = e.board
	var count: int = board.tile_count()
	for k in range(2, 13):
		var idx: int = (pos + k) % count
		var t = board.tile_at(idx)
		var ttype := str(t.get("type", ""))
		if ttype in ["property", "railroad", "utility"] and int(e._owner_of(idx)) == -1:
			return idx
	return -1


func _dice_step_to(target: int) -> int:
	var e = _engine()
	if e == null:
		return -1
	var count: int = e.board.tile_count()
	var step: int = (target - int(e.players[_human].position) + count) % count
	# 0 and 1 are not rollable (and a double-1 is a jail roll): take the same tile one lap later
	if step < 2:
		step += count
	return step if step <= 12 else -1


func _d1_for(step: int) -> int:
	return 6 if step >= 7 else int(floor(step / 2.0))


## A CAPTURE CANNOT RACE A CLOCK. The human's decision window defaults to 30s, so the first
## revision photographed whatever the timer had already done to the turn ("roll -> absent" - the
## buttons were gone) and needed 2.5 minutes to catch five states. Zero is the engine's own
## "no timeout" value (`seat_manager._maybe_timeout` returns early on it): the bots still play on
## their own delay, but a human decision now WAITS for the person - which is the state on film.
func _freeze_decision_timers() -> void:
	var e = _engine()
	if e == null or e.settings == null:
		return
	e.settings.turn_timer = 0
	e.settings.auction_timer = 0
	_note("decision timers frozen (turn_timer=%d auction_timer=%d)"
		% [int(e.settings.turn_timer), int(e.settings.auction_timer)])


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


## What is on screen right now, in words - the report has to be able to say WHY a frame is
## believed to show what its name claims (a series of pictures nobody can name is not evidence).
func _modal():
	var gv = _game_view()
	return gv.find_child("modal", true, false) if gv != null else null


func _modal_desc() -> String:
	var modal = _modal()
	if modal == null:
		return "no modal"
	return "modal kind=%s visible=%s" % [str(modal.get("kind")), str((modal as Control).visible)]


## Wait for a sheet to appear, but never fail over it: some states are worth photographing with or
## without their sheet, and the NOTE line says which one was on screen.
func _soft_wait(cond: Callable, budget_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(budget_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return
		await _frames(2)


func _note(msg: String) -> void:
	print("SG-07 NOTE " + msg)


func _miss(state: String, reason: String) -> void:
	_misses.append("%s: %s" % [state, reason])
	print("SG-07 MISS %s %s" % [state, reason])


func _fail(msg: String) -> void:
	_misses.append(msg)
	print("SG-07 MISS %s" % msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("SG-07 DONE seq=%s skin=%s states=%d in %dms (misses=%d)"
		% [_seq, SkinManager.chosen, _shots, Time.get_ticks_msec() - _t0, _misses.size()])
	get_tree().quit(0 if _misses.is_empty() else 1)
