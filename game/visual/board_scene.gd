extends Control
## The board (`#stage` → `#board`): the 40-tile ring, the centre (watermark / dice tray /
## banner / decision card) and the player tokens. v3 rebuild from the prototype: flat,
## cell = side/11, band-facing-centre tiles, dice that tumble IN the centre.
##
## Reads the spectator projection; emits tile clicks. It never touches the engine.

signal tile_clicked(index: int)
## R-15: the panno's players zone is the door to `drawer-seats` once the seats rail is gone.
signal seats_requested

const TileView := preload("res://visual/tile_view.gd")
const UiTheme := preload("res://ui/theme.gd")
const I18n := preload("res://i18n/i18n.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const TurnPanno := preload("res://ui/components/turn_panno.gd")

var _skin: SkinManager
## See SkinManager.set_animations: the settings sheet's "Анимации" row used to be inert. The shell
## pushes the setting here (and into the camera); 0.0 keeps the state change and drops the tween.
var animations_enabled: bool = true


func set_animations(on: bool) -> void:
	animations_enabled = on


## Every duration this scene eases with goes through here.
func _dur(seconds: float) -> float:
	return seconds if animations_enabled else 0.0
var _board: Array = []
var _tiles: Array = []
var _cell := 0.0
var _band_px := 0.0
var _selected := -1
var _entries: Dictionary = {}       # index -> state dict handed to the tiles

var _wm1: Label
var _wm2: Label
var _tray: HBoxContainer
var _dice: Array = []
var _sum: Label
var _doubles: Label
var _banner: Label
## E-2/D10: the central banner becomes an EVENT surface, not just a turn label. It carries a queue
## of messages with auto-hide, because a purchase, a build, a jail or a bankruptcy left no trace on
## the BOARD at all - only a 3s toast in a side dock, which a viewer following the ring never sees.
var _ev_queue: Array = []          # [{text, color, tile}]
var _ev_shown: int = 0             # index into _ev_queue of the message on screen
var _ev_timer: float = 0.0         # seconds the current message has been up
const EV_HOLD := 3.0               # "автоскрытие (3с)" - master-fix-plan §2 E-2
var _flash: Dictionary = {}        # tile index -> seconds left (the state-frame pulse)
const FLASH_HOLD := 1.0
var _card: PanelContainer
var _card_name: Label
var _card_price: Label
var _tokens: Dictionary = {}        # pid -> Control
var _token_pos: Dictionary = {}     # pid -> int (tile index)

var _rolling := false
var _roll_t := 0.0
var _roll_swap := 0.0
var _roll_to := Vector2i(1, 1)
var _watermark := true
## brief §4.1: the ring's interior is a TURN PANNO, not a hole. It owns the layout of the four
## zones; the widgets built below (watermark, dice tray, event banner, decision card) are hosted
## INSIDE its zones, so nothing in the centre is positioned by absolute coordinates any more.
var _panno: Control
var _last_line: Dictionary = {}          # the shell's finished journal line (R-14: not computed here)
var _journal_tail: Array = []            # last N journal sentences, oldest first
const JRN_TAIL := 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_skin = SkinManager.new()
	_skin.load_skin()
	_load_board()
	resized.connect(_layout)
	_build_centre()
	# The panno is created in `_build_centre()`, so the FIRST layout pass has to run after it:
	# `resized` may already have fired while the board was entering the tree, and without this
	# call the panno stayed at 0x0 for the whole session (measured: the ring's interior still read
	# 7.3 % occupied because nothing was drawn there).
	_layout()


func _load_board() -> void:
	var f := FileAccess.open("res://data/board.json", FileAccess.READ)
	if f == null:
		push_error("board_scene: cannot read res://data/board.json")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_board = parsed.get("tiles", [])
	elif parsed is Array:
		_board = parsed


func _build_centre() -> void:
	_wm1 = UiTheme.label("NEURO\nPROPERTY TRADE", 18, UiTheme.COL().text_dim)
	_wm1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wm1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_wm1)
	_wm2 = UiTheme.label(I18n.t("top.cold"), 10, UiTheme.COL().text_dim)
	_wm2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wm2.modulate = Color(1, 1, 1, 0.6)
	add_child(_wm2)

	_tray = UiTheme.hbox(12)
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_tray)
	for i in 2:
		var d := Control.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.set_meta("value", 1)
		d.draw.connect(_draw_die.bind(d))
		_tray.add_child(d)
		_dice.append(d)
	_sum = UiTheme.label("", 24, UiTheme.COL().text)
	_sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sum.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.COL().panel_dark, UiTheme.COL().border, 1, 0))
	_sum.visible = false
	_tray.add_child(_sum)
	_doubles = UiTheme.label(I18n.t("die.doubles"), 11, UiTheme.COL().accent2)
	_doubles.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), UiTheme.COL().accent2, 1, 0))
	_doubles.visible = false
	_tray.add_child(_doubles)

	_banner = UiTheme.label("", 15, UiTheme.COL().text)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_card.visible = false
	add_child(_card)
	var cv := UiTheme.vbox(4)
	_card.add_child(cv)
	_card_name = UiTheme.label("", 16, UiTheme.COL().text)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_card_name)
	_card_price = UiTheme.label("", 14, UiTheme.COL().money)
	_card_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_card_price)

	# brief §4.1 (R-13/R-2): the ring's interior is a four-zone TURN PANNO. Built last, and the
	# widgets above are moved INTO its zones: the panno owns the layout, they keep their behaviour.
	# This is what turns the 857x800 hole (84.7 % empty, 94 px of content) into the turn surface.
	_panno = TurnPanno.new()
	_panno.name = "turn-panno"
	add_child(_panno)
	_panno.build()
	_panno.seats_requested.connect(func() -> void: seats_requested.emit())
	var roll_col: VBoxContainer = _panno.zone_box("roll")
	var ev_col: VBoxContainer = _panno.zone_box("event")
	if roll_col != null:
		_tray.reparent(roll_col, false)
	if ev_col != null:
		_banner.reparent(ev_col, false)
		_card.reparent(ev_col, false)
	# The watermark is the COLD state's decoration; the panno already says "партия не начата".
	# It stays a child of the board (never inside a column: an autowrapping label there demanded
	# 577px of minimum height and pushed every zone out of the ring).
	_wm1.visible = false
	_wm2.visible = false


## Ring coordinates for board index (classic order: GO bottom-right, anti-clockwise).
static func _grid_pos(i: int) -> Vector2i:
	if i == 0:
		return Vector2i(10, 10)
	if i < 10:
		return Vector2i(10 - i, 10)
	if i == 10:
		return Vector2i(0, 10)
	if i < 20:
		return Vector2i(0, 10 - (i - 10))
	if i == 20:
		return Vector2i(0, 0)
	if i < 30:
		return Vector2i(i - 20, 0)
	if i == 30:
		return Vector2i(10, 0)
	return Vector2i(10, i - 30)


static func _ring_side(i: int) -> String:
	if i <= 10:
		return "b"
	if i <= 20:
		return "l"
	if i <= 30:
		return "t"
	return "r"


func _is_corner(i: int) -> bool:
	return i in [0, 10, 20, 30]


## B1: four screens, one per corner. The line lives INSIDE the corner cell (not on an overlay):
## READ-01 wants every ring cell to keep an identifier, PANEL-NOT-EMPTY wants a big panel to carry
## text, and R-12 forbids dropping the name - so the cell shows its name (small) plus the glance line
## (big). Measured: an overlay left four 296x161 panels with 0 lines and four cells without names.
const GLANCE_IDX := [0, 10, 20, 30]
const GLANCE_F := 0.264            # of the band: 50px at a 190px band -> eff 12.19 on a 390 frame
var _glance_text: Dictionary = {}  # ring index -> the line last written (survives a ring rebuild)


func glance_font() -> int:
	return int(maxf(14.0, float(ring_metrics(size)["band"]) * GLANCE_F))


func _apply_glance() -> void:
	var fs := glance_font()
	for idx in GLANCE_IDX:
		if idx < _tiles.size() and _glance_text.has(idx):
			(_tiles[idx] as TileView).set_screen(str(_glance_text[idx]), fs)


func _set_glance(idx: int, text: String) -> void:
	_glance_text[idx] = text
	if idx < _tiles.size():
		(_tiles[idx] as TileView).set_screen(text, glance_font())


## The glance layer, straight from the projection (R-14: no game state is computed here).
func _sync_glance(proj: Dictionary, seats: Array, _human_pid: int) -> void:
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var turn_name := ""
	for s in seats:
		if int(s.pid) == turn:
			turn_name = str(s.name)
	if turn_name == "":
		for p in (proj.get("players", []) as Array):
			if int(p.get("index", -1)) == turn:
				turn_name = str(p.get("name", ""))
	var phase := str(proj.get("phase", ""))
	var pot := int(proj.get("parking_pot", 0))
	var rnd := int(proj.get("round", 1))
	var cold := _watermark or turn < 0
	_set_glance(0, I18n.t("top.cold") if cold else I18n.t("glance.turn", [turn_name]))
	_set_glance(10, I18n.t("top.cold") if cold else I18n.t("glance.phase",
		[I18n.t("phase." + phase) if phase != "" else "—"]))
	_set_glance(20, I18n.t("glance.bank", ["$%d" % pot]))
	_set_glance(30, I18n.t("glance.round", [str(rnd)]))


func _layout() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_place_board()
	_place_centre()


## B1 «кольцо во весь кадр»: the ring fills the FRAME instead of a centred square. Two numbers set
## the whole geometry, both taken from constraints rather than taste:
##   * band  - the ring's thickness. 0.158 of the frame's height puts it at 190px on 1600x1200, which
##             is what a 88px side cell needs to stay above R-17's 77px floor;
##   * corner - the four corners are WIDER than they are thick (320x190), because they carry the
##             glance layer: "БАНК ПАРКОВКИ $240" at 50px needs 557px on one line, 308px on two, and
##             a square 11x11 ring at a 77px cell gives a corner at most 253px. That is the arithmetic
##             from the accepted concept, not an aesthetic choice.
const MIN_CELL := 77.0
const CORNER_MIN_W := 300.0
const BAND_FRACTION := 0.158


static func ring_metrics(frame: Vector2) -> Dictionary:
	var w := maxf(frame.x, 1.0)
	var h := maxf(frame.y, 1.0)
	# R-17 is a FLOOR, not a target: a cell may never go below 77px. When the frame is too short for
	# a band plus nine legal cells, the RING grows past the frame and the camera windows it - that is
	# R-18 ("if R-7 and R-17 conflict, the frame grows, the board does not shrink"). Measured: at
	# 1280x720 a square 11x11 ring gives 65.45px cells, so this was already broken before B1.
	var band: float = clampf(h * BAND_FRACTION, 88.0, maxf(88.0, (h - 9.0 * MIN_CELL) * 0.5))
	var ring_h: float = maxf(h, 2.0 * band + 9.0 * MIN_CELL)
	var ring_w: float = maxf(w, 2.0 * CORNER_MIN_W + 9.0 * MIN_CELL)
	var corner: float = clampf(band * 1.68, CORNER_MIN_W, maxf(CORNER_MIN_W, (ring_w - 9.0 * MIN_CELL) * 0.5))
	return {
		"band": band,
		"corner": corner,
		"ring_w": ring_w,
		"ring_h": ring_h,
		"origin": Vector2((w - ring_w) * 0.5, (h - ring_h) * 0.5),
		"step_x": (ring_w - 2.0 * corner) / 9.0,
		"step_y": (ring_h - 2.0 * band) / 9.0,
	}


## The rect of ring cell `i` (classic order: GO bottom-right, anti-clockwise). Coordinates are in the
## board's own space: `origin` is negative when the ring is larger than the frame.
static func tile_rect(i: int, m: Dictionary, _frame: Vector2) -> Rect2:
	var band: float = m["band"]
	var corner: float = m["corner"]
	var sx: float = m["step_x"]
	var sy: float = m["step_y"]
	var o: Vector2 = m.get("origin", Vector2.ZERO)
	var w: float = m["ring_w"]
	var h: float = m["ring_h"]
	if i == 0:
		return Rect2(o + Vector2(w - corner, h - band), Vector2(corner, band))
	if i == 10:
		return Rect2(o + Vector2(0, h - band), Vector2(corner, band))
	if i == 20:
		return Rect2(o + Vector2(0, 0), Vector2(corner, band))
	if i == 30:
		return Rect2(o + Vector2(w - corner, 0), Vector2(corner, band))
	if i < 10:
		return Rect2(o + Vector2(corner + float(9 - i) * sx, h - band), Vector2(sx, band))
	if i < 20:
		return Rect2(o + Vector2(0, h - band - float(i - 10) * sy), Vector2(band, sy))
	if i < 30:
		return Rect2(o + Vector2(corner + float(i - 21) * sx, 0), Vector2(sx, band))
	# the right column runs between the two right corners: y starts at BAND, because a corner is
	# corner-WIDE but only band-TALL (measured bug: starting at `corner` made cell 38 overlap cell 0
	# by 189.6x37.7 on 1600x1200).
	return Rect2(o + Vector2(w - band, band + float(i - 31) * sy), Vector2(band, sy))


func _place_board() -> void:
	var frame := size
	var m := ring_metrics(frame)
	var band: float = m["band"]
	_cell = band                       # the design's reference unit: the band's thickness
	var rebuild: bool = _tiles.is_empty() or absf(band - _band_px) > 0.5
	_band_px = band
	if rebuild:
		for t in _tiles:
			t.queue_free()
		_tiles.clear()
		for i in _board.size():
			var tv = TileView.new()
			var data: Dictionary = _board[i]
			var r0: Rect2 = tile_rect(i, m, frame)
			var ring_side: String = "corner" if _is_corner(i) else _ring_side(i)
			add_child(tv)
			tv.setup(_skin, i, data, r0.size.x, ring_side, r0.size.y)
			# a corner is a SCREEN, not a plot: its face stays (the band and the border carry the
			# ring's rhythm) but its own name/price step aside for the glance line.
			tv.set_plain(_is_corner(i))
			tv.pressed.connect(func(idx: int) -> void: tile_clicked.emit(idx))
			_tiles.append(tv)
	for i in _tiles.size():
		var r: Rect2 = tile_rect(i, m, frame)
		var tv2 = _tiles[i]
		tv2.position = r.position
		tv2.size = r.size
		# width/height change with the frame, and `setup` does not re-lay-out a built tile: without
		# this the labels keep the widths of the PREVIOUS frame (measured: the ring kept 95px text
		# boxes after the frame went to 1600x1200).
		tv2.resize(r.size.x, r.size.y)
	for pid in _tokens.keys():
		var tok: Control = _tokens[pid]
		var idx: int = int(_token_pos.get(pid, 0))
		tok.position = _token_screen_pos(idx, int(pid), 4)
	_apply_glance()


func _place_centre() -> void:
	# R-13: the panno is given ONE rect - the ring's interior - and lays itself out from there.
	# Nothing inside it is positioned by absolute coordinates derived from the screen size.
	# B1: the interior is now the RECTANGLE inside the bands, not a square: at 1600x1200 it is
	# 1221x821, which is why the centre can hold a hub plus four panels instead of a 9x9 hole.
	if _panno == null:
		return
	var m := ring_metrics(size)
	var band: float = m["band"]
	var o: Vector2 = m["origin"]
	var inner := Rect2(o + Vector2(band, band),
		Vector2(maxf(1.0, float(m["ring_w"]) - 2.0 * band), maxf(1.0, float(m["ring_h"]) - 2.0 * band)))
	_panno.position = inner.position
	_panno.size = inner.size
	_panno.apply_scale(_cell)
	# the dice keep the game's own art; only their size follows the band, as before
	var die_px: float = maxf(18.0, roundf(_cell * 0.34))
	for d in _dice:
		d.custom_minimum_size = Vector2(die_px, die_px)
	_sum.add_theme_font_size_override("font_size", maxi(14, int(_cell * 0.34)))
	_banner.add_theme_font_size_override("font_size", maxi(11, int(_cell * 0.20)))
	_card_name.add_theme_font_size_override("font_size", maxi(12, int(_cell * 0.18)))
	_card_price.add_theme_font_size_override("font_size", maxi(11, int(_cell * 0.16)))


## Watermark shows in the cold state only (proto renderCenter).
func set_watermark(v: bool) -> void:
	# The watermark is RETIRED from the centre: the panno's event zone already says "партия не
	# начата" and the cold state is a full surface now. The flag stays because the shell and the
	# cold path still toggle it; the labels themselves never show again.
	_watermark = v
	_wm1.visible = false
	_wm2.visible = false


func set_cold() -> void:
	set_watermark(true)
	_banner.visible = false
	_card.visible = false
	if _panno != null:
		_panno.set_cold(true)
	for pid in _tokens:
		(_tokens[pid] as Control).visible = false


## Paint from the spectator projection.
func sync(proj: Dictionary, seats: Array, human_pid: int) -> void:
	var entries := {}
	var by_index := {}
	for e in (proj.get("board", []) as Array):
		by_index[int(e.get("index", -1))] = e
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var turn_pos := -1
	for p in (proj.get("players", []) as Array):
		if int(p.get("index", -1)) == turn:
			turn_pos = int(p.get("position", -1))
	for i in _board.size():
		# `.duplicate()` IS REQUIRED, not defensive noise: `Dictionary.get(key, default)` returns the
		# DEFAULT ITSELF (read-only) when the key is absent, and the lines below assign into `e`. A
		# projection that carries only the tiles it knows about - which the auction test's does, and
		# which any partial push from the server legitimately can - made every missing index throw
		# "Invalid assignment on read-only value". The board itself was fine; the copy was not made.
		var e: Dictionary = (by_index.get(i, {}) as Dictionary).duplicate()
		var owner: int = int(e.get("owner", -1))
		if owner >= 0:
			var nm := str(e.get("owner_name", ""))
			var col: Color = UiTheme.COL().accent
			for s in seats:
				if int(s.pid) == owner:
					col = s.color
					if nm == "":
						nm = str(s.name)
			e["owner_color"] = col
			e["owner_name"] = nm
		e["active"] = i == turn_pos and not _watermark
		e["selected"] = i == _selected
		entries[i] = e
	_entries = entries
	for i in _tiles.size():
		_tiles[i].apply(entries.get(i, {}))
	_sync_tokens(proj, seats)
	_sync_centre(proj, seats, human_pid)
	_sync_glance(proj, seats, human_pid)


## The shell hands over the SAME finished journal line it gives the toast and the feed, plus the
## last few sentences for the panno's journal zone (R-14: the panno computes no game state).
func set_last_line(line: Dictionary) -> void:
	_last_line = line


func set_journal_tail(lines: Array) -> void:
	_journal_tail = lines


func _sync_centre(proj: Dictionary, seats: Array, human_pid: int) -> void:
	# The panno paints FIRST and unconditionally: the zones (dice, players, journal) must be
	# current in every phase, including the AUCTION branch below that returns early.
	if _panno != null:
		_panno.sync(proj, seats, human_pid, _last_line, _journal_tail)
	var phase: String = str(proj.get("phase", ""))
	var dice: Array = proj.get("dice", [0, 0])
	if int(dice[0]) > 0 and not _rolling:
		set_dice(int(dice[0]), int(dice[1]))
	var turn: int = int(proj.get("turn_player", proj.get("turn", -1)))
	var nm := ""
	var col: Color = UiTheme.COL().accent
	for s in seats:
		if int(s.pid) == turn:
			nm = str(s.name)
			col = s.color
	var ph_lbl: String = I18n.t("phase." + phase)
	if ph_lbl.begins_with("{phase."):
		ph_lbl = phase
	_banner.text = "%s · %s" % [nm, ph_lbl]
	_banner.add_theme_color_override("font_color", col)
	_banner.visible = nm != "" and phase != ""
	var pend: Dictionary = proj.get("pending", {})
	var is_card: bool = str(pend.get("type", "")) in ["purchase", "auction"] or phase == "AUCTION"
	# E-4/D12: while an AUCTION runs, the CENTRE of the board says so - the lot, the standing bid and
	# who leads it - and every new bid updates it. Until now an auction was visible only to whoever
	# had the sheet open: a spectator watching the board saw the same turn label as during any other
	# phase, so the most dramatic moment in the game was invisible from the ring.
	if phase == "AUCTION":
		var at_name: String = ""
		var at_tile: int = int(pend.get("tile", -1))
		for e in (proj.get("board", []) as Array):
			if int(e.get("index", -1)) == at_tile:
				at_name = str(e.get("name", ""))
		var at_high: int = int(pend.get("high", -1))
		var at_lead: String = _seat_name_of(proj, seats, int(pend.get("high_player", -1)))
		var line := I18n.t("board.auction_plate", [at_name])
		if at_high > 0:
			line = I18n.t("board.auction_plate_bid", [at_name, at_high, at_lead])
		# the plate is a live message like an event: same queue, so a bid overwrites the previous bid
		_banner.text = line
		_banner.add_theme_color_override("font_color", UiTheme.COL().money if at_high > 0 else col)
		_banner.visible = at_name != ""
		_card.visible = is_card
		if is_card:
			_card_name.text = at_name
			_card_price.text = "$%d" % int(pend.get("cost", 0)) if pend.has("cost") else "$%d" % at_high
		return
	if is_card:
		var tile_idx: int = int(pend.get("tile", -1))
		var t: Dictionary = {}
		for e in (proj.get("board", []) as Array):
			if int(e.get("index", -1)) == tile_idx:
				t = e
		_card_name.text = str(t.get("name", ""))
		_card_price.text = "$%d" % int(t.get("cost", 0))


## E-4: a seat's display name by pid (the auction plate names the leading bidder).
func _seat_name_of(_proj: Dictionary, seats: Array, pid: int) -> String:
	for s in seats:
		if int(s.pid) == pid:
			return str(s.name)
	return ""


func _sync_tokens(proj: Dictionary, seats: Array) -> void:
	var players: Array = proj.get("players", [])
	var seen := {}
	for p in players:
		var pid: int = int(p.get("index", 0))
		seen[pid] = true
		var col: Color = UiTheme.COL().accent
		for s in seats:
			if int(s.pid) == pid:
				col = s.color
		var tok: Control = _tokens.get(pid)
		if tok == null:
			tok = Panel.new()
			tok.custom_minimum_size = Vector2(16, 16)
			tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tok.add_theme_stylebox_override("panel",
				UiTheme.box(Color(col.r, col.g, col.b, 0.35), col, 2, 8))
			add_child(tok)
			_tokens[pid] = tok
		var pos: int = int(p.get("position", 0))
		var target := _token_screen_pos(pos, pid, players.size())
		var old: int = int(_token_pos.get(pid, -1))
		if old != pos and old >= 0:
			var tw := create_tween()
			tw.tween_property(tok, "position", target, _dur(0.19))
		else:
			tok.position = target
		_token_pos[pid] = pos
		tok.visible = not bool(p.get("bankrupt", false))
	for pid in _tokens.keys():
		if not seen.has(pid):
			(_tokens[pid] as Control).visible = false


func _token_screen_pos(idx: int, pid: int, count: int) -> Vector2:
	if _cell <= 0.0 or _tiles.is_empty():
		return Vector2.ZERO
	var i: int = clampi(idx, 0, _tiles.size() - 1)
	var tile: Control = _tiles[i]
	var base: Vector2 = tile.position + tile.size * 0.5
	var fan: float = 16.0
	return base + Vector2((pid % 3 - 1) * fan, ((pid / 3) % 2 - 0.5) * fan) - Vector2(8, 8) * 0.5


## ZOOM-01: where a seat's token sits, in the board's own coordinate space. The camera centres on
## this. Returns null when the seat is unknown (a seat that left, or a cold frame), so the camera
## says "no target" instead of jumping to the origin.
func token_board_pos(pid: int) -> Variant:
	if not _tokens.has(pid):
		return null
	var tok: Control = _tokens[pid]
	if not tok.visible:
		return null
	return tok.position + tok.size * 0.5


## Select a tile: re-apply the state layer only.
func set_selected(idx: int) -> void:
	_selected = idx
	for i in _tiles.size():
		var e: Dictionary = _entries.get(i, {})
		e["selected"] = i == idx
		_tiles[i].apply(e)


## The roll: the TRAY tumbles and settles on the decided faces (0.85s).
func roll_tray(d1: int, d2: int) -> void:
	_roll_to = Vector2i(clampi(d1, 1, 6), clampi(d2, 1, 6))
	_rolling = true
	_roll_t = 0.0
	_roll_swap = 0.0
	_sum.visible = false
	_doubles.visible = false
	set_process(true)


func set_dice(a: int, b: int) -> void:
	for i in _dice.size():
		(_dice[i] as Control).set_meta("value", a if i == 0 else b)
		(_dice[i] as Control).queue_redraw()
	_sum.visible = a > 0
	if a > 0:
		_sum.text = str(a + b)
	_doubles.visible = a > 0 and a == b


## E-2 (master-fix-plan §2, D10): put ONE engine event on the BOARD.
##
## WHY: purchase, build, jail, bankruptcy, tax, winner and trade left no visual trace on the board
## at all - the only feedback was a 3-second toast in a side dock, which a viewer following the ring
## (or watching the stream's board) never sees. The centre already had a `_banner`; it showed the
## current turn and nothing else. Now it speaks the event, and the participating CELL pulses its
## frame for a second, so the eye is taken to the place the event happened.
##
## `text` is pre-rendered by the caller (the same JournalLines renderer the feed uses), so the
## board, the journal and the toast cannot disagree about what happened.
func show_event(text: String, color: Color = Color.TRANSPARENT, tile: int = -1) -> void:
	if text.strip_edges() == "":
		return
	var col: Color = UiTheme.COL().accent if color.a <= 0.0 else color
	_ev_queue.append({"text": text, "color": col, "tile": tile})
	if tile >= 0:
		_flash[tile] = FLASH_HOLD
	set_process(true)   # a message must animate even if the dice are still


## Advance the banner queue and the flash timers. Split out so `show_event` and the tests can drive
## it without a live frame loop.
func _tick_events(delta: float) -> void:
	# the flash: expire tiles whose pulse is over, then repaint the state frames
	if not _flash.is_empty():
		var done: Array = []
		for k in _flash.keys():
			_flash[k] = float(_flash[k]) - delta
			if float(_flash[k]) <= 0.0:
				done.append(k)
		for k in done:
			_flash.erase(k)
		_repaint_entries()
	# the banner: show the newest message for EV_HOLD, then fall back to the turn label
	if _ev_shown < _ev_queue.size():
		_ev_timer += delta
		var msg: Dictionary = _ev_queue[_ev_shown]
		_banner.text = str(msg["text"])
		_banner.add_theme_color_override("font_color", msg["color"])
		_banner.visible = true
		if _ev_timer >= EV_HOLD:
			_ev_timer = 0.0
			_ev_shown += 1
			if _ev_shown >= _ev_queue.size():
				# queue drained: hand the banner back to the turn label
				_ev_queue.clear()
				_ev_shown = 0
				_repaint_entries()


## Is an event message on the banner right now (as opposed to the turn label)?
func event_banner_active() -> bool:
	return _ev_shown < _ev_queue.size()


## The message currently on the banner, for a test to read back.
func event_banner_text() -> String:
	return _banner.text if event_banner_active() else ""


## Is the given cell pulsing?
func cell_flashing(idx: int) -> bool:
	return _flash.has(idx)


func _repaint_entries() -> void:
	for i in _tiles.size():
		var e: Dictionary = _entries.get(i, {})
		if _flash.has(i):
			e["flash"] = true
		_tiles[i].apply(e)


func _process(delta: float) -> void:
	# E-2: the event banner and the cell flash tick on the SAME clock as the dice, so this node
	# always processes. It used to `return` early when not rolling, which would have frozen the
	# queue the moment the dice settled.
	_tick_events(delta)
	if not _rolling:
		return
	var dur := 0.85
	_roll_t += delta
	_roll_swap += delta
	if _roll_swap >= 0.085:
		_roll_swap = 0.0
		for i in _dice.size():
			(_dice[i] as Control).set_meta("value", 1 + (i * 3 + int(_roll_t * 24.0)) % 6)
			(_dice[i] as Control).queue_redraw()
	var p: float = clampf(_roll_t / dur, 0.0, 1.0)
	for i in _dice.size():
		var d: Control = _dice[i]
		d.pivot_offset = d.size * 0.5
		d.rotation = sin(p * TAU * 2.4 + float(i) * 1.7) * 0.55 * (1.0 - p)
		d.scale = Vector2(1.0, 1.0 - 0.25 * sin(p * PI))
	if _roll_t >= dur:
		_rolling = false
		# NOTE: process stays ON. It used to be switched off here, which was fine while the dice
		# were the only animation - but the event banner (E-2) and the cell flash live on this same
		# tick, and turning it off when the dice settled would have frozen them mid-message.
		for d in _dice:
			(d as Control).rotation = 0.0
			(d as Control).scale = Vector2.ONE
		set_dice(_roll_to.x, _roll_to.y)


## Play one engine event (adapter shape): roll tumbles the tray, move hops the token.
func play_event(ev: Dictionary) -> void:
	var k: String = str(ev.get("k", ""))
	if k == "roll":
		roll_tray(int(ev.get("a", 1)), int(ev.get("b", 1)))
	elif k in ["move", "teleport"]:
		var pid: int = int(ev.get("p", -1))
		var to: int = int(ev.get("ti", -1))
		if pid >= 0 and to >= 0 and _tokens.has(pid):
			var tw := create_tween()
			tw.tween_property(_tokens[pid], "position", _token_screen_pos(to, pid, 4), _dur(0.19))


func _draw_die(holder: Control) -> void:
	var v: int = int(holder.get_meta("value", 1))
	var s: Vector2 = holder.size
	var side: float = maxf(4.0, minf(s.x, s.y))
	var base := Rect2((s - Vector2(side, side)) * 0.5, Vector2(side, side))
	holder.draw_rect(base, UiTheme.skin().color("dice_bg", Color(0.95, 0.96, 0.98)))
	var col: Color = UiTheme.skin().color("dice_ink", Color(0.09, 0.1, 0.12))
	var foot: Color = col
	foot.a = 0.2
	var fh: float = maxf(2.0, minf(4.0, side * 0.11))
	holder.draw_rect(Rect2(base.position + Vector2(0.0, base.size.y - fh), Vector2(side, fh)), foot)
	var pad: float = maxf(2.0, side * 0.12)
	var cell: float = (side - pad * 2.0) / 3.0
	for p in _pip_positions(v):
		var c := base.position + Vector2(
			pad + (float(p[0]) + 0.5) * cell,
			pad + (float(p[1]) + 0.5) * cell)
		holder.draw_circle(c, maxf(1.5, cell * 0.31), col)


static func _pip_positions(v: int) -> Array:
	match v:
		1: return [[1, 1]]
		2: return [[0, 0], [2, 2]]
		3: return [[0, 0], [1, 1], [2, 2]]
		4: return [[0, 0], [2, 0], [0, 2], [2, 2]]
		5: return [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]
		6: return [[0, 0], [2, 0], [0, 1], [2, 1], [0, 2], [2, 2]]
	return []
