extends Control
## The match settings sheet (cold start / restart apply). v3 rebuild: the fields that
## actually exist in GameSettings — seats and names, seed, starting cash, round limit
## and the turn timer — plus START / APPLY in the footer. It builds the settings and
## the seat list and hands them to main; it never touches the engine itself.

signal started(settings, seats)
signal apply_requested(settings, seats)
## "Создать партию для друзей" (F-47): main turns the configured seats into REMOTE ones, opens
## the server and shows the invitation links. The screen itself only says the user asked.
signal host_invite_requested
signal closed

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const GameSettingsScript := preload("res://core/game_settings.gd")
const SeatConfigScript := preload("res://seats/seat_config.gd")

var _pre := true
var _count := 4
var _name_edits: Array = []
var _rows_box: VBoxContainer
var _seed_edit: LineEdit
var _cash_edit: LineEdit
var _round_edit: LineEdit
var _timer_edit: LineEdit
var _title: Label
var _primary: Button
var _host_btn: Button
var _count_lbl: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(UiTheme.COL().bg.r, UiTheme.COL().bg.g, UiTheme.COL().bg.b, 0.8)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var sheet := PanelContainer.new()
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -300
	sheet.offset_right = 300
	sheet.offset_top = -260
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	sheet.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	add_child(sheet)
	var m := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(edge, 16)
	sheet.add_child(m)
	var v := UiTheme.vbox(10)
	m.add_child(v)

	var head := UiTheme.hbox(8)
	_title = UiTheme.label(I18n.t("settings.title"), 16, UiTheme.COL().text)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiTheme.button("✕", "")
	x.custom_minimum_size = Vector2(26, 26)
	x.connect("pressed", func() -> void:
		visible = false
		closed.emit())
	head.add_child(x)
	v.add_child(head)

	# seats: count stepper + one name row per seat
	var seats_head := UiTheme.hbox(8)
	seats_head.add_child(UiTheme.label(I18n.t("settings.tab_players"), 12, UiTheme.COL().text_dim))
	var minus := UiTheme.button("−", "")
	minus.custom_minimum_size = Vector2(28, 26)
	minus.connect("pressed", func() -> void: _set_count(_count - 1))
	seats_head.add_child(minus)
	_count_lbl = UiTheme.label("4", 13, UiTheme.COL().text)
	seats_head.add_child(_count_lbl)
	var plus := UiTheme.button("+", "")
	plus.custom_minimum_size = Vector2(28, 26)
	plus.connect("pressed", func() -> void: _set_count(_count + 1))
	seats_head.add_child(plus)
	v.add_child(seats_head)
	_rows_box = UiTheme.vbox(4)
	v.add_child(_rows_box)

	# the numeric fields
	_seed_edit = _field(v, "settings.seed", "0")
	_cash_edit = _field(v, "settings.cash", "1500")
	_round_edit = _field(v, "settings.rounds", "0")
	_timer_edit = _field(v, "settings.timer", "30")

	# footer
	var foot := UiTheme.hbox(8)
	# F-47: hosting for friends. Pre-game only (a match in progress has its seats built).
	_host_btn = UiTheme.button(I18n.t("settings.host_btn"), I18n.t("settings.host_tip"))
	_host_btn.custom_minimum_size.y = 44
	_host_btn.connect("pressed", Callable(self, "_host_pressed"))
	foot.add_child(_host_btn)
	var foot_sp := Control.new()
	foot_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(foot_sp)
	_primary = UiTheme.button_accent(I18n.t("settings.start_btn"), I18n.t("settings.start_tip"))
	_primary.custom_minimum_size.y = 44
	_primary.connect("pressed", Callable(self, "_emit"))
	foot.add_child(_primary)
	v.add_child(foot)

	_refresh_rows()


func _field(box: VBoxContainer, key: String, default: String) -> LineEdit:
	var row := UiTheme.hbox(8)
	var k := UiTheme.label(I18n.t(key), 12, UiTheme.COL().text_dim)
	k.custom_minimum_size.x = 160
	row.add_child(k)
	var e := LineEdit.new()
	e.text = default
	e.custom_minimum_size.x = 120
	e.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	row.add_child(e)
	box.add_child(row)
	return e


func set_mode(pre_game: bool) -> void:
	_pre = pre_game
	if _primary != null:
		_primary.text = I18n.t("settings.start_btn") if pre_game else I18n.t("settings.apply_btn")
	if _host_btn != null:
		_host_btn.visible = pre_game


func open() -> void:
	visible = true
	_refresh_rows()


func _set_count(n: int) -> void:
	_count = clampi(n, 2, 8)
	_count_lbl.text = str(_count)
	_refresh_rows()


func _refresh_rows() -> void:
	if _rows_box == null:
		return
	var keep: Array = []
	for e in _name_edits:
		keep.append((e as LineEdit).text)
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_name_edits.clear()
	for i in _count:
		var row := UiTheme.hbox(8)
		var idx := UiTheme.label(str(i + 1), 11, UiTheme.COL().text_dim)
		idx.custom_minimum_size.x = 16
		row.add_child(idx)
		var e := LineEdit.new()
		e.text = str(keep[i]) if i < keep.size() else ("Host" if i == 0 else "AI %d" % i)
		e.custom_minimum_size.x = 140
		e.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
		row.add_child(e)
		var driver := UiTheme.label("LOCAL" if i == 0 else "AI", 10, UiTheme.COL().accent if i == 0 else UiTheme.COL().text_dim)
		row.add_child(driver)
		_rows_box.add_child(row)
		_name_edits.append(e)


func _int_of(e: LineEdit, fallback: int) -> int:
	var s := e.text.strip_edges()
	return int(s) if s.is_valid_int() else fallback


## The match settings as the user set them. Extracted so the HOST-INVITE flow can build a match
## from the same fields the START button reads (it used to be inline in `_emit`, so a second
## reader did not exist and the invite button could not collect anything).
func _collect_settings():
	var st = GameSettingsScript.new()
	st.seat_count = _count
	var assigns: Array = []
	for i in _count:
		assigns.append({
			"driver": "LOCAL" if i == 0 else "AI",
			"name": (_name_edits[i] as LineEdit).text.strip_edges(),
		})
	st.seat_assignments = assigns
	st.rng_seed = _int_of(_seed_edit, 0)
	st.starting_cash = _int_of(_cash_edit, 1500)
	st.round_limit = _int_of(_round_edit, 0)
	st.turn_timer = _int_of(_timer_edit, 30)
	return st


func _emit() -> void:
	var st = _collect_settings()
	var seats: Array = SeatConfigScript.from_settings(st)
	if _pre:
		started.emit(st, seats)
	else:
		apply_requested.emit(st, seats)


func _host_pressed() -> void:
	host_invite_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		visible = false
		closed.emit()
		accept_event()
