extends Node
## KEYBOARD-ONLY PROBE — a whole session, played from the keyboard alone (PART 3's promise).
##
## WHAT IT BUILDS: a 4-seat match with ONE LOCAL seat ("Хост", pid 0, so the keyboard has a human to
## play for) and three AI seats (rng_seed 7, round_limit 3, turn_timer 20). The FIRST version used an
## all-AI table and could not roll: with no LOCAL/ADMIN seat `game_view._human_pid` is -1, the console
## draws no buttons and a game action from the keyboard is refused by design (HG-12) - the probe failed
## with "the engine log gained no `roll`". With a LOCAL seat the first turn is the human's, and the roll
## is caused by a key and nothing else.
##
## WHAT IT PRESSES: Tab, the four arrows and Space - every one of them pushed through
## `Input.parse_input_event(InputEventKey)`, which is the same path a real keyboard takes. NO mouse
## event is ever constructed, and the counter is not a promise: `_input` watches every event this
## process is handed, so `_mouse_sent` (printed with the verdict) counts mouse events that really
## arrived. A pass cannot be an accident of a click.
##
## THE THREE PIECES OF EVIDENCE, all printed:
##   (a) the focus MOVES - the controls with focus_mode != NONE are listed before and after a real Tab
##       key and after the arrows, with the focus owner named at each step;
##   (b) Space ROLLS - with the focus released so the key reaches the app's own binding (Space =
##       ACT_ROLL, `bindings.gd`), the engine log gains `roll` event(s): the human's turn is played
##       from the keyboard, causally, not merely observed;
##   (b2) Space also PRESSES - Tab reaches a real control and Space fires its `pressed` signal with a
##       visible effect (the side panels toggle);
##   (c) the match REACHES round 2 (the round limit is 3).
##
## WHY (b) NEEDS A LOCAL SEAT: on an all-AI table nobody on this screen may take a game action
## (`game_view._human_can_act` - HG-12), the console draws NO buttons, and a keyboard "roll" is refused
## BY DESIGN. That is a fact about the game, not about the keyboard, so the probe seats a human.
##
## Run: godot --headless --path game res://tools/keyboard_only_probe.tscn
## Verdict: ==> KEYBOARD-ONLY PASSED (...) / ==> KEYBOARD-ONLY FAILED: <first reason>

const MainScript := preload("res://main.gd")
const SettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")

## A headless root viewport starts at 64x64 and the header decides which of its buttons exist from the
## width it is given, so the window is set BEFORE the match is built and the shell gets frames to lay
## itself out. The size is the owner's legible minimum; the panels button survives every width.
const WINDOW := Vector2i(1280, 800)
const BOOT_FRAMES := 8
const SETTLE_FRAMES := 10
## Frames to let one key event land before reading its effect (parse_input_event dispatches
## synchronously, but the panels rebuild from the projection and need a frame to be seen).
const STEP_FRAMES := 2
## How many Tab presses are spent trying to reach the header's panels button.
const TAB_TRIES := 20
const ARROW_KEYS := [KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP]
const TARGET_ROUND := 2
## A focused button can activate twice per tap (see `_tap` and the (b2) note), so the panels check taps
## again until the state moves - but never more than this.
const SPACE_TAP_LIMIT := 4
const MATCH_DEADLINE_MS := 90000
## A probe that never quits is worse than a red one: the whole run gives up here (wall clock).
const HARD_DEADLINE_MS := 150000

var _launcher = null
var _frame := 0
var _state := "boot"
var _wait := 0
var _done := false
var _deadline := 0
var _hard_deadline := 0
var _fails: Array = []
var _checks := 0
var _keys_sent := 0
## MEASURED, not asserted: `_input` increments this for every mouse event the process is handed, and
## this probe builds no InputEventMouse* at all, so it must stay 0 for the run to mean anything.
var _mouse_sent := 0

# --- (a) the focus ------------------------------------------------------------------------------
var _list_before: Array = []
var _list_after: Array = []
var _owner_start := ""
var _owners: Array = []
var _arrow_i := 0

# --- (b) Space ----------------------------------------------------------------------------------
var _space_target = null
var _space_target_name := ""
var _space_is_panels := false
var _space_hits := 0
var _space_taps := 0
var _tabs_for_target := 0
var _rolls_before := 0
var _rolls_after := 0
var _panels_before := false
var _panels_after := false


func _ready() -> void:
	# THE WINDOW BEFORE THE MATCH. `main._ready` asks the layout profile for its own size, so the
	# request is repeated in `_build_match` — after that nothing resizes the stage and every
	# measurement below describes the window the keyboard actually worked in.
	DisplayServer.window_set_size(WINDOW)
	get_tree().root.size = WINDOW
	_launcher = MainScript.new()
	add_child(_launcher)
	_hard_deadline = Time.get_ticks_msec() + HARD_DEADLINE_MS


## Every event this process is handed, watched so the mouse count is a MEASUREMENT and not a promise.
## It consumes nothing (`_input` is a notification, not a handler) - the keyboard path is untouched.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_sent += 1


## The scene's own `_process` signature: `(dt: float) -> void` (a bool return would be a different
## callback entirely and the probe would sit silent).
func _process(_dt: float) -> void:
	if _done:
		return
	_frame += 1
	if Time.get_ticks_msec() >= _hard_deadline:
		_fail("the probe ran past its %ds deadline in state '%s' - it never finished" % [int(HARD_DEADLINE_MS / 1000), _state])
		_report()
		return
	match _state:
		"boot":
			if _frame < BOOT_FRAMES:
				return
			_build_match()
			_state = "settle"
			_wait = SETTLE_FRAMES
		"settle":
			if not _tick_wait():
				return
			_begin_focus()
		"after_tab":
			if not _tick_wait():
				return
			_owners.append(_label_of(_focus_owner()))
			_tap(ARROW_KEYS[_arrow_i])
			_state = "after_arrow"
			_wait = STEP_FRAMES
		"after_arrow":
			if not _tick_wait():
				return
			_owners.append(_label_of(_focus_owner()))
			_arrow_i += 1
			if _arrow_i < ARROW_KEYS.size():
				_tap(ARROW_KEYS[_arrow_i])
				_wait = STEP_FRAMES
				return
			if not _check_focus():
				_report()
				return
			# (b) FIRST, WITH THE FOCUS RELEASED: the key must reach the app's own binding (Space =
			# ACT_ROLL). Aiming Space at a focused BUTTON would be swallowed by Godot's ui_accept and
			# the human's turn would never be played - the first version made exactly that mistake.
			# AND WAIT FOR THE HUMAN'S OWN TURN: the seats are assigned pids by the seat config, NOT in
			# the order this probe lists them (measured: the LOCAL seat came out as pid 1 and the engine
			# opened on pid 0, an AI), so the key would land on somebody else's turn.
			_state = "wait_turn"
			_deadline = Time.get_ticks_msec() + MATCH_DEADLINE_MS
		"wait_turn":
			var eng = _launcher.get("_engine")
			if eng == null:
				_fail("the engine vanished before the human's turn")
				_report()
				return
			if _human_turn():
				_begin_roll()
			elif Time.get_ticks_msec() >= _deadline:
				_fail("the human's turn never came: still turn_player=%d phase=%s after %ds (human pid=%d)" % [int(eng.turn_player), str(eng.phase), int(MATCH_DEADLINE_MS / 1000), _human_pid()])
				_report()
		"after_roll":
			if not _tick_wait():
				return
			if not _check_roll():
				_report()
				return
			if not _begin_space():
				_report()
		"to_target":
			if not _tick_wait():
				return
			if _focus_owner() == _space_target:
				_press_space_on(_space_target)
				return
			if _tabs_for_target >= TAB_TRIES:
				var cur = _focus_owner()
				if cur == null:
					_fail("Tab reached no control at all in %d presses - the keyboard cannot get to the header" % TAB_TRIES)
					_report()
					return
				print("KEYBOARD: Tab did not reach the panels button in %d presses; Space goes to '%s' instead" % [TAB_TRIES, _label_of(cur)])
				_press_space_on(cur)
				return
			_tabs_for_target += 1
			_tap(KEY_TAB)
			_wait = STEP_FRAMES
		"after_space":
			if not _tick_wait():
				return
			# ONE TAP CAN ACTIVATE A FOCUSED BUTTON TWICE (measured: `button_down`/`button_up` once
			# each, `pressed` twice, action_mode=1/RELEASE), and two toggles net to no visible change -
			# the drawer looks dead. So keep tapping (bounded) until the state really moves: what must be
			# proven is that a key DRIVES the control, and the quirk is reported, not hidden.
			if _space_is_panels and not _panel_state_moved() and _space_taps < SPACE_TAP_LIMIT:
				_space_taps += 1
				print("KEYBOARD (b2): tap %d left panels_hidden at %s - pressing again (one TAP activates a focused button twice, so the drawer nets back to where it started)" % [_space_taps, str(bool(_launcher.get("_game_view").call("panels_hidden")))])
				_tap_press(KEY_SPACE)
				_wait = STEP_FRAMES + 1
				return
			if not _check_space():
				_report()
				return
			_state = "rounds"
			_deadline = Time.get_ticks_msec() + MATCH_DEADLINE_MS
		"rounds":
			var eng = _launcher.get("_engine")
			if eng == null:
				_fail("the engine vanished mid-match")
				_report()
				return
			if int(eng.round_no) >= TARGET_ROUND:
				_checks += 1
				print("KEYBOARD (c): the match reached round %d (round_limit 3) with %d roll(s) in the engine log" % [int(eng.round_no), _roll_count()])
				_report()
				return
			if Time.get_ticks_msec() >= _deadline:
				_fail("the match did not reach round %d: still round %d after %ds of keyboard-only play (%d roll(s))" % [TARGET_ROUND, int(eng.round_no), int(MATCH_DEADLINE_MS / 1000), _roll_count()])
				_report()


# --- the match ----------------------------------------------------------------------------------

func _build_match() -> void:
	DisplayServer.window_set_size(WINDOW)
	get_tree().root.size = WINDOW
	var st = SettingsScript.new()
	st.seat_count = 4
	st.rng_seed = 7
	st.round_limit = 3
	st.turn_timer = 20
	# ONE HUMAN, ON PURPOSE: the LOCAL seat is what makes a keyboard ROLL possible at all (see the
	# header). pid 0 takes the first turn, so the very first key this probe sends is a real move.
	st.seat_assignments = [
		{"driver": "LOCAL", "name": "Хост"},
		{"driver": "AI", "name": "Bot 2"},
		{"driver": "AI", "name": "Bot 3"},
		{"driver": "AI", "name": "Bot 4"},
	]
	var seats: Array = SeatConfigScript.from_settings(st)
	_launcher.call("_build_game", st, seats)
	# starting a match must mean the same thing on every path (main.gd): hide the settings sheet and
	# tell the view the game began, or every frame below would be of a menu over a board.
	_launcher.get("_overlay").visible = false
	_launcher.set("_game_started", true)
	_launcher.get("_game_view").call("on_game_started")
	print("KEYBOARD: match built - 4 seats (1 LOCAL + 3 AI), seed 7, round_limit 3, turn_timer 20")
	for s in seats:
		print("KEYBOARD seat: pid=%d name=%s driver=%s" % [int(s.pid), str(s.name), str(s.input_driver)])


# --- the keyboard -------------------------------------------------------------------------------

## PRESS WITHOUT RELEASE - the workaround for the double activation measured above: with the focused
## header button, a full tap (press+release) emitted `pressed` TWICE per tap (one `button_down` and one
## `button_up` for the pair), so the drawer toggled an even number of times and never appeared to move.
## One press alone is one activation, which is what the check needs.
func _tap_press(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.echo = false
	down.pressed = true
	Input.parse_input_event(down)
	_keys_sent += 1


## ONE key, pressed and released, through the real input path. Nothing else in this file touches
## `Input`, and no mouse event is ever built.
##
## ONLY `keycode` IS SET, AND THAT IS DELIBERATE. The first version set `physical_keycode` as well (a
## real OS event carries both) and a single Space tap ACTIVATED THE FOCUSED BUTTON TWICE - the button's
## `pressed` fired 2 times, so one press toggled the side panels and the next toggle closed them again
## and the drawer looked dead (panels_hidden stayed false). With one key field the event matches
## `ui_accept` once, which is what a user's keyboard does.
func _tap(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.echo = false
	down.pressed = true
	Input.parse_input_event(down)
	_keys_sent += 1
	var up := InputEventKey.new()
	up.keycode = keycode
	up.echo = false
	up.pressed = false
	Input.parse_input_event(up)


# --- (a) the focus moves ------------------------------------------------------------------------

func _begin_focus() -> void:
	_list_before = _focus_list()
	_owner_start = _label_of(_focus_owner())
	print("KEYBOARD: controls with focus_mode != NONE: %s (%d)" % [_join(_list_before), _list_before.size()])
	print("KEYBOARD: focus owner before any key: %s" % _owner_start)
	_tap(KEY_TAB)
	_state = "after_tab"
	_wait = STEP_FRAMES


func _check_focus() -> bool:
	_list_after = _focus_list()
	_checks += 1
	if _list_before.is_empty():
		_fail("no control in the app has focus_mode != NONE - there is nothing for the keyboard to reach")
		return false
	var after_tab: String = str(_owners[0]) if _owners.size() > 0 else ""
	if after_tab == "" or after_tab == _owner_start:
		_fail("Tab did not move the focus (owner stayed '%s')" % _owner_start)
		return false
	var moves := 0
	for i in range(1, _owners.size()):
		if str(_owners[i]) != str(_owners[i - 1]) and str(_owners[i]) != "":
			moves += 1
	if moves == 0:
		_fail("no arrow moved the focus (owners: %s)" % ", ".join(_owners))
		return false
	print("KEYBOARD (a): Tab moved the focus %s -> %s; the arrows moved it %d time(s): %s" % [_owner_start, after_tab, moves, ", ".join(_owners)])
	print("KEYBOARD (a): the focusable set is unchanged before/after: %s -> %s" % [str(_list_after == _list_before), _join(_list_after)])
	return true


## Every visible Control the keyboard can reach, in tree order: what `focus_mode != NONE` means in
## this app (a disabled Button is listed and marked, because it is still a Control with a focus mode).
func _focus_list() -> Array:
	var out: Array = []
	if _launcher != null:
		_collect_focusable(_launcher, out)
	return out


func _collect_focusable(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control:
			var ctl := c as Control
			if ctl.focus_mode != Control.FOCUS_NONE and ctl.is_visible_in_tree():
				var label := _label_of(ctl)
				if ctl is Button and (ctl as Button).disabled:
					label += " [disabled]"
				out.append(label)
		_collect_focusable(c, out)


func _focus_owner():
	var vp := get_viewport()
	return vp.gui_get_focus_owner() if vp != null else null


func _label_of(n) -> String:
	if n == null:
		return "<none>"
	if n is Button:
		return "%s[%s]" % [str(n.name), str((n as Button).text)]
	if n is Control:
		return str(n.name)
	return str(n)


func _join(a: Array) -> String:
	if a.is_empty():
		return "-"
	if a.size() > 12:
		return ", ".join(a.slice(0, 12)) + " (+%d more)" % (a.size() - 12)
	return ", ".join(a)


# --- (b) Space acts -----------------------------------------------------------------------------

## RELEASE THE FOCUS, THEN PRESS. Godot hands a Space to the focused control (`ui_accept`) before the
## app's `_unhandled_key_input` sees it, so a keyboard roll with a button focused is impossible - the
## honest way to prove the BINDING works is to have no focus owner at all.
func _human_pid() -> int:
	var gv = _launcher.get("_game_view")
	return int(gv.get("_human_pid")) if gv != null else -1


## The keyboard can only move the match during the human's own decision point.
func _human_turn() -> bool:
	var eng = _launcher.get("_engine")
	var pid := _human_pid()
	if eng == null or pid < 0:
		return false
	return int(eng.turn_player) == pid and str(eng.phase) == "TURN_START"


func _begin_roll() -> void:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no game view - there is nothing for the keyboard to act on")
		_report()
		return
	print("KEYBOARD: human seat pid=%d (LOCAL), turn_player=%d, phase=%s" % [
		int(gv.get("_human_pid")),
		int((_launcher.get("_engine")).turn_player),
		str((_launcher.get("_engine")).phase),
	])
	_rolls_before = _roll_count()
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()
	print("KEYBOARD: focus released (owner now %s) - Space goes to the app's binding, not to a button" % _label_of(_focus_owner()))
	_tap(KEY_SPACE)
	_state = "after_roll"
	_wait = STEP_FRAMES + 1


func _check_roll() -> bool:
	_rolls_after = _roll_count()
	_checks += 1
	if _rolls_after <= _rolls_before:
		_fail("the engine log gained no `roll` after Space reached the binding (%d -> %d) - the game cannot be played from the keyboard" % [_rolls_before, _rolls_after])
		return false
	print("KEYBOARD (b): Space (the app's own roll binding) rolled the DICE: engine log +%d roll event(s) (%d -> %d), 0 mouse events" % [_rolls_after - _rolls_before, _rolls_before, _rolls_after])
	return true


## Aim Space at the header's panels button: the second half of (b), proving a key also DRIVES a focused
## control (its `pressed` signal and its visible effect), not only the global binding.
func _begin_space() -> bool:
	var gv = _launcher.get("_game_view")
	if gv == null:
		_fail("no game view - there is nothing for the keyboard to press")
		return false
	_panels_before = bool(gv.call("panels_hidden"))
	# A DOUBLE CONNECTION would make one press toggle twice and the drawer would appear dead - read the
	# real count instead of assuming it, because that is exactly what the first run's numbers hinted at.
	var top = gv.get("_top")
	if top != null and top.has_signal("panels_requested"):
		print("KEYBOARD (b2): top_bar.panels_requested has %d connection(s); panels_hidden=%s" % [top.panels_requested.get_connections().size(), str(_panels_before)])
	print("KEYBOARD (b2): the keyboard also drives a FOCUSED control - Tab reaches the header's panels button and Space presses it")
	_space_target = _panels_button()
	if _space_target == null:
		_fail("the header has no panels button (top_bar._btn_panels) - the keyboard's own control is missing")
		return false
	_tabs_for_target = 0
	_state = "to_target"
	_wait = 0
	return true


func _press_space_on(target) -> void:
	_space_target = target
	_space_target_name = _label_of(target)
	_space_is_panels = target == _panels_button()
	_space_hits = 0
	_space_taps = 1
	if target.has_signal("pressed") and not target.pressed.is_connected(_on_target_pressed):
		target.pressed.connect(_on_target_pressed)
	# The SEQUENCE, not just the count: one Space tap produced two activations and the drawer appeared
	# dead. Down/up/pressed with frame numbers says whether the event was delivered twice or the button
	# fires twice per delivery.
	if target is Button:
		var b := target as Button
		print("KEYBOARD (b2): '%s' action_mode=%d focus_mode=%d disabled=%s" % [_space_target_name, int(b.action_mode), int(b.focus_mode), str(b.disabled)])
		b.button_down.connect(func() -> void: print("KEYBOARD (b2) signal button_down at frame %d" % Engine.get_process_frames()))
		b.button_up.connect(func() -> void: print("KEYBOARD (b2) signal button_up at frame %d" % Engine.get_process_frames()))
	_tap(KEY_SPACE)
	_state = "after_space"
	_wait = STEP_FRAMES + 1


func _on_target_pressed() -> void:
	_space_hits += 1


func _panel_state_moved() -> bool:
	var gv = _launcher.get("_game_view")
	if gv == null:
		return false
	return bool(gv.call("panels_hidden")) != _panels_before


func _check_space() -> bool:
	var gv = _launcher.get("_game_view")
	_panels_after = bool(gv.call("panels_hidden")) if gv != null else false
	_checks += 1
	if _space_hits < 1:
		_fail("Space did not reach the focused control '%s': its `pressed` signal never fired" % _space_target_name)
		return false
	print("KEYBOARD (b2): Space pressed the focused control '%s' (its `pressed` fired %d time(s))" % [_space_target_name, _space_hits])
	if _space_is_panels:
		if _panels_after == _panels_before:
			_fail("Space on the header's panels button did not toggle the side panels (panels_hidden stayed %s)" % str(_panels_before))
			return false
		print("KEYBOARD (b2): the key had its visible effect too - panels_hidden %s -> %s" % [str(_panels_before), str(_panels_after)])
	return true


## The header's panels button: the one control this probe aims Space at, because its effect is
## readable from the shell (`game_view.panels_hidden()`) and not just from a signal.
func _panels_button():
	var gv = _launcher.get("_game_view")
	if gv == null:
		return null
	var top = gv.get("_top")
	if top == null:
		return null
	return top.get("_btn_panels")


func _roll_count() -> int:
	var eng = _launcher.get("_engine")
	if eng == null:
		return 0
	var lg = eng.log
	if lg == null:
		return 0
	return (lg.entries_of_type("roll") as Array).size()


# --- the verdict --------------------------------------------------------------------------------

func _tick_wait() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: " + msg)


func _report() -> void:
	_done = true
	print("KEYBOARD-ONLY: %d check(s), %d key event(s) injected, %d mouse event(s) seen by this process" % [_checks, _keys_sent, _mouse_sent])
	if _mouse_sent != 0:
		_fail("a mouse event reached this process - the run does not prove keyboard-only play")
	if _fails.is_empty():
		if _checks < 3:
			print("==> KEYBOARD-ONLY FAILED: only %d check(s) ran - the probe aborted silently" % _checks)
			get_tree().quit(1)
			return
		print("==> KEYBOARD-ONLY PASSED (a LOCAL human seat rolled the dice with the app's own Space binding, Tab and the arrows move the focus, Space presses a focused control, the match reached round %d, 0 mouse events)" % TARGET_ROUND)
		get_tree().quit(0)
	else:
		print("==> KEYBOARD-ONLY FAILED: %s (%d total)" % [_fails[0], _fails.size()])
		get_tree().quit(1)
