extends Node
## The board's VISUAL GRAMMAR, PROVEN IN PIXELS.
##
## The unit test (`state_glyphs_test.gd`) pins the grammar as DATA - a house is a house, a
## hotel is not a house, the mortgage is a hatch. Data can be right while the DRAWING is
## broken, so this probe does the other half: it builds real cells, renders them, and READS
## THE PIXELS BACK.
##
## What it proves:
##   1. a cell with an owner shows the owner's COLOUR - the shape is drawn in it;
##   2. a cell with 1 house and a cell with 3 houses differ IN THE AMOUNT OF INK - the count
##      is a form, and the form grows with the fact;
##   3. a mortgaged cell shows a HATCH that reaches the cell's edges, not a letter in the
##      middle;
##   4. the house and the hotel are different shapes on the screen, not only in the data.
##
## Run: godot --headless --path game res://tools/state_glyphs_probe.tscn
## Verdict: ==> STATE-GLYPHS PASSED/FAILED (...)

const TileView := preload("res://visual/tile_view.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const StateGlyphs := preload("res://visual/state_glyphs.gd")
const UiTheme := preload("res://ui/theme.gd")

const CELL := 96.0
const CELLS := [
	{"name": "free", "data": {"short": "Free", "cost": 100, "type": "property"},
		"entry": {}},
	{"name": "owner", "data": {"short": "Owned", "cost": 100, "type": "property"},
		"entry": {"owner": 0, "owner_name": "Хост", "owner_color": Color(1.0, 0.44, 0.68)}},
	{"name": "house1", "data": {"short": "H1", "cost": 100, "type": "property"},
		"entry": {"owner": 1, "owner_name": "Neuro", "owner_color": Color(0.37, 0.89, 1.0),
			"houses": 1}},
	{"name": "house3", "data": {"short": "H3", "cost": 100, "type": "property"},
		"entry": {"owner": 1, "owner_name": "Neuro", "owner_color": Color(0.37, 0.89, 1.0),
			"houses": 3}},
	{"name": "hotel", "data": {"short": "HTL", "cost": 100, "type": "property"},
		"entry": {"owner": 1, "owner_name": "Neuro", "owner_color": Color(0.37, 0.89, 1.0),
			"houses": 5}},
	{"name": "mortgage", "data": {"short": "Mtg", "cost": 100, "type": "property"},
		"entry": {"owner": 2, "owner_name": "evil", "owner_color": Color(0.91, 0.15, 0.31),
			"mortgaged": true}},
]

## The tile needs a skin; the DEFAULT one is enough - the probe measures FORMS, not colours.
func _skin() -> SkinManager:
	var s := SkinManager.new()
	return s


var _fails: Array = []
## The cell ground, read from the ACTIVE skin - the tile paints with
## `UiTheme.COL().panel` (surface.1 of the ACTIVE skin), so that is the colour the
## probe has to subtract. It used to assume "nearly black", which was true of the
## DARK skin only.
var _bg: Color = Color(0, 0, 0)
## How close to the background a pixel must be to count AS the background.
const _BG_TOLERANCE := 0.12
var _checks := 0


func _ready() -> void:
	# A headless viewport has nothing to photograph: the pixels are read back from the
	# RENDERED frame, so the probe needs a real renderer. The gates that film the app run the
	# same way (`--rendering-driver opengl3`); without a display this probe cannot measure
	# and says so out loud instead of claiming a pass.
	if DisplayServer.get_name() == "headless":
		print("==> STATE-GLYPHS SKIPPED: no renderer (headless) - the probe photographs the "
			+ "rendered frame")
		get_tree().quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(720, 180))
	get_tree().root.size = Vector2i(720, 180)
	await get_tree().process_frame

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	host.add_child(row)

	# The ground the cells are painted on, from the ACTIVE skin.
	_bg = _read_bg()
	var views: Array = []
	for spec in CELLS:
		var tv := TileView.new()
		tv.custom_minimum_size = Vector2(CELL, CELL)
		row.add_child(tv)
		tv.setup(_skin(), int(spec.get("name", "").length()), spec["data"], CELL, "b", CELL)
		# A PLAIN cell: no name, no price, no letter badge, no text counter. Whatever ink is
		# left in the cell can only be a SHAPE - so the measurement is about the grammar and
		# not about the text that used to say the same thing. (The probe measured the text
		# before it measured the shapes, and passed with the shapes switched off.)
		tv.set_plain(true)
		tv.apply(spec["entry"])
		views.append(tv)

	# the layout needs a frame before the marks are placed
	await get_tree().process_frame
	await get_tree().process_frame

	for tv in views:
		tv.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	if img == null:
		_fail("the viewport gave no image - the probe cannot measure")
		_finish()
		return

	# read each cell's region out of the frame
	var regions: Array = []
	for i in views.size():
		var tv: TileView = views[i]
		var r: Rect2 = tv.get_global_rect()
		regions.append({"name": str(CELLS[i]["name"]), "rect": r})

	var free_ink := _ink(img, regions[0]["rect"])
	var owner_ink := _ink(img, regions[1]["rect"])
	var h1_ink := _ink(img, regions[2]["rect"])
	var h3_ink := _ink(img, regions[3]["rect"])
	var hotel_ink := _ink(img, regions[4]["rect"])
	var mtg_ink := _ink(img, regions[5]["rect"])

	# 1. the owner shows the owner's colour
	var pink := _count_colour(img, regions[1]["rect"], Color(1.0, 0.44, 0.68))
	if pink <= 0:
		_fail("the owned cell shows no pixel in the owner's colour - the flag is not drawn")
	_check(owner_ink > free_ink, "the owned cell has more ink than the free one (%d vs %d)"
		% [owner_ink, free_ink])

	# 2. the house count is a FORM: more houses, more ink
	_check(h3_ink > h1_ink, "three houses draw more ink than one (%d vs %d) - the count is a form"
		% [h3_ink, h1_ink])
	_check(h1_ink > free_ink, "a cell with a house has more ink than a free one (%d vs %d)"
		% [h1_ink, free_ink])

	# 3. the hotel is a different shape: not simply "more ink"
	_check(hotel_ink > 0, "the hotel cell draws nothing (%d)" % hotel_ink)
	_check(hotel_ink != h3_ink, ("the hotel and three houses draw the same ink (%d) - they "
		+ "must be different shapes") % hotel_ink)

	# 4. the mortgage is a hatch that REACHES the edges
	var edge := _edge_ink(img, regions[5]["rect"])
	_check(edge > 0, "the mortgaged cell has no hatching at its edges - the mark would read "
		+ "as a letter in the middle")
	_check(mtg_ink > free_ink, "the mortgaged cell has more ink than the free one (%d vs %d)"
		% [mtg_ink, free_ink])

	_finish()


## The number of pixels in the cell that are not the background.
func _ink(img: Image, rect: Rect2) -> int:
	var n := 0
	var x0 := int(maxf(0.0, rect.position.x))
	var y0 := int(maxf(0.0, rect.position.y))
	var x1 := int(minf(float(img.get_width()), rect.end.x))
	var y1 := int(minf(float(img.get_height()), rect.end.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := img.get_pixel(x, y)
			if p.a > 0.15 and not _is_bg(p):
				n += 1
	return n


## The pixels near the cell's border - where a hatch must reach and a letter never does.
func _edge_ink(img: Image, rect: Rect2) -> int:
	var n := 0
	var x0 := int(maxf(0.0, rect.position.x))
	var y0 := int(maxf(0.0, rect.position.y))
	var x1 := int(minf(float(img.get_width()), rect.end.x))
	var y1 := int(minf(float(img.get_height()), rect.end.y))
	var band := 4
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x - x0 > band and x1 - x > band and y - y0 > band and y1 - y > band:
				continue
			var p := img.get_pixel(x, y)
			if p.a > 0.15 and not _is_bg(p):
				n += 1
	return n


## The pixels close to a given colour.
func _count_colour(img: Image, rect: Rect2, want: Color) -> int:
	var n := 0
	var x0 := int(maxf(0.0, rect.position.x))
	var y0 := int(maxf(0.0, rect.position.y))
	var x1 := int(minf(float(img.get_width()), rect.end.x))
	var y1 := int(minf(float(img.get_height()), rect.end.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := img.get_pixel(x, y)
			if p.a < 0.3:
				continue
			if absf(p.r - want.r) < 0.28 and absf(p.g - want.g) < 0.28 and absf(p.b - want.b) < 0.28:
				n += 1
	return n


## The background of the cell, READ FROM THE SKIN - not assumed.
##
## The first version hard-coded "nearly black and nearly neutral", which was true
## of the DARK skin only. When neuro became the LIGHT skin, nothing was near-black
## any more, every pixel counted as ink, and all six cells measured the same
## 9216 - the gate went red for a reason that had nothing to do with the shapes.
## The background is now the skin's own tile colour, and a pixel counts as
## background when it is CLOSE to it.
func _is_bg(p: Color) -> bool:
	return _bg_dist(p) <= _BG_TOLERANCE


## How far a pixel is from the background colour (0 = the background itself).
func _bg_dist(p: Color) -> float:
	var dr := p.r - _bg.r
	var dg := p.g - _bg.g
	var db := p.b - _bg.b
	return sqrt(dr * dr + dg * dg + db * db)


## The background colour, taken from the skin the probe is measuring.
func _read_bg() -> Color:
	# the ACTIVE skin - the tile paints with UiTheme.COL().panel, and that is the
	# active skin's surface.1. A fresh SkinManager would read a different one.
	return UiTheme.COL()["panel"]


func _check(ok: bool, why: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(why)


func _fail(why: String) -> void:
	_checks += 1
	_fails.append(why)


func _finish() -> void:
	if _fails.is_empty():
		print("==> STATE-GLYPHS PASSED (%d checks: the owner's colour is drawn, the house count "
			% _checks)
		print("    is a form that grows with the fact, the hotel is its own shape, and the "
			+ "mortgage")
		print("    is a hatch that reaches the cell's edges - all read back from the pixels)")
		get_tree().quit(0)
		return
	for f in _fails:
		push_error("STATE-GLYPHS: " + str(f))
	print("==> STATE-GLYPHS FAILED (%d check(s) red)" % _fails.size())
	get_tree().quit(1)
