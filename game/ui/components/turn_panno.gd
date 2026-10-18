extends Control
## Turn panno — the 9×9 centre of the ring becomes a four-zone panel (brief §4.1):
##   Бросок 22 % · Событие 28 % · Игроки 30 % · Журнал 20 %   (top to bottom)
##
## WHY THIS FILE EXISTS. The centre used to be a 35px banner and a 59px dice tray inside a
## 857×800 hole: measured on the live frame, 84.7 % of the ring's interior drew nothing and the
## five facts a viewer needs (whose turn, phase, dice+sum, every player's cash, the last event)
## lived in side panels that collapse to empty strips. R-1/R-2 in
## docs/specs/ui-redesign-brief.md demand ≤25 % empty cells and ≥70 % of the interior in use.
##
## RULES THIS MODULE OBEYS (each one is a bug the brief measured):
##  * R-13 — ONE layout: a VBoxContainer with stretch ratios. Nothing inside is positioned by
##    absolute coordinates derived from the screen size; the panno is given one rect by the board
##    and lays itself out from there.
##  * R-14 — it is a CONSUMER: `sync()` takes the projection and a finished journal line. It never
##    reads the engine and never computes game state.
##  * R-3 — every zone carries at least two lines of content in the live state, so no zone is a
##    decorated empty box.
##  * R-8 — two text roles: values (`label`, never wrapped) and paragraphs (`label_wrap`).
##  * R-5 — no zone hides itself in the live state; the zone is either populated or the whole
##    panno is in the cold state.
##
## The dice are NOT built here: board_scene owns their art and animation and adds them to
## `roll_slot`, so the panno supplies layout while the existing dice behaviour stays untouched.

const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")

## R-15 (brief §4.2): the 48px seats rail is gone - the panno's players zone carries the glance
## layer, and this signal is the door to the full seat cards in `drawer-seats`.
signal seats_requested

## Zone order is the reading order from the brief and must not be shuffled: heights are ratios of
## the panno's height, so they scale with the board instead of being fixed pixels.
const ZONE_KEYS: Array = ["roll", "event", "players", "journal"]
const RATIOS: Array = [22.0, 28.0, 30.0, 20.0]
const PLAYER_ROWS := 4
const JOURNAL_ROWS := 3
## Font sizes are ratios of a board cell, so the panno reads the same at 1280 and at 1600.
const FS_CAPTION := 0.155
const FS_VALUE := 0.270
const FS_SUM := 0.520
const FS_EVENT := 0.250
const FS_JRN := 0.190
## The turn/phase line under the dice is a GLANCE value (R-7): at an 80px cell it must clear 20px,
## so it cannot be a caption-sized 0.19 ratio - it measured 15px and the panno test refused it.
const FS_META := 0.260

var _built := false
var _cell := 64.0
var _cold := false

var _root: VBoxContainer
var _zones: Array = []
var _caps: Array = []
var _font_nodes: Array = []      # [{node: Control, ratio: float}]

var roll_slot: HBoxContainer
var _turn: Label
var _event_who: Label
var _event_text: Label
var _event_money: Label
var _pl_rows: Array = []          # [{root, chip, name, money, owns}]
var _jrn_rows: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build()


## Public because a component that builds in `_ready()` is NOT built in a headless test.
func build() -> void:
	if _built:
		return
	_built = true
	# The panno NEVER asks for room: it lives inside the ring's interior, which the board sizes.
	# Without this a long journal line or a big font made the Control's MINIMUM size inflate the
	# whole window - SG-07 then captured 1920x1013 where the profile promises 1600x1200.
	custom_minimum_size = Vector2.ZERO
	clip_contents = true
	for c in get_children():
		c.queue_free()
	_root = VBoxContainer.new()
	_root.name = "panno-root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_theme_constant_override("separation", 4)
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for i in ZONE_KEYS.size():
		var zone := PanelContainer.new()
		zone.name = "zone-" + str(ZONE_KEYS[i])
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0, 6.0))
		zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
		zone.size_flags_stretch_ratio = float(RATIOS[i])
		_root.add_child(zone)
		_zones.append(zone)
		var col := UiTheme.vbox(2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.add_child(col)
		var cap := UiTheme.label(I18n.t("panno." + str(ZONE_KEYS[i])), _fs(FS_CAPTION), UiTheme.COL().text_dim)
		_font_nodes.append({"node": cap, "ratio": FS_CAPTION})
		col.add_child(cap)
		_caps.append(cap)
		_build_zone(i, col)

	# Labels that sit DIRECTLY in a zone column fill it: `UiTheme.label` is the VALUE factory (width
	# by content), which inside a column leaves a 1px wide label once clipping is on - measured as an
	# empty centre. A row INSIDE the column is different: SG-04/P-4 allows exactly ONE stretching
	# child per row, so money/ownership stay at their text width and only the seat name grows.
	for entry in _font_nodes:
		var node = entry["node"]
		if node is Label and (node as Label).get_parent() is VBoxContainer:
			(node as Label).custom_minimum_size = Vector2.ZERO
			(node as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(node as Label).clip_text = (node as Label).autowrap_mode == TextServer.AUTOWRAP_OFF

	apply_scale(_cell)


func _build_zone(i: int, col: VBoxContainer) -> void:
	match str(ZONE_KEYS[i]):
		"roll":
			roll_slot = UiTheme.hbox(10)
			roll_slot.alignment = BoxContainer.ALIGNMENT_CENTER
			roll_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(roll_slot)
			_turn = UiTheme.label("", _fs(FS_META), UiTheme.COL().text_dim)
			_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _turn, "ratio": FS_META})
			col.add_child(_turn)
		"event":
			_event_who = UiTheme.label("", _fs(FS_EVENT), UiTheme.COL().accent)
			_event_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_who, "ratio": FS_EVENT})
			col.add_child(_event_who)
			_event_text = UiTheme.label_wrap("", _fs(FS_EVENT), UiTheme.COL().text)
			_event_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_text, "ratio": FS_EVENT})
			col.add_child(_event_text)
			_event_money = UiTheme.label_money("", _fs(FS_VALUE))
			_event_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_money, "ratio": FS_VALUE})
			col.add_child(_event_money)
		"players":
			for r in PLAYER_ROWS:
				var row := UiTheme.hbox(8)
				row.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# The rows share the zone's height: with fixed-height rows the column ended 58px
				# short of its own bottom edge and READ-02 read that as 32 % dead space.
				row.size_flags_vertical = Control.SIZE_EXPAND_FILL
				var chip := ColorRect.new()
				chip.color = UiTheme.COL().border
				chip.custom_minimum_size = Vector2(10, 10)
				chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(chip)
				var nm := UiTheme.label("", _fs(FS_VALUE), UiTheme.COL().text)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_font_nodes.append({"node": nm, "ratio": FS_VALUE})
				row.add_child(nm)
				var money := UiTheme.label_money("", _fs(FS_VALUE))
				_font_nodes.append({"node": money, "ratio": FS_VALUE})
				row.add_child(money)
				var owns := UiTheme.label("", _fs(FS_META), UiTheme.COL().text_dim)
				_font_nodes.append({"node": owns, "ratio": FS_META})
				row.add_child(owns)
				col.add_child(row)
				_pl_rows.append({"root": row, "chip": chip, "name": nm, "money": money, "owns": owns})
			# The zone is the DOOR to the full seat cards: with the seats rail removed (R-15) the
			# drawer would otherwise be unreachable in compact. A click, not a new control.
			col.mouse_filter = Control.MOUSE_FILTER_STOP
			col.tooltip_text = I18n.t("ui.players")
			col.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
						and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					seats_requested.emit())
		"journal":
			for r in JOURNAL_ROWS:
				var line := UiTheme.label_wrap("", _fs(FS_JRN), UiTheme.COL().text_dim)
				_font_nodes.append({"node": line, "ratio": FS_JRN})
				col.add_child(line)
				_jrn_rows.append(line)


## Cell size comes from the board, so every font is a ratio of the ring's own geometry.
func apply_scale(cell: float) -> void:
	_cell = maxf(24.0, cell)
	for entry in _font_nodes:
		var node = entry["node"]
		if is_instance_valid(node):
			node.add_theme_font_size_override("font_size", _fs(float(entry["ratio"])))


func _fs(ratio: float) -> int:
	return maxi(10, int(round(_cell * ratio)))


func zone_ratios() -> Array:
	var out: Array = []
	for z in _zones:
		if is_instance_valid(z):
			out.append(float(z.size_flags_stretch_ratio))
	return out


func zone_names() -> Array:
	var out: Array = []
	for z in _zones:
		if is_instance_valid(z):
			out.append(str(z.name))
	return out


## The column of one zone, so the board can host its OWN widgets inside the panno's layout
## (the dice tray, the event banner, the decision card) instead of positioning them by hand.
func zone_box(key: String) -> VBoxContainer:
	if not _built:
		build()
	var idx: int = ZONE_KEYS.find(key)
	if idx < 0 or idx >= _zones.size():
		return null
	var zone = _zones[idx]
	if not is_instance_valid(zone) or zone.get_child_count() == 0:
		return null
	return zone.get_child(0) as VBoxContainer


## Cold state: the match has not started. Zones stay in place (no layout jump) and say so.
func set_cold(on: bool) -> void:
	_cold = on
	_turn.text = I18n.t("top.cold") if on else ""
	_event_who.text = ""
	_event_text.text = I18n.t("plr.cold") if on else ""
	_event_money.text = ""
	for r in _pl_rows:
		r["name"].text = ""
		r["money"].text = ""
		r["owns"].text = ""
	for line in _jrn_rows:
		line.text = ""


## Paint from the projection + one finished journal line (the shell computes the line ONCE and
## hands the same sentence to the toast, the journal and this panno).
## event_line: {who, text, tag, cat, money} or {} — journal_tail: strings, oldest first.
func sync(proj: Dictionary, seats: Array, human_pid: int, event_line: Dictionary, journal_tail: Array) -> void:
	if not _built:
		build()
	var players: Array = proj.get("players", [])
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var phase: String = str(proj.get("phase", ""))
	var turn_name := _seat_name(seats, players, turn)
	var phase_lbl: String = I18n.t("phase." + phase)
	if phase_lbl.begins_with("{phase."):
		phase_lbl = phase
	if _cold:
		_turn.text = I18n.t("top.cold")
	else:
		_turn.text = "%s · %s" % [turn_name, phase_lbl] if turn_name != "" else phase_lbl

	# EVENT zone: the decision that is waiting (if any) outranks the last event line.
	var pend: Dictionary = proj.get("pending", {})
	var ptype := str(pend.get("type", ""))
	var tile_name := _tile_name(proj, int(pend.get("tile", -1)))
	if ptype != "" and tile_name != "":
		_event_who.text = I18n.t("ph.2") if ptype == "purchase" else I18n.t("modal.auction_title")
		_event_text.text = tile_name
		_event_money.text = ("$%d" % int(pend.get("cost", 0))) if pend.has("cost") else ""
	elif not event_line.is_empty():
		_event_who.text = str(event_line.get("who", ""))
		_event_text.text = str(event_line.get("text", ""))
		var cat := str(event_line.get("cat", ""))
		_event_money.text = ""
		_event_money.add_theme_color_override("font_color",
			UiTheme.COL().money if cat in ["money", "buy"] else UiTheme.COL().text_dim)
	elif _cold:
		_event_who.text = ""
		_event_text.text = I18n.t("plr.cold")
		_event_money.text = ""

	# PLAYERS zone: cash of EVERY seat (R-4) plus what they own.
	for r in PLAYER_ROWS:
		var row: Dictionary = _pl_rows[r]
		# A row with no seat behind it is not "space", it is dead space: READ-02 measured the zone
		# at 32 % empty in a 2-seat match because the four rows were always drawn. Hide them and
		# let the column hand the height to the seats that exist.
		row["root"].visible = r < players.size()
		if r >= players.size():
			row["chip"].color = UiTheme.COL().border
			row["name"].text = ""
			row["money"].text = ""
			row["owns"].text = ""
			continue
		var p: Dictionary = players[r]
		var pid: int = int(p.get("index", r))
		row["chip"].color = _seat_color(seats, pid)
		var nm := str(p.get("name", ""))
		if nm == "":
			nm = _seat_name(seats, players, pid)
		var money := int(p.get("money", 0))
		row["name"].text = nm
		row["money"].text = "$%d" % money
		var tiles: Array = p.get("tiles", [])
		row["owns"].text = I18n.t("panno.owns", [tiles.size(), int(p.get("houses", 0))])
		var dim := bool(p.get("bankrupt", false))
		row["root"].modulate = Color(1, 1, 1, 0.45) if dim else Color(1, 1, 1, 1)
		if pid == human_pid:
			row["name"].add_theme_color_override("font_color", UiTheme.COL().accent2)
		else:
			row["name"].add_theme_color_override("font_color", UiTheme.COL().text)

	# JOURNAL zone: the last lines, oldest first (newest nearest the console).
	#
	# An empty tail means "the match has just started": the zone would then be a caption over 169 px
	# of nothing, which is exactly what R-3 forbids (PANEL-NOT-EMPTY measured 1 line there). Two
	# true sentences stand in until the first event arrives - they are the zone's own explanation,
	# not invented game state, so R-14 holds.
	var start_lines: Array = []
	if journal_tail.is_empty():
		start_lines = [I18n.t("panno.jrn_start"), I18n.t("panno.jrn_hint")]
	for i in JOURNAL_ROWS:
		var line: Label = _jrn_rows[i]
		if not start_lines.is_empty():
			line.text = str(start_lines[i]) if i < start_lines.size() else ""
			continue
		var idx: int = journal_tail.size() - JOURNAL_ROWS + i
		line.text = str(journal_tail[idx]) if idx >= 0 and idx < journal_tail.size() else ""


func _seat_name(seats: Array, players: Array, pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	for p in players:
		if int(p.get("index", -1)) == pid:
			return str(p.get("name", ""))
	return ""


func _seat_color(seats: Array, pid: int) -> Color:
	for s in seats:
		if int(s.pid) == pid:
			return s.color
	return UiTheme.COL().border


func _tile_name(proj: Dictionary, index: int) -> String:
	if index < 0:
		return ""
	for e in (proj.get("board", []) as Array):
		if int(e.get("index", -1)) == index:
			return str(e.get("name", ""))
	return ""
