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
		"test_panno_sync_paints_players_and_journal", "test_panno_reads_only_contract_keys",
		"test_panno_has_no_absolute_placement"]


static func _panno():
	var p = PannoScript.new()
	p.build()
	return p


## The four zones exist, in the brief's reading order, with the brief's height ratios.
static func test_panno_four_zones_in_reading_order() -> String:
	var p = _panno()
	var names: Array = p.zone_names()
	var want: Array = ["zone-roll", "zone-event", "zone-players", "zone-journal"]
	if names != want:
		return "the panno's zones are %s, the brief's reading order is %s" % [str(names), str(want)]
	var ratios: Array = p.zone_ratios()
	var want_r: Array = [22.0, 28.0, 30.0, 20.0]
	if ratios.size() != want_r.size():
		return "expected 4 zone ratios, got %d" % ratios.size()
	for i in want_r.size():
		if absf(float(ratios[i]) - float(want_r[i])) > 0.01:
			return "zone %s has ratio %.1f, the brief's §4.1 table says %.0f" % [
				want[i], float(ratios[i]), float(want_r[i])]
	# every zone must be able to take its share of the height
	for key in ["roll", "event", "players", "journal"]:
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


## One sync paints every seat's cash (R-4) and the last journal sentences - no engine access.
static func test_panno_sync_paints_players_and_journal() -> String:
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
	p.sync(proj, seats, 0, line, ["a", "b", "c"])
	# the zone column is [caption, row0..row3]: rows start at index 1
	var col_players: VBoxContainer = p.zone_box("players")
	var rows: Array = []
	for i in range(1, col_players.get_child_count()):
		rows.append(col_players.get_child(i))
	if rows.size() < 4:
		return "the players zone has %d rows, the centre must show EVERY seat (up to 4)" % rows.size()
	var row0: Control = rows[0]
	var texts: Array = []
	for c in row0.get_children():
		if c is Label:
			texts.append((c as Label).text)
	if not texts.has("$1215"):
		return "row 0 does not show the seat's cash; labels were %s" % str(texts)
	if not texts.has("Хост"):
		return "row 0 does not show the seat's name; labels were %s" % str(texts)
	var jrn: VBoxContainer = p.zone_box("journal")
	if jrn.get_child_count() < 4:
		return "the journal zone has %d label(s), the brief asks for 3" % (jrn.get_child_count() - 1)
	if (jrn.get_child(3) as Label).text != "c":
		return "the journal zone's last line is %s, expected the newest sentence 'c'" % (jrn.get_child(3) as Label).text
	var ev: Control = p.zone_box("event")
	var ev_text := ""
	for c in ev.get_children():
		if c is Label and (c as Label).text != "":
			ev_text += (c as Label).text + " | "
	if not ev_text.contains("Mira") and not ev_text.contains("продаёт"):
		return "the event zone does not carry the last event line (got %s)" % ev_text
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
