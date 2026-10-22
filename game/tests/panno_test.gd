extends RefCounted
## P1.1 — the turn panno (docs/specs/ui-redesign-brief.md §4.1).
##
## The brief measured the ring's interior as 84.7 % empty with 94 px of content in 800, and asked
## for a four-zone panel: Бросок 22 % · Событие 28 % · Игроки 30 % · Журнал 20 %. These tests pin
## the three properties a later refactor could silently drop: the ZONES (order + ratios), the
## SOURCE of every value (the projection, never the engine), and the LAYOUT RULE (no absolute
## coordinates inside the panno - R-13).

const PannoScript := preload("res://ui/components/turn_panno.gd")
const UiTheme := preload("res://ui/theme.gd")
const ContractScript := preload("res://tests/ui_contract_test.gd")

const PANNO_PATH := "res://ui/components/turn_panno.gd"


static func test_list() -> Array[String]:
	return ["test_panno_four_zones_in_reading_order", "test_panno_fonts_follow_the_cell",
		"test_panno_sync_paints_players_and_event",
		"test_panno_players_zone_hosts_the_shell_cards", "test_panno_journal_zone_hosts_the_panel",
		"test_panno_reads_only_contract_keys",
		"test_panno_has_no_absolute_placement"]


static func _panno():
	var p = PannoScript.new()
	p.build()
	return p


## The four zones exist, in the brief's reading order, with the brief's height ratios.
static func test_panno_four_zones_in_reading_order() -> String:
	var p = _panno()
	var names: Array = p.zone_names()
	# FIVE zones since 21.10: the tile card (the inspector) joined the journal in the
	# lower belt's right side - concept A puts "what happened" and "what is this tile"
	# together, and the right column was 344px of the 1600 frame that was NOT the board.
	var want: Array = ["zone-roll", "zone-event", "zone-players", "zone-journal",
		"zone-inspector"]
	if names != want:
		return "the panno's zones are %s, the composition says %s" % [str(names), str(want)]
	var ratios: Array = p.zone_ratios()
	var want_r: Array = [22.0, 28.0, 30.0, 60.0, 40.0]
	if ratios.size() != want_r.size():
		return "expected 4 zone ratios, got %d" % ratios.size()
	for i in want_r.size():
		if absf(float(ratios[i]) - float(want_r[i])) > 0.01:
			return "zone %s has ratio %.1f, the composition says %.0f" % [
				want[i], float(ratios[i]), float(want_r[i])]
	# every zone must be able to take its share of the height
	for key in ["roll", "event", "players", "journal", "inspector"]:
		var box = p.zone_box(key)
		if box == null:
			return "zone_box('%s') returned null - the zone cannot host anything" % key
	p.free()
	return ""


## Fonts are ratios of the board cell, so the panno reads the same on a 1280 window and a 1600 one.
static func test_panno_fonts_follow_the_cell() -> String:
	var p = _panno()
	p.apply_scale(40.0)
	var small: int = _turn_font(p)
	p.apply_scale(80.0)
	var big: int = _turn_font(p)
	if small <= 0 or big <= 0:
		return "the roll zone has no font-carrying label to measure (got %d/%d)" % [small, big]
	if big <= small:
		return "font size did not follow the cell: %d at 40px, %d at 80px" % [small, big]
	if big < 20:
		return "the turn/phase line renders at %dpx on an 80px cell - a value a viewer must read" % big
	p.free()
	return ""


## The roll zone's column is [caption, dice row, turn/phase label] - read the label itself, not the
## first child (which is the caption, and would make this test measure the wrong widget).
static func _turn_font(p) -> int:
	var box: VBoxContainer = p.zone_box("roll")
	if box == null:
		return 0
	var best := 0
	for c in box.get_children():
		if c is Label:
			best = maxi(best, int((c as Label).get_theme_font_size("font_size")))
	return best


## One sync paints the last event - no engine access. (The journal is not painted here
## any more: it is the shell's panel, in the slot below.)
##
## THE SEATS ARE NOT PAINTED HERE ANY MORE (21.10). The players zone is a SLOT: the shell's
## PlayersPanel shows the four seat cards inside it (see the test below), so a panno that also
## painted name/cash rows would be a second, poorer copy of the same facts in the same band.
static func test_panno_sync_paints_players_and_event() -> String:
	var p = _panno()
	p.apply_scale(80.0)
	var proj := {
		"phase": "TURN_START",
		"turn_player": 1,
		"players": [
			{"index": 0, "name": "Хост", "money": 1215, "position": 6, "tiles": [3, 6], "houses": 1,
				"bankrupt": false},
			{"index": 1, "name": "Neuro", "money": 980, "position": 24, "tiles": [8, 9, 37],
				"houses": 2, "bankrupt": false},
		],
		"board": [{"index": 6, "name": "Cedar Ave", "cost": 100}],
		"pending": {},
	}
	var seats: Array = [
		{"pid": 0, "name": "Хост", "color": Color("#ff6fae")},
		{"pid": 1, "name": "Neuro", "color": Color("#5fe3ff")},
	]
	var line := {"who": "Mira", "text": "продаёт с клетки 27", "cat": "money"}
	p.sync(proj, seats, 0, line)
	# the players zone is [caption, slot] - the seats arrive through the slot, not as rows here
	var col_players: VBoxContainer = p.zone_box("players")
	if col_players == null or col_players.get_child_count() != 2:
		return "the players zone is not [caption, slot] - the seat cards have no home in the ring"
	# the TURN line names whose turn it is (the one seat fact the panno still owns)
	var turn_lbl := ""
	for c in p.zone_box("roll").get_children():
		if c is Label and str((c as Label).name) == "panno-turn":
			turn_lbl = (c as Label).text
	if not turn_lbl.contains("Neuro"):
		return "the roll zone's turn line is `%s`, expected the seat whose turn it is" % turn_lbl
	# THE JOURNAL ZONE IS A SLOT (22.10): the panno gives the journal a PLACE and the
	# shell puts its own panel in it - the same pattern as the seat cards and the tile
	# card. The panno does NOT paint journal lines any more: the panel owns the feed, and
	# a second copy of the same sentences in the same band is what the change removed.
	var jrn: VBoxContainer = p.zone_box("journal")
	if jrn.get_child_count() != 2:
		return "the journal zone has %d child(ren), it should be [caption, slot]" % jrn.get_child_count()
	if p.journal_slot_box() == null:
		return "the panno has no journal slot - the journal has no place in the ring"
	var ev: Control = p.zone_box("event")
	var ev_text := ""
	for c in ev.get_children():
		if c is Label and (c as Label).text != "":
			ev_text += (c as Label).text + " | "
	if not ev_text.contains("Mira") and not ev_text.contains("продаёт"):
		return "the event zone does not carry the last event line (got %s)" % ev_text
	p.free()
	return ""


## THE JOURNAL ZONE IS A SLOT, AND THE JOURNAL IS ONE (22.10).
##
## Until 22.10 the feed existed TWICE: the panno painted three lines of its own and the
## full panel - filters, counter, export, every row - sat in the 344px right dock. Two
## journals of the same events, one of them a poorer copy of the other.
##
## The panno now gives the journal a PLACE (a slot) and the shell puts its own panel
## in it, exactly as the seat cards and the tile card are placed. This test pins both
## halves: the slot exists, and the panel can actually be put there.
static func test_panno_journal_zone_hosts_the_panel() -> String:
	var p = _panno()
	var slot: VBoxContainer = p.journal_slot_box()
	if slot == null:
		return "the panno has no journal slot - the journal has no place in the ring"
	if slot.get_parent() == null:
		return "the journal slot is not in the panno's tree - it would be lost"
	# THE SLOT MUST BE ABLE TO HOLD THE PANEL: a slot that cannot take a widget is a
	# caption, and the journal would fall back to the dock - the very copy we removed.
	var marker := Label.new()
	marker.name = "probe-journal-panel"
	slot.add_child(marker)
	if slot.get_child_count() != 1 or slot.get_child(0) != marker:
		return "the journal slot did not accept the panel - the journal would stay in the dock"
	# AND NOTHING MAY PAINT JOURNAL LINES OF ITS OWN: that is the second copy. The ZONE
	# holds its caption and the slot - a Label beside them would be a journal of the
	# panno's own, next to the panel's. Both places are checked.
	for c in slot.get_children():
		if c is Label and c != marker:
			return "the journal slot still paints a Label of its own (%s) - there are two journals again" % str(c.name)
	for c in p.zone_box("journal").get_children():
		if c is Label and c.get_index() != 0:
			return "the journal zone paints a Label of its own (%s) beside the slot - there are two journals again" % str(c.name)
	p.free()
	return ""


## THE PLAYERS ZONE IS A SLOT (track 1, step 2: the seat cards move INTO the ring).
##
## Pins the contract the shell relies on: the zone exposes a container the shell can put its own
## PlayersPanel into, the zone itself stops painting the seats, and the container fills the belt.
## Negative shape this test refuses: a panno that paints its own four rows AND a host, or a
## `players_slot` that is a stray node outside zone-players.
static func test_panno_players_zone_hosts_the_shell_cards() -> String:
	var p = _panno()
	var slot: VBoxContainer = p.players_slot_box()
	if slot == null:
		return "the players zone exposes no slot - the shell's seat cards have nowhere to go"
	var col: VBoxContainer = p.zone_box("players")
	if col == null:
		return "zone-players has no column"
	if not col.is_ancestor_of(slot):
		return "the players slot is not inside zone-players - the cards would land outside the belt"
	if col.get_child_count() != 2:
		return ("the players zone column has %d child(ren); it must be exactly [caption, slot] " +
			"now that the shell paints the seats") % col.get_child_count()
	if slot.size_flags_vertical & Control.SIZE_EXPAND == 0:
		return "the players slot does not expand - the cards would hug a corner of the upper belt"
	# hosting works: the widget the shell hands over ends up IN the slot (and is not reparented away)
	var hosted := Control.new()
	hosted.name = "hosted-cards"
	slot.add_child(hosted)
	if hosted.get_parent() != slot:
		return "the players slot does not accept a hosted widget"
	if slot.get_child_count() != 1:
		return "the players slot holds %d widget(s) after hosting one" % slot.get_child_count()
	# and the slot is the UPPER belt's - the seats are the top belt of the two, per concept A
	var belt: Node = slot.get_parent()
	while belt != null and str(belt.name) != "panno-belt-top" and str(belt.name) != "panno-belt-bottom":
		belt = belt.get_parent()
	if belt == null or str(belt.name) != "panno-belt-top":
		return "the players slot is not in the UPPER belt - the seats must be the top band"
	p.free()
	return ""


## R-14: every projection key the panno reads is in the HG-10 contract.
static func test_panno_reads_only_contract_keys() -> String:
	var contract: Array = ContractScript.CONTRACT
	var src := FileAccess.get_file_as_string(PANNO_PATH)
	if src == "":
		return "cannot read %s - the check would pass while proving nothing" % PANNO_PATH
	var re := RegEx.new()
	re.compile("proj\\.get\\(\"([a-z_]+)\"")
	var seen := 0
	for m in re.search_all(src):
		seen += 1
		var key := m.get_string(1)
		if not contract.has(key):
			return "the panno reads `%s`, which is not in the projection contract" % key
	if seen < 2:
		return "the scan found %d projection read(s) in the panno - it cannot be proving anything" % seen
	return ""


## R-13: one layout. The panno may not place anything by absolute coordinates of its own.
static func test_panno_has_no_absolute_placement() -> String:
	var src := FileAccess.get_file_as_string(PANNO_PATH)
	if src == "":
		return "cannot read %s - the check would pass while proving nothing" % PANNO_PATH
	if src.contains(".position ="):
		return "the panno positions a child with `.position =` - layout belongs to the containers (R-13)"
	if src.contains(".size = Vector2("):
		return "the panno assigns a literal `.size = Vector2(...)` - that is the absolute layout R-13 forbids"
	return ""
