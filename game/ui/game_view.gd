extends Control
## The game shell — the v3 interface assembled from the prototype's regions:
##   #top (header) · #seats (left dock) · #stage (board) + #act (console) · #rightcol
##   (toasts · #journal · #inspector) · #modal.
##
## Same outer contract as before the swap (signals + setup/apply_projection/...), so
## main.gd wiring is unchanged. Reads the spectator projection; submits intents through
## the seat manager — the engine still validates everything.

signal restart_requested
signal settings_requested
signal skin_requested(skin_id: String)

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const TopBar := preload("res://ui/top_bar.gd")
const PlayersPanel := preload("res://ui/players_panel.gd")
const ActionPanel := preload("res://ui/action_panel.gd")
const JournalPanel := preload("res://ui/journal_panel.gd")
const JournalLines := preload("res://ui/core/journal_lines.gd")
const KeyboardNav := preload("res://ui/core/keyboard_nav.gd")
const Bindings := preload("res://ui/core/bindings.gd")
const TileInspector := preload("res://ui/tile_inspector.gd")
const ToastList := preload("res://ui/toast.gd")
const ModalHost := preload("res://ui/modal_host.gd")
const BoardScene := preload("res://visual/board_scene.gd")
const BoardCamera := preload("res://ui/components/board_camera.gd")
const SeatManager := preload("res://seats/seat_manager.gd")

## E-2 (master-fix-plan §2, D10): the event kinds that must leave a mark ON THE BOARD. The plan
## lists them: purchase, auction start/win, build, bankruptcy, jail, winner, tax, go bonus, trade.
## These are the moments a viewer following the ring has to be told about; everything else is
## accounting (cash moves, positions) and is carried by the token animation instead.
const BOARD_EVENT_TYPES := [
	"buy", "aucstart", "aucwin", "build", "sell", "bank", "jail", "over", "tax", "go",
	"trade", "trdoffer", "trdno",
]
const SkinManager := preload("res://visual/skin_manager.gd")

const DOCK_L := 268.0
const DOCK_R := 344.0

var _profile = null
var _engine = null
var _mgr = null
var seats: Array = []
var _proj: Dictionary = {}
var _cold := true
var _observer := false
## WHO AM I ON THIS SCREEN. Was hardcoded to 0 (the audit: "на хосте работает случайно; у
## удалённого клиента кнопки не покажутся никогда, а интенты ушли бы за место 0"). Two
## sources: `setup()` derives it from the seat list (the LOCAL/ADMIN seat), and a client that
## joined over the wire is TOLD its pid by the host (`set_human_pid` on JOINED). -1 = nobody
## local plays here: the console offers no buttons, no intent can be sent for anyone.
var _human_pid := -1
## The wire, when this screen is a REMOTE client: buttons then submit through it instead of a
## local manager (a client owns no engine - main._submit used to hit `if _mgr == null: return`
## and the browser's presses went nowhere).
var _remote = null

var _top: Control
var _seats_panel: Control
var _board: Control
var _camera: Control
## ZOOM-01: the turn the camera last followed, so a NEW turn re-follows and the same turn does not
## fight a viewer who panned away.
var _camera_turn := -1
## PART 2: the user hid the side panels (the H key / the header button). Remembered across a
## profile change, and applied by _apply_panels_visibility.
var _panels_hidden := false
## PART 4 (bindings): the resolved {act: keycode} table this screen dispatches on. Seeded from the
## saved overrides at _ready, rewritten by the settings screen.
var _bindings: Dictionary = Bindings.defaults()
## True while the settings screen is waiting for a keypress to bind. The shell then leaves the
## keyboard alone: a key pressed to REBIND must not also act on the match behind the overlay.
var _key_capture := false
var _console: Control
var _journal: Control
var _inspector: Control
var _toasts: Control
var _modals: Control
var _rightcol: Control
var _body_row: Control
## compact profile (design/regions.json): the docks collapse into 48px RAILS; a rail click
## opens the matching 320px DRAWER over the stage with the dock's content inside. The old
## compact profile only HID the docks - the audit's defect - which made the journal, the
## inspector and (through it) all tile management unreachable.
var _rail_right: Control
var _rail_r_journal: Control
var _rail_r_inspector: Control
var _drawers: Dictionary = {}
## SG-06: engine events -> readable journal lines (adapter spans + tile names).
var _journal_lines = JournalLines.new()
## brief §4.1: the last journal sentences, shown inside the ring's panno (the board must say what
## just happened without the side panel). The shell owns the text; board_scene only displays it.
var _board_tail: Array = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# the app paints its own background (proto `.app { background: var(--bg) }`) — without
	# this the window clear colour (grey) showed through every gap in the layout
	var bg := ColorRect.new()
	bg.color = UiTheme.COL().bg
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()


func _build() -> void:
	# PART 4: the keys come from disk before anything reads them, so the very first keystroke uses the
	# player's own bindings rather than the shipped ones.
	_bindings = Bindings.resolved(Bindings.load_saved())
	var outer := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(edge, 8)   # `--gap`
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	var col := UiTheme.vbox(8)
	outer.add_child(col)

	_top = TopBar.new()
	_top.name = "top"
	_top.settings_requested.connect(func() -> void: settings_requested.emit())
	_top.restart_requested.connect(func() -> void: restart_requested.emit())
	_top.skin_requested.connect(func(id: String) -> void: skin_requested.emit(id))
	# PART 2: the header's panels button and the H key do the same thing.
	_top.panels_requested.connect(Callable(self, "toggle_panels"))
	col.add_child(_top)

	var body := UiTheme.hbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_body_row = body

	_seats_panel = PlayersPanel.new()
	_seats_panel.name = "seats"
	_seats_panel.custom_minimum_size.x = DOCK_L
	_seats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_seats_panel)

	# centre column: the STAGE (the board under a camera) with the console under it
	var centre := UiTheme.vbox(8)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(centre)
	# ZOOM-01: the board lives under a camera that can pan and zoom it. The board keeps its own
	# layout (a square that fills this container); the camera transforms the whole thing.
	_camera = BoardCamera.new()
	_camera.name = "stage-camera"
	_camera.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_camera.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_child(_camera)
	_board = BoardScene.new()
	_board.name = "stage"
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.tile_clicked.connect(Callable(self, "_on_tile_clicked"))
	# R-15: the panno's players zone replaces the seats rail; a click on it opens the full cards.
	_board.seats_requested.connect(func() -> void: _open_drawer("seats"))
	_camera.add_child(_board)
	_camera.setup(_board)
	_camera.token_pos_of = Callable(self, "_token_board_pos")
	_console = ActionPanel.new()
	_console.name = "act"
	_console.action_requested.connect(Callable(self, "_on_action"))
	_console.start_requested.connect(func() -> void: settings_requested.emit())
	centre.add_child(_console)

	# right column: toasts, journal, inspector
	_rightcol = UiTheme.vbox(8)
	_rightcol.name = "rightcol"
	_rightcol.custom_minimum_size.x = DOCK_R
	_rightcol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_rightcol)
	_toasts = ToastList.new()
	_toasts.name = "toast"
	_rightcol.add_child(_toasts)
	_journal = JournalPanel.new()
	_journal.name = "journal"
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rightcol.add_child(_journal)
	_inspector = TileInspector.new()
	_inspector.name = "inspector"
	_inspector.action_requested.connect(Callable(self, "_on_inspector_action"))
	_rightcol.add_child(_inspector)

	_build_compact_shell(body)

	_modals = ModalHost.new()
	_modals.name = "modal"
	add_child(_modals)
	# the modals collect PARAMETERS the engine needs; the shell submits them like any button
	_modals.trade_submitted.connect(_on_trade_submitted)
	_modals.trade_answered.connect(_on_trade_answered)
	_modals.auction_bid.connect(_on_auction_bid)
	_modals.auction_pass.connect(_on_auction_pass)

	_apply_profile()
	# SG-08: one switch retranslates everything in place - no rebuild, no stale language
	if not I18n.inst().locale_changed.is_connected(Callable(self, "_on_locale_changed")):
		I18n.inst().locale_changed.connect(Callable(self, "_on_locale_changed"))


func set_profile(pr) -> void:
	_profile = pr
	# a launch role that disables input IS the observer (UiProfile.stream)
	if pr != null and not bool(pr.input_enabled):
		set_observer(true)
	_apply_profile()


## THE OBSERVER ROLE (HG-12 / UiProfile.stream): spectator data, input dead, the journal
## widens to 400px (F-57) because reading is all this screen does. Reached by the launch role
## or by the autodetect above; the console paints the observer status instead of buttons.
func set_observer(v: bool) -> void:
	_observer = v
	if _console != null:
		_console.set_observer(_observer)
	_apply_dock_width()


func _apply_dock_width() -> void:
	if _rightcol != null:
		_rightcol.custom_minimum_size.x = 400.0 if _observer else DOCK_R


func _apply_profile() -> void:
	# THE RAILS ARE THE DEFAULT (owner's relayout, 16.10 evening): "панели — УЗКИЕ рейлы по краям,
	# доска главная на весь центр". Measured before choosing: the board is HEIGHT-limited at every
	# profile but the narrowest, so the 612px the two docks take is mostly spent on width the board
	# could not use anyway - while at 1000x650 the docks starve it to a 328px square (30px cells)
	# where rails leave 490px (45px cells), half again as much board.
	#
	# So the docks are the EXCEPTION, and the exception is stated as a measurement rather than a
	# taste: they open only when the window is wide enough to give the board its full height AND
	# still spare the room. That keeps a big desktop looking like the mockup while every cramped
	# window gets the board instead of two panels with a couple of lines in them.
	var compact := _is_compact()
	_apply_panels_visibility()
	if not compact:
		_close_all_drawers()
	else:
		_layout_drawers()


## Compact/rails from the BOARD's point of view: would the docks cost the board its own size?
##
## The threshold lives in LayoutProfile (`RAILS_BELOW`) so the shell, the gate and the tests read ONE
## home - this is only the name the shell uses for it.
const WIDE_DOCKS_MIN := LayoutProfile.RAILS_BELOW


func _is_compact() -> bool:
	# RAILS BY DEFAULT (owner's relayout, 16.10): the docks now open only on a window wide enough to
	# spare the width - see WIDE_DOCKS_MIN. The old rule (< 1280 or <= 700 tall) kept two 268/344
	# docks on a 1280-wide window where they cost the board the width it needed.
	return size.x > 0.0 and (size.x < WIDE_DOCKS_MIN or size.y <= 700.0)


## PART 2 (the owner's order): hide the side panels with one button/key.
##
## WHY: on a wide window the two docks take 268+344 = 612px of the stage's width, and the owner's
## report is that the space is used illogically - the board is the thing being watched, and side
## panels are reference. One toggle gives the whole width to the board and back.
##
## It hides BOTH sides at once and works in either profile (the docks on a wide window, the 48px
## rails on a compact one), because what the user means by "hide the panels" does not depend on the
## profile the window happens to be in. The choice is REMEMBERED across a profile change: a resize
## re-applies it rather than silently showing the panels again.
signal panels_toggled(hidden: bool)


func toggle_panels() -> void:
	set_panels_hidden(not _panels_hidden)


func panels_hidden() -> bool:
	return _panels_hidden


func set_panels_hidden(hidden: bool) -> void:
	if hidden == _panels_hidden:
		return
	_panels_hidden = hidden
	_apply_profile()
	panels_toggled.emit(hidden)


## The user's panel choice applied on top of the profile layout: the profile decides WHICH control
## represents the side panels (dock or rail); this decides whether it is shown at all.
func _apply_panels_visibility() -> void:
	var compact := _is_compact()
	if _seats_panel != null:
		_seats_panel.visible = (not compact) and not _panels_hidden
	if _rightcol != null:
		_rightcol.visible = (not compact) and not _panels_hidden
	if _rail_right != null:
		_rail_right.visible = compact and not _panels_hidden


## SG-08 — live locale: static labels come back via their `i18n_key` metadata (I18n.relabel
## walks this subtree), state-driven panels re-render from the last state they were given, and
## the compact rails/drawers get their titles re-derived. Nothing here needs a match rebuild.
## HG-13: the B/N badges on the console buttons are promises - the keys press the REAL
## buttons (buy / end turn), on this seat's turn only, exactly like a mouse click.
##
## ZOOM-01 adds the camera keys (arrows/+-/0/F) here rather than in a second handler: ONE place
## decides who owns a key, so a key can never mean two things at once. The camera is consulted
## FIRST and only for the keys it claims; an unknown key falls through to the console keys.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	# PART 4: the settings screen is capturing a key for a rebinding - it owns the keyboard until it
	# has one. Without this, pressing "B" to bind would ALSO buy a property behind the overlay.
	if _key_capture:
		return
	# PART 3: the keyboard model owns Tab/arrows/Enter/Space. It is consulted before everything else
	# so a focused button's own Enter handling cannot race the navigator.
	if KeyboardNav.owns(ke.keycode):
		if _handle_nav_key(ke.keycode):
			get_viewport().set_input_as_handled()
			return
	# EVERY OTHER KEY IS ONE TABLE LOOKUP (bindings.gd). Before this the keys were hard-coded here AND
	# in `keyboard-nav.hotkeys` AND asserted in the HG-13 gate - three homes, so a settings screen over
	# any one of them would have shown a key that did nothing. Now the screen, the hint and this
	# handler all read the same table, and a rebind takes effect on the next keystroke.
	var act := Bindings.action_for(_bindings, ke.keycode)
	if act == "":
		return
	if _dispatch_bound(act):
		get_viewport().set_input_as_handled()


## Run one bound action. Returns true when it consumed the key.
##
## A GAME action is only accepted when a human is actually deciding here - the same guard the B/N
## badges always had, so a rebind cannot let an observer mutate the match (HG-12).
func _dispatch_bound(act: String) -> bool:
	match act:
		Bindings.ACT_BUY:
			if not _human_can_act():
				return false
			_console.call("press_action", "buy")
		Bindings.ACT_END_TURN:
			if not _human_can_act():
				return false
			_console.call("press_action", "end_turn")
		Bindings.ACT_ROLL:
			if not _human_can_act():
				return false
			_console.call("press_action", "roll")
		Bindings.ACT_TRADE:
			if not _human_can_act():
				return false
			_console.call("press_action", "propose_trade")
		Bindings.ACT_BUILD:
			if _inspector != null:
				_inspector.call("press_action", "build_house")
			return true
		Bindings.ACT_MORTGAGE:
			if _inspector != null:
				_inspector.call("press_action", "mortgage_property")
			return true
		Bindings.ACT_PANELS:
			toggle_panels()
		Bindings.ACT_SETTINGS:
			settings_requested.emit()
		Bindings.ACT_FOLLOW:
			if _camera != null:
				_camera.call("handle_key", Bindings.KEY_FOR_FOLLOW)
		Bindings.ACT_CAM_LEFT, Bindings.ACT_CAM_RIGHT, Bindings.ACT_CAM_UP, Bindings.ACT_CAM_DOWN:
			if _camera == null:
				return false
			_camera.call("pan_by", _camera_delta(act))
		Bindings.ACT_ZOOM_IN:
			if _camera != null:
				_camera.call("zoom_at", 1.12, (_camera as Control).size * 0.5)
		Bindings.ACT_ZOOM_OUT:
			if _camera != null:
				_camera.call("zoom_at", 1.0 / 1.12, (_camera as Control).size * 0.5)
		_:
			return false
	return true


## The stage-space direction a bound camera key moves the board in.
func _camera_delta(act: String) -> Vector2:
	var step := 48.0
	match act:
		Bindings.ACT_CAM_LEFT:
			return Vector2(step, 0)
		Bindings.ACT_CAM_RIGHT:
			return Vector2(-step, 0)
		Bindings.ACT_CAM_UP:
			return Vector2(0, step)
		Bindings.ACT_CAM_DOWN:
			return Vector2(0, -step)
	return Vector2.ZERO


## May a game action be taken right now: a human is seated here, is not an observer, and it is their
## turn (the console's own `_human_now`). The ONE guard every game hotkey shares.
func _human_can_act() -> bool:
	if _observer or _console == null:
		return false
	return bool(_console.get("_human_now"))


## --- PART 4: the bindings API the settings screen calls ------------------------------------------

## The resolved table, for the screen to render.
func bindings() -> Dictionary:
	return _bindings


## Rebind one action and persist. The screen calls this; the shell applies it on the next keystroke
## (the handler looks the table up live, so there is nothing to re-register).
func set_binding(act: String, keycode: int) -> void:
	_bindings = Bindings.rebind(_bindings, act, keycode)
	Bindings.save_saved(_bindings)


## Return one action to its shipped key.
func reset_binding(act: String) -> void:
	_bindings = Bindings.reset_one(_bindings, act)
	Bindings.save_saved(_bindings)


## Return every action to its shipped key.
func reset_all_bindings() -> void:
	_bindings = Bindings.defaults()
	Bindings.save_saved(_bindings)


## The keyboard hint, built from the LIVE table so a rebind is reflected wherever it is shown.
func bindings_hint() -> String:
	return KeyboardNav.hotkey_hint(_bindings)



func _on_locale_changed(_loc: String) -> void:
	I18n.relabel(self)
	if _top != null and _top.has_method("retranslate"):
		_top.retranslate()
	if _seats_panel != null and _seats_panel.has_method("retranslate"):
		_seats_panel.retranslate()
	if _console != null and _console.has_method("retranslate"):
		_console.retranslate()
	if _inspector != null and _inspector.has_method("retranslate"):
		_inspector.retranslate()
	if _journal != null and _journal.has_method("retranslate"):
		_journal.retranslate()
	if _rail_r_journal != null:
		(_rail_r_journal as RailPanel).set_title(I18n.t("jrn.title"))
	if _rail_r_inspector != null:
		(_rail_r_inspector as RailPanel).set_title(I18n.t("ins.title"))


## The compact shell: ONE 48px rail on the right (journal + inspector) replaces both docks; a rail
## click opens the matching 320px drawer (DrawerPanel) over the stage. The seats rail is GONE
## (brief §4.2, R-15): its glance layer moved into the panno's players zone, and that zone is the
## door to `drawer-seats` now, so nothing became unreachable.
func _build_compact_shell(body: Control) -> void:
	_rail_right = UiTheme.panel()
	_rail_right.name = "rail-right"
	_rail_right.custom_minimum_size.x = 48.0
	var rail_col := UiTheme.vbox(4)
	_rail_right.add_child(rail_col)
	_rail_r_journal = RailPanel.new()
	(_rail_r_journal as RailPanel).name = "rail-right-journal"
	(_rail_r_journal as RailPanel).setup(UiTheme.skin(), "jrn.title", false)
	(_rail_r_journal as RailPanel).set_title(I18n.t("jrn.title"))
	(_rail_r_journal as RailPanel).set_collapsed(true, false)
	_rail_r_journal.toggled.connect(
		func(_c: bool) -> void: _toggle_drawer("journal", _rail_r_journal))
	# THE RAIL PANELS FILL THE SIDE (owner: «боковые кнопки… не на всю ширину заполняют сторону»).
	# Each one takes half of the rail's height, so the clickable area is the whole side of the screen
	# instead of two chips at the top with 1000px of dead rail under them.
	(_rail_r_journal as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_col.add_child(_rail_r_journal)
	_rail_r_inspector = RailPanel.new()
	(_rail_r_inspector as RailPanel).name = "rail-right-inspector"
	(_rail_r_inspector as RailPanel).setup(UiTheme.skin(), "ins.title", false)
	(_rail_r_inspector as RailPanel).set_title(I18n.t("ins.title"))
	(_rail_r_inspector as RailPanel).set_collapsed(true, false)
	_rail_r_inspector.toggled.connect(
		func(_c: bool) -> void: _toggle_drawer("inspector", _rail_r_inspector))
	(_rail_r_inspector as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_col.add_child(_rail_r_inspector)
	body.add_child(_rail_right)

	_rail_right.visible = false

	for spec in [["seats", "ui.players"], ["journal", "jrn.title"], ["inspector", "ins.title"]]:
		var d := DrawerPanel.new()
		d.name = "drawer-%s" % str(spec[0])
		d.set_title_key(str(spec[1]))
		d.visible = false
		d.closed.connect(func() -> void: _close_drawer(str(spec[0])))
		add_child(d)
		_drawers[str(spec[0])] = d


func _toggle_drawer(which: String, rail: Control) -> void:
	var d = _drawers.get(which)
	if d == null:
		return
	if (d as Control).visible:
		_close_drawer(which)
	else:
		_open_drawer(which)
	# the rail snaps back to its 48px strip; the drawer carries the content
	if rail is RailPanel:
		(rail as RailPanel).set_collapsed(true, false)


func _open_drawer(which: String) -> void:
	_close_all_drawers()
	var d = _drawers.get(which)
	if d == null:
		return
	match which:
		"seats":
			(d as DrawerPanel).put(_seats_panel)
		"journal":
			(d as DrawerPanel).put(_journal)
		"inspector":
			(d as DrawerPanel).put(_inspector)
	_layout_drawers()
	(d as Control).visible = true


## Return the content to its dock and hide the drawer. The dock's visibility follows the
## profile (hidden in compact), so returning a panel here must not flash it on screen.
func _close_drawer(which: String) -> void:
	var d = _drawers.get(which)
	if d == null or not (d as Control).visible:
		return
	var c := (d as DrawerPanel).take()
	if c != null:
		match which:
			"seats":
				_body_row.add_child(c)
				_body_row.move_child(c, 0)
				(c as Control).visible = not _is_compact()
			"journal":
				_rightcol.add_child(c)
				_rightcol.move_child(c, 1)
			"inspector":
				_rightcol.add_child(c)
				_rightcol.move_child(c, 2)
	(d as Control).visible = false


func _close_all_drawers() -> void:
	for which in _drawers.keys():
		_close_drawer(str(which))


## The drawers float over the stage: the seats drawer beside rail-left, the journal/inspector
## drawers beside rail-right.
func _layout_drawers() -> void:
	var w := 320.0
	var h := maxf(180.0, size.y - 96.0 - 120.0)
	for which in _drawers.keys():
		var d: Control = _drawers[which]
		d.custom_minimum_size = Vector2(w, h)
		d.size = Vector2(w, h)
		if str(which) == "seats":
			d.position = Vector2(8.0 + 48.0 + 8.0, 72.0)
		else:
			d.position = Vector2(maxf(0.0, size.x - 8.0 - 48.0 - 8.0 - w), 72.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_profile()


## Cold start: an empty board with the watermark and a console that says the match has
## not begun and offers START.
func setup_cold(launcher) -> void:
	_cold = true
	if _console != null and _console.has_method("set_cold"):
		_console.set_cold(true)
	if _board != null and _board.has_method("set_cold"):
		_board.set_cold()
	if _top != null and _top.has_method("set_cold"):
		_top.set_cold()
	_apply_profile()


func setup(eng, mgr, seat_list: Array, s) -> void:
	_engine = eng
	_mgr = mgr
	seats = seat_list
	_cold = false
	# a new match starts with an empty feed: the journal keeps raw events for its filters and
	# re-formats them on locale change (SG-06/SG-08), so it must not carry the last match's
	if _journal != null:
		_journal.clear_rows()
		if _journal.has_method("set_seats"):
			_journal.set_seats(seats)
	# the panno's journal zone starts empty with the match, like the feed it mirrors
	_board_tail.clear()
	if _board != null:
		_board.set_last_line({})
		_board.set_journal_tail([])
	# WHO PLAYS HERE: the seat driven by a human (LOCAL/ADMIN), whoever that is. The old
	# `_human_pid = 0` was right only by convention, and only on the host: any other ordering
	# (or a client) got a screen whose buttons could never appear or played the wrong seat.
	_human_pid = -1
	for s2 in seats:
		if str(s2.input_driver) == "LOCAL" or str(s2.input_driver) == "ADMIN":
			_human_pid = int(s2.pid)
			break
	if _mgr != null and _mgr.has_signal("events_emitted"):
		if not _mgr.events_emitted.is_connected(Callable(self, "_on_events")):
			_mgr.events_emitted.connect(Callable(self, "_on_events"))
	# the manager pushes a fresh spectator projection on every state change; the shell
	# follows it (this is the wire the local match paints from)
	if _mgr != null and _mgr.has_signal("state_changed"):
		if not _mgr.state_changed.is_connected(Callable(self, "apply_projection")):
			_mgr.state_changed.connect(Callable(self, "apply_projection"))
	if _console != null:
		_console.set_cold(false)
		_console.set_observer(_observer)
	if _board != null:
		_board.set_watermark(false)
	_sync_all()


func on_game_started() -> void:
	_cold = false
	if _board != null:
		_board.set_watermark(false)
	if _console != null:
		_console.set_cold(false)
	_sync_all()


func on_overlay_closed() -> void:
	pass


## A client learned which seat it owns (the host answered JOINED). Buttons may now appear
## on this client's own turn.
func set_human_pid(pid: int) -> void:
	_human_pid = pid
	# AUTODETECT (HG-12): no LOCAL/ADMIN seat on this screen means nobody here can play -
	# the stream window, a spectator host. Input dies with the same switch either way.
	if pid < 0:
		set_observer(true)
	_sync_all()


## This screen is a REMOTE client: intents go over the wire (the host validates). Set on JOINED.
func set_remote_session(sess) -> void:
	_remote = sess


## The host refused an intent from this client. Say why in the player's language.
func show_rejection(reason: String) -> void:
	if _modals != null:
		_modals.show_message(I18n.t("gv.rejected_title"), I18n.t("gv.rejected_body", [reason]))


## Main pushes the spectator projection (local engine or the wire).
func apply_projection(proj: Dictionary) -> void:
	_proj = proj
	if _cold:
		_cold = false
		if _console != null:
			_console.set_cold(false)
		if _board != null:
			_board.set_watermark(false)
	_sync_all()


func _sync_all() -> void:
	if _proj.is_empty():
		return
	_sync_modals()
	if _top != null:
		_top.sync(_proj, seats)
	if _seats_panel != null:
		_seats_panel.sync(_proj, seats)
	var holder := -1
	var legal: Array = []
	if _engine != null:
		holder = SeatManager.find_decision_holder(_engine, _engine.player_count())
		if holder >= 0:
			legal = _engine.legal_actions(holder)
	else:
		holder = int(_proj.get("holder", -1))
		legal = _proj.get("legal", [])
	if _board != null:
		_board.sync(_proj, seats, _human_pid)
	_sync_camera()
	if _console != null:
		_console.sync(holder, legal, holder == _human_pid and not _observer, _proj, seats)
	if _inspector != null:
		_inspector.sync(_proj, seats, legal, _human_pid)


## ZOOM-01: the camera follows the turn (the owner asked for the board to zoom on a move) and HOLDS
## while an auction runs - a viewer watching a bid must not be dragged away from the lot.
##
## One place decides, from the projection alone, so the shell does not scatter camera policy across
## the panels. A viewer who took the camera themselves (`_camera.following() < 0`) is not overridden
## by the next turn: only a NEW turn re-follows, and a pan stops follow until the turn changes again.
func _sync_camera() -> void:
	if _camera == null:
		return
	var phase := str(_proj.get("phase", ""))
	_camera.set_hold(phase == "AUCTION")
	var turn := int(_proj.get("turn_player", _proj.get("turn", -1)))
	_camera.turn_pid = turn
	if turn >= 0 and turn != _camera_turn:
		_camera_turn = turn
		# a new turn: take the camera back to the moving token, unless an auction holds it
		if phase != "AUCTION":
			_camera.follow(turn)


## The board-space point of a seat's token, for the camera to centre on. Returns null when the seat
## is unknown, so the camera can say "no target" instead of jumping to (0,0).
func _token_board_pos(pid: int) -> Variant:
	if _board == null or not _board.has_method("token_board_pos"):
		return null
	return _board.token_board_pos(pid)


## PART 3: the keyboard navigator. Returns true when it CONSUMED the key.
##
## ARROWS ARE SHARED WITH THE CAMERA, so the precedence is written down instead of left to whoever
## asks first: an arrow moves the FOCUS when there is a control to move to (the player is working the
## buttons), and pans the BOARD when there is not (the player is looking at the ring). A key that
## does nothing must not swallow the event, or the camera would never see an arrow.
func _handle_nav_key(keycode: int) -> bool:
	if _observer:
		return false                    # the stream has no input; the camera gets the arrows
	var controls := _focusable_controls()
	if controls.is_empty():
		return false
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER or keycode == KEY_SPACE:
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			(f as Button).emit_signal("pressed")
			return true
		return false
	var rects: Array = []
	var cur := -1
	var owner := get_viewport().gui_get_focus_owner()
	for i in controls.size():
		rects.append((controls[i] as Control).get_global_rect())
		if controls[i] == owner:
			cur = i
	var nxt: int = KeyboardNav.next_index(keycode, cur, rects)
	if nxt < 0 or nxt >= controls.size():
		return false
	(controls[nxt] as Control).grab_focus()
	return true


## The controls the keyboard can reach: every visible, enabled Button in the interactive panels, in
## a stable reading order. The panels rebuild their buttons each turn, so this is read fresh.
func _focusable_controls() -> Array:
	var out: Array = []
	for panel in [_console, _inspector, _top, _modals]:
		if panel == null or not (panel as Control).is_visible_in_tree():
			continue
		_collect_buttons(panel, out)
	return out


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			var b := c as Button
			if b.visible and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
				out.append(b)
		_collect_buttons(c, out)


func _on_tile_clicked(idx: int) -> void:
	if _inspector != null:
		_inspector.select(idx)
	if _board != null and _board.has_method("set_selected"):
		_board.set_selected(idx)


## Every console/board action funnels here. ACTIONS THAT NEED PARAMETERS OPEN A DIALOG —
## the audit's defect was exactly this: `action_requested(act, {})` sent an empty dict for
## all of them, and the engine refused six of thirteen buttons on every turn.
func _on_action(action: String, params: Dictionary) -> void:
	match action:
		"bid":
			_modals.show_auction(_proj, seats, _human_pid)
			return
		"propose_trade":
			_modals.show_trade_composer(_proj, seats, _human_pid)
			return
		"respond_trade":
			var pend: Dictionary = _proj.get("pending", {})
			if str(pend.get("type", "")) != "trade":
				return   # nothing to respond to (the button should not have been drawn)
			_modals.show_trade_response(_proj, seats)
			return
		"build_house", "sell_house", "mortgage_property", "unmortgage_property":
			# tile-addressed actions: the inspector's selection is the address. With no tile
			# picked, say how to pick one instead of sending `{}` to be refused "tile required".
			var tile := int(_inspector.selected) if _inspector != null else -1
			var mine := false
			for t in (_proj.get("board", []) as Array):
				if int(t.get("index", -1)) == tile and int(t.get("owner", -1)) == _human_pid:
					mine = true
					break
			if tile < 0 or not mine:
				_modals.show_message(I18n.t("gv.select_tile"), I18n.t("gv.select_tile_body"))
				return
			_submit(_human_pid, action, {"tile": tile})
			return
	_submit(_human_pid, action, params)


func _on_trade_submitted(to: int, give_tiles: Array, give_cash: int, want_tiles: Array, want_cash: int) -> void:
	_submit(_human_pid, "propose_trade", {
		"to": to, "give_tiles": give_tiles, "give_cash": give_cash,
		"want_tiles": want_tiles, "want_cash": want_cash,
	})


func _on_trade_answered(accept: bool) -> void:
	_submit(_human_pid, "respond_trade", {"accept": accept})


func _on_auction_bid(amount: int) -> void:
	_submit(_human_pid, "bid", {"amount": amount})


func _on_auction_pass() -> void:
	_submit(_human_pid, "pass", {})


func _on_inspector_action(tile: int, op: String) -> void:
	_submit(_human_pid, op, {"tile": tile})


func _submit(pid: int, action: String, params: Dictionary) -> void:
	# AN OBSERVER SENDS NOTHING, EVER (HG-12): the launch role (`--stream`) and the autodetect
	# (no LOCAL/ADMIN seat) both land here - before the wire path, before the manager path.
	if _observer:
		return
	# A CLIENT SUBMITS OVER THE WIRE. It has no manager and no engine: `_mgr.push_intent` was
	# the only path, so in the joined browser every press died here — the audit's "консольные
	# кнопки" defect, one layer down. The host still validates everything; the verdict comes
	# back on the same socket (main -> show_rejection on refusal).
	if _remote != null and _remote.has_method("is_joined") and _remote.is_joined():
		_remote.act(action, params)
		return
	if _mgr == null:
		return
	if pid < 0:
		# nobody local plays on this screen (observer/no LOCAL seat): nothing may be sent
		return
	var res: Dictionary = _mgr.push_intent(pid, action, params)
	if not res.get("ok", false):
		show_rejection(str(res.get("reason", "?")))


## The panno's journal zone (brief §4.1): the shell owns the sentence, board_scene only displays
## it, so the feed, the toast and the ring cannot disagree about what happened.
func _note_board_line(line: Dictionary) -> void:
	if _board == null:
		return
	_board.set_last_line(line)
	var who_line := str(line.get("who", ""))
	var text_line := str(line.get("text", ""))
	_board_tail.append(text_line if who_line == "" else "%s · %s" % [who_line, text_line])
	while _board_tail.size() > 3:
		_board_tail.pop_front()
	_board.set_journal_tail(_board_tail)


## Engine/manager events -> toasts, journal rows and board animations.
func _on_events(events: Array) -> void:
	for ev in events:
		var e: Dictionary = ev
		var kind: String = str(e.get("type", ""))
		if _toasts != null:
			# E-1/D9: the toast gets the same context the journal line gets (tile names, seats), so a
			# trade notification can name the properties instead of showing a bare proposer name.
			_toasts.show_event_toast(e, _journal_ctx())
		var data: Dictionary = e.get("data", {})
		# E-1/E-2: ONE line per event, computed once. The journal, the toast and the board banner
		# all read this same `line`, so the three surfaces cannot disagree about what happened.
		var line: Dictionary = {}
		if _journal != null:
			# SG-06: the line comes from the ADAPTER + the projection's tile names - never from
			# the raw engine type ("free_parking") and never as "клетка N".
			var ctx := _journal_ctx()
			line = _journal_lines.line_for(e, ctx)
			if not line.is_empty():
				_journal.append(e, ctx)
				# brief §4.1 / R-4: the SAME sentence also goes into the panno's journal zone, so
				# the board itself says what just happened — a viewer following the ring no longer
				# has to open the side panel to find out.
				_note_board_line(line)
				if _console != null and _is_compact():
					# compact: the journal lives behind rail-right; the newest event shows as the
					# console's one-line ticker (the registry's own wording for the compact toast)
					var who_line := str(line.get("who", ""))
					var text_line := str(line.get("text", ""))
					_console.show_ticker(text_line if who_line == "" else "%s · %s" % [who_line, text_line],
						str(line.get("cat", "info")))
		if _board != null:
			# board animations: rolls tumble the tray, moves hop the tokens
			if kind == "roll":
				_board.play_event({"k": "roll", "a": int(data.get("d1", 1)), "b": int(data.get("d2", 1))})
			elif kind in ["move", "teleport"]:
				var pid := _pid_of(str(data.get("player", "")))
				_board.play_event({"k": "move", "p": pid, "ti": int(data.get("to", data.get("tile", -1)))})
			# E-2/D10: the EVENTS that matter to a viewer go onto the BOARD as well as the feed.
			# The list is the plan's: purchase, auction start/win, build, bankruptcy, jail, winner,
			# tax, go bonus, trade. The text is the journal line's own text, so the banner and the
			# feed say the same sentence; the cell comes from the event's tile so the eye lands on
			# the place it happened.
			if kind in BOARD_EVENT_TYPES and not line.is_empty():
				_board.show_event(str(line.get("text", "")), _event_color(kind),
					int(line.get("_tile", _event_tile(e))))

			

func _pid_of(name: String) -> int:
	for s in seats:
		if str(s.name) == name:
			return int(s.pid)
	return -1


## E-2: the colour of a board event. It mirrors the toast's own colour rule (toast.gd), because a
## viewer reading the board and a player reading the dock are looking at the same news and should
## not have to learn two colour codes.
func _event_color(kind: String) -> Color:
	match kind:
		"buy", "aucwin":
			return UiTheme.COL().success
		"tax", "rent":
			return UiTheme.COL().money
		"bank", "jail":
			return UiTheme.COL().danger
		"build", "sell":
			return UiTheme.COL().accent
	return UiTheme.COL().accent


## E-2: which cell the event happened on, so the board can pulse it. Engine event shapes are not
## uniform (buy carries `tile`, jail carries `player`, auction carries `tile`), so every spelling the
## adapter knows is tried and -1 means "no cell to point at" rather than "cell 0", which would point
## the viewer at GO on every unmatched event.
func _event_tile(e: Dictionary) -> int:
	var d: Dictionary = e.get("data", {})
	for key in ["tile", "ti", "to", "index"]:
		if d.has(key):
			return int(d[key])
	return -1


## SG-06 rendering context for one journal batch: seat names/colours and the projection's tile
## NAMES. Rebuilt per batch - seats and the board change while the match runs.
func _journal_ctx() -> Dictionary:
	var names := {}
	var colors := {}
	for s in seats:
		names[int(s.pid)] = str(s.name)
		colors[int(s.pid)] = s.color
	var tiles := {}
	for t in (_proj.get("board", []) as Array):
		tiles[int(t.get("index", -1))] = str(t.get("name", ""))
	return {"names": names, "colors": colors, "tiles": tiles, "dim": UiTheme.COL().text_dim}


## A modal that shows LIVE state must follow that state: a bid re-raised by the next player
## refreshes the auction sheet (keeping what was half-typed), and a dialog whose subject is
## gone (lot sold, trade resolved) closes itself instead of lying.
func _sync_modals() -> void:
	if _modals == null or not _modals.is_open():
		return
	var pend: Dictionary = _proj.get("pending", {})
	var ptype := str(pend.get("type", ""))
	if _modals.kind == "auction":
		if ptype != "auction":
			_modals.close()
		elif int(pend.get("high", -1)) != int(_modals.get("_a_high")):
			_modals.show_auction(_proj, seats, _human_pid)
	elif _modals.kind == "trade_response":
		if ptype != "trade":
			_modals.close()
	elif _modals.kind == "trade_composer":
		if ptype == "trade":
			_modals.close()   # a trade is already on the table: the composer is out of date


func show_game_over(winner_name: String) -> void:
	if _modals != null:
		# `modal.game_over` / `modal.winner` are the keys the v3 sheet declares for exactly this
		# message (they sat unused while the shell asked for `over.title`/`over.winner`, two keys
		# nobody had ever written - the game-over modal showed `{over.title}` to the player).
		_modals.show_message(I18n.t("modal.game_over"), I18n.t("modal.winner", [winner_name]))
	if _toasts != null:
		_toasts.show_event_toast({"type": "winner", "data": {"player": winner_name}})
