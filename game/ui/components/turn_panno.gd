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
## THE COMPOSITION (concept A, docs/specs/ui-redesign-v5-composition.md).
##
## The ring's interior is TWO BELTS, not a stack of four zones:
##   the upper belt  - the four seats, side by side
##   the lower belt  - three columns: roll | journal | event
##
## WHY, in one line: the hero action and the thing it acts on must be read together, and
## in a stack the eye meets four full-width bands before it gets to the journal.
const ZONE_KEYS: Array = ["roll", "event", "players", "journal", "inspector"]
## The two belts share the interior 30/70: the seats need a fixed band (four cards
## side by side, each with a name, a chip and a balance), the lower belt takes the rest.
const BELT_TOP_RATIO := 30.0
const BELT_BOTTOM_RATIO := 70.0
## The left column of the lower belt is FIXED width (SG-04/P-4 lets a flex row stretch
## exactly one child - the journal is the one that grows). 520px at a 1600 frame: the
## hero buttons and the event line need that much and no more.
const BELT_LEFT_WIDTH := 520
## The tile card's width in the lower belt - fixed, so the journal is the only
## stretching child of that row (P-4).
const INSPECTOR_WIDTH := 330.0
## Within the lower belt: the roll column (the hero) and the event column share the
## left, the journal the right. A stretch ratio only says how the REMAINING space is
## shared - measured, the stack never squeezed anything (the journal holds 3 lines and
## does not grow), so these ratios are about PROPORTION, not about survival.
const RATIOS: Array = [22.0, 28.0, 30.0, 60.0, 40.0]
## Font sizes are ratios of a board cell, so the panno reads the same at 1280 and at 1600.
const FS_CAPTION := 0.155
const FS_VALUE := 0.270
const FS_SUM := 0.520
const FS_EVENT := 0.270
## The turn/phase line under the dice is a GLANCE value (R-7): at an 80px cell it must clear 20px,
## so it cannot be a caption-sized 0.19 ratio - it measured 15px and the panno test refused it.
const FS_META := 0.270

var _built := false
var _cell := 64.0
var _cold := false

var _root: VBoxContainer
var _zones: Array = []
## The two belts: the upper one holds the seats, the lower one the roll | journal | event
## columns. They are named because the gates and the probes look them up.
var _belt_top: HBoxContainer
var _belt_bottom: HBoxContainer
var _belt_col_left: VBoxContainer
var _belt_col_right: HBoxContainer
var _caps: Array = []
var _font_nodes: Array = []      # [{node: Control, ratio: float}]

var roll_slot: HBoxContainer
## The slot the SEAT CARDS sit in - the upper belt. Same pattern as `inspector_slot`:
## the panno supplies the place, the shell supplies the widget. The shell's PlayersPanel
## owns the seat facts (position, the jail/bankrupt chips, the round/pot strip and the
## ownership bar); the zone below it is only the door to the same cards in `drawer-seats`.
var players_slot: VBoxContainer
## The slot the INSPECTOR sits in - the right column of the lower belt, beside the
## journal. The panno supplies the layout, the shell supplies the widget (the same
## pattern as `roll_slot` and the dice). The inspector is the shell's: it knows the
## selection and owns the action buttons.
var inspector_slot: VBoxContainer
var _turn: Label
var _event_who: Label
var _event_text: Label
var _event_money: Label
var journal_slot: VBoxContainer


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

	# TWO BELTS, not a stack of four (concept A, docs/specs/ui-redesign-v5-composition.md).
	# The upper belt is the four seats; the lower belt is three columns:
	# roll | journal | event. The order is the READING order, and the order is why:
	# "Бросок" is the hero action and it must be the FIRST thing the eye lands on, and
	# the event and the journal are two views of the same turn, so they belong together.
	# In the old stack the eye met roll, then event, then players, then journal - the
	# hero and the thing it acts on were separated by two zones.
	_belt_top = HBoxContainer.new()
	_belt_top.name = "panno-belt-top"
	_belt_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_belt_top.add_theme_constant_override("separation", 4)
	_belt_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_belt_top.size_flags_stretch_ratio = float(BELT_TOP_RATIO)
	_root.add_child(_belt_top)
	_belt_bottom = HBoxContainer.new()
	_belt_bottom.name = "panno-belt-bottom"
	_belt_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_belt_bottom.add_theme_constant_override("separation", 4)
	_belt_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_belt_bottom.size_flags_stretch_ratio = float(BELT_BOTTOM_RATIO)
	_root.add_child(_belt_bottom)
	# the lower belt's two columns: the narrow one (hero + event) and the wide one
	# (the journal). The split is 1fr / 1.4fr - the journal carries longer lines.
	_belt_col_left = VBoxContainer.new()
	_belt_col_left.name = "panno-col-left"
	_belt_col_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_belt_col_left.add_theme_constant_override("separation", 4)
	# SG-04/P-4: a flex row may stretch EXACTLY ONE child. Two stretching children
	# in an HBox is what makes a stretched Label collapse to its content width, and the
	# rule counts every stretching Control, not only Labels. So the RIGHT column (the
	# journal) grows - its content is long lines that must wrap - and the LEFT one (the
	# hero and the event) takes a FIXED width, because its content is short values and
	# buttons whose width is their own.
	_belt_col_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_belt_col_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_belt_col_left.custom_minimum_size.x = BELT_LEFT_WIDTH
	_belt_bottom.add_child(_belt_col_left)
	_belt_col_right = HBoxContainer.new()
	_belt_col_right.name = "panno-col-right"
	_belt_col_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_belt_col_right.add_theme_constant_override("separation", 4)
	_belt_col_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_belt_col_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_belt_bottom.add_child(_belt_col_right)
	# the right side of the lower belt is a PAIR of columns: the journal and the
	# tile card. They are two views of the same turn - what happened and what this
	# tile is - and concept A puts them side by side. The journal keeps the wider
	# share (its lines are long); the tile card needs enough width for its rows.

	for i in ZONE_KEYS.size():
		var zone := PanelContainer.new()
		zone.name = "zone-" + str(ZONE_KEYS[i])
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.add_theme_stylebox_override("panel",
			UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0, 6.0))
		zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
		zone.size_flags_stretch_ratio = float(RATIOS[i])
		# P-4: a flex row stretches EXACTLY ONE child. The lower belt's right side is
		# a row of two zones - the journal and the tile card - so only the JOURNAL
		# may grow. The card takes a fixed width: its rows are short, and a card that
		# stretched to 600px of empty space is the owner's own complaint.
		if str(ZONE_KEYS[i]) == "inspector":
			zone.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			zone.custom_minimum_size.x = INSPECTOR_WIDTH
		else:
			zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# WHERE a zone lives:
		#   players  - the whole upper belt
		#   roll     - the upper half of the lower belt's LEFT column
		#   event    - the lower half of the lower belt's LEFT column
		#   journal  - the lower belt's RIGHT column
		# So the lower belt has TWO columns: a narrow one with the hero and the event
		# stacked, and a wide one with the journal. The hero action is the first thing in
		# the left column, at the top-left of the reading order.
		if str(ZONE_KEYS[i]) == "players":
			_belt_top.add_child(zone)
		else:
			if str(ZONE_KEYS[i]) == "journal" or str(ZONE_KEYS[i]) == "inspector":
				# The journal and the tile card are SIBLINGS: two views of the same turn,
				# and concept A puts them side by side in the ring's lower belt. The
				# journal keeps the wider share - its lines are long.
				_belt_col_right.add_child(zone)
			else:
				_belt_col_left.add_child(zone)
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
			# NAMED FOR THE GATES: STREAM-READ must measure the labels a viewer actually SEES. The
			# dock's jrn-title/jrn-text are hidden in every profile under 2000px wide (compact mode),
			# so the gate used to judge an invisible node while the panno - the thing on screen -
			# carried no names at all.
			_turn.name = "panno-turn"
			_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _turn, "ratio": FS_META})
			col.add_child(_turn)
		"event":
			_event_who = UiTheme.label("", _fs(FS_EVENT), UiTheme.COL().accent)
			_event_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_who, "ratio": FS_EVENT})
			col.add_child(_event_who)
			_event_text = UiTheme.label_wrap("", _fs(FS_EVENT), UiTheme.COL().text)
			_event_text.name = "panno-event-text"
			_event_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_text, "ratio": FS_EVENT})
			col.add_child(_event_text)
			_event_money = UiTheme.label_money("", _fs(FS_VALUE))
			_event_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_font_nodes.append({"node": _event_money, "ratio": FS_VALUE})
			col.add_child(_event_money)
		"players":
			# THE SEAT CARDS. The panno gives the upper belt a PLACE; the shell puts its own
			# PlayersPanel in it (the same pattern as the tile card and the dice tray). The panel
			# owns the seat facts - position, the jail/bankrupt chips, the round/pot strip and the
			# ownership bar - so "who is playing, with how much and where" has ONE source.
			# Until 21.10 this zone painted four glance rows of its own (chip, name, cash, owned)
			# while the FULL cards lived in the 268px left dock, which the profile hides below
			# 2000px wide: the richer view of the same four facts was reachable only through a
			# drawer. Moving the panel in removes the second, poorer copy instead of adding a third.
			players_slot = UiTheme.vbox(4)
			players_slot.name = "players-slot"
			players_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			players_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
			players_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(players_slot)
			# The zone is the DOOR to the seat cards in `drawer-seats`: with the seats rail removed
			# (R-15) the drawer would otherwise be unreachable in compact. A click, not a new control.
			col.mouse_filter = Control.MOUSE_FILTER_STOP
			col.tooltip_text = I18n.t("ui.players")
			col.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
						and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					seats_requested.emit())
		"journal":
			# THE JOURNAL, AND IT IS ONE JOURNAL.
			#
			# Until 22.10 this zone painted three lines of its own while the FULL journal -
			# filters, counter, export, every row - lived in the 344px right dock: two journals
			# of the same feed, one of them a poorer copy. The panno gives the journal a PLACE;
			# the shell puts its own panel in it, exactly like the seat cards and the tile card.
			# The panel keeps its behaviour (it owns the events, the filters and the export).
			#
			# THE PANNO DOES NOT SCROLL (clip_contents = true, R-13), so the panel carries its OWN
			# scroll area - the rows scroll INSIDE the zone and the zone keeps its size.
			journal_slot = UiTheme.vbox(4)
			journal_slot.name = "journal-slot"
			journal_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
			journal_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(journal_slot)
		"inspector":
			# The tile card. The panno gives it a PLACE and a caption; the shell puts
			# the widget in (the same pattern as `roll_slot` and the dice). The inspector
			# stays the shell's - it knows the selection and owns the action buttons.
			inspector_slot = UiTheme.vbox(4)
			inspector_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(inspector_slot)


## Cell size comes from the board, so every font is a ratio of the ring's own geometry.
func apply_scale(cell: float) -> void:
	_cell = maxf(24.0, cell)
	for entry in _font_nodes:
		var node = entry["node"]
		if is_instance_valid(node):
			node.add_theme_font_size_override("font_size", _fs(float(entry["ratio"])))
	# THE JOURNAL PANEL IN THE SLOT SCALES WITH THE RING TOO. It is the shell's widget,
	# so it cannot read the cell itself - the panno hands it over, exactly as it hands
	# the cell to its own labels. A panel that kept its pixel sizes would be unreadable
	# on a phone, where the ring is small (STREAM-READ measures that).
	if journal_slot != null:
		for c in journal_slot.get_children():
			if c.has_method("set_ring_cell"):
				c.call("set_ring_cell", _cell)


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
## Where the INSPECTOR goes. The shell asks for the slot and reparents the tile card
## into it - the panno supplies the layout, the shell keeps the widget and its behaviour.
## The same pattern as `roll_slot` and the dice tray.
func inspector_slot_box() -> VBoxContainer:
	if not _built:
		build()
	return inspector_slot


## Where the JOURNAL goes. The shell asks for the slot and reparents its JournalPanel
## into it - the panno supplies the layout, the shell keeps the widget and its behaviour.
## The same pattern as `inspector_slot` and `players_slot`.
func journal_slot_box() -> VBoxContainer:
	if not _built:
		build()
	return journal_slot


## Where the SEAT CARDS go. The shell asks for the slot and reparents its PlayersPanel
## into it - the panno supplies the layout, the shell keeps the widget and its behaviour.
## The same pattern as `inspector_slot` and the dice tray.
func players_slot_box() -> VBoxContainer:
	if not _built:
		build()
	return players_slot


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
	# The journal is NOT cleared here: the panel in the slot owns the feed, and the shell
	# empties it with `clear_rows()` when a new match starts. A cold board and a cold
	# journal are two different facts.


## Paint from the projection + one finished journal line (the shell computes the line ONCE and
## hands the same sentence to the toast, the journal and this panno).
## event_line: {who, text, tag, cat, money} or {}.
##
## The `journal_tail` argument is GONE (22.10): it fed the three lines this panno used to
## paint, and the panel in the journal slot owns the feed now. A parameter nobody reads is
## a second source of truth waiting to drift.
func sync(proj: Dictionary, seats: Array, human_pid: int, event_line: Dictionary) -> void:
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

	# PLAYERS zone: painted by the SHELL's PlayersPanel, which this panno hosts in
	# `players_slot` (the seat cards: cash of every seat, position, chips, round/pot).
	# It used to paint four glance rows here - two views of the same facts in one band,
	# and the poorer one. R-14 holds either way: the panel reads the same projection.

	# JOURNAL zone: the shell's own panel, which lives in the slot above. The panno no
	# longer paints journal lines: the panel owns the feed, the filters and the export, and
	# a second copy of the same three sentences in the same band is the thing this whole
	# change set out to remove. The panno still reads the same projection as before (R-14) -
	# it just does not draw the feed itself.


func _seat_name(seats: Array, players: Array, pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	for p in players:
		if int(p.get("index", -1)) == pid:
			return str(p.get("name", ""))
	return ""


func _tile_name(proj: Dictionary, index: int) -> String:
	if index < 0:
		return ""
	for e in (proj.get("board", []) as Array):
		if int(e.get("index", -1)) == index:
			return str(e.get("name", ""))
	return ""
