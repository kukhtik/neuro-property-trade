extends RefCounted
## The board's VISUAL GRAMMAR: a fact about a cell is a FORM, not a word.
##
## The owner's complaint (20.10): "не пиши, а показывай в дизайне (к примеру кто владеет и
## состояние, сколько отелей и так далее)". The board answered it in words - the owner was a
## LETTER in a badge, the house count was the text "×3", the mortgage was the letter "M".
##
## These tests pin the grammar itself, because a grammar that drifts is worse than no
## grammar: the board would keep drawing shapes that mean nothing.
##
## The grammar is DATA (`StateGlyphs.fill_points`, `.stroke_points`, `.jail_bars`,
## `.hatch_lines`, `.owner_flag_parts`) and the drawing is a thin renderer over it. That
## split is what makes these tests possible: the test runner calls test functions
## SYNCHRONOUSLY, so a test that awaited a rendered frame would never get its result. The
## pixel proof - that the shapes actually land on the screen - lives in the probe scene
## `res://tools/state_glyphs_probe.tscn`.

const StateGlyphs := preload("res://visual/state_glyphs.gd")


static func test_list() -> Array[String]:
	return [
		"test_every_glyph_has_geometry",
		"test_house_count_is_a_count_of_silhouettes",
		"test_hotel_is_a_different_shape_than_a_house",
		"test_mortgage_is_hatching_not_a_letter",
		"test_mortgage_hatch_reaches_both_edges",
		"test_owner_flag_is_a_pole_and_a_pennant",
		"test_jail_is_three_bars",
		"test_jail_card_is_not_a_house",
		"test_house_row_grows_with_the_count",
		"test_a_house_is_bigger_than_a_dot",
	]


## Every glyph in the vocabulary has GEOMETRY. A glyph with no points is a hole in the
## grammar: the board would draw nothing where a fact should be.
static func test_every_glyph_has_geometry() -> String:
	for which in StateGlyphs.PATHS.keys():
		var d: String = StateGlyphs.PATHS[which]
		var filled := StateGlyphs.fill_points(d)
		var stroked := StateGlyphs.stroke_points(d, str(which))
		if filled.size() < 3 and stroked.size() < 2:
			return "the glyph '%s' has no geometry: %d fill point(s), %d stroke point(s)" % [
				str(which), filled.size(), stroked.size()]
	return ""


## The house counter as a COUNT: 0, 1, 2, 3, 4 houses are five distinguishable states, and
## the hotel is a sixth - a different shape, not a fifth house (R-23).
static func test_house_count_is_a_count_of_silhouettes() -> String:
	for h in range(0, 5):
		if StateGlyphs.house_glyph_count(h) != h:
			return "%d houses must be %d silhouettes, got %d" % [
				h, h, StateGlyphs.house_glyph_count(h)]
	if StateGlyphs.house_glyph_count(5) != 1:
		return "a hotel (5) must be ONE silhouette, got %d" % StateGlyphs.house_glyph_count(5)
	return ""


## The hotel is a DIFFERENT shape than a house. If the two had the same outline, "four
## houses" and "a hotel" would be the same fact - the failure the requirement names.
static func test_hotel_is_a_different_shape_than_a_house() -> String:
	var house := StateGlyphs.fill_points(StateGlyphs.PATHS["house"])
	var hotel := StateGlyphs.fill_points(StateGlyphs.PATHS["hotel"])
	if house.size() < 3:
		return "the house has no outline"
	if hotel.size() < 3:
		return "the hotel has no outline"
	if house.size() == hotel.size() and _same_points(house, hotel):
		return "the house and the hotel have the SAME outline - they must be different shapes"
	return ""


static func _same_points(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.01:
			return false
	return true


## The mortgage is a HATCH, not a letter: a texture across the cell, not a glyph in it.
static func test_mortgage_is_hatching_not_a_letter() -> String:
	var rect := Rect2(0, 0, 36, 36)
	var lines := StateGlyphs.hatch_lines(rect)
	if lines.size() < 3:
		return "the mortgage mark has %d line(s) - a hatch over a 36px cell needs several" \
			% lines.size()
	for seg in lines:
		if seg.size() < 2:
			return "a hatch line has no endpoints"
	return ""


## A hatch REACHES THE EDGES: the top edge and the bottom edge both carry hatching. A letter
## "M" sits in the middle and leaves the corners bare - which is how the old board looked.
static func test_mortgage_hatch_reaches_both_edges() -> String:
	var rect := Rect2(0, 0, 36, 36)
	var lines := StateGlyphs.hatch_lines(rect)
	var top := 0
	var bottom := 0
	for seg in lines:
		var a := seg[0]
		var b := seg[1]
		if a.y <= 0.5 or b.y <= 0.5:
			top += 1
		if a.y >= 35.5 or b.y >= 35.5:
			bottom += 1
	if top == 0:
		return "no hatch line reaches the top edge - the mark would read as a letter"
	if bottom == 0:
		return "no hatch line reaches the bottom edge - the mark would read as a letter"
	return ""


## The owner mark is a POLE and a PENNANT - a flag, not a letter.
static func test_owner_flag_is_a_pole_and_a_pennant() -> String:
	var parts := StateGlyphs.owner_flag_parts(Rect2(0, 0, 36, 36))
	if parts.size() != 2:
		return "the owner flag has %d part(s), expected 2 (a pole and a pennant)" % parts.size()
	var pole: Rect2 = parts[0]
	if pole.size.x <= 0.0 or pole.size.y <= 0.0:
		return "the flag's pole has no size"
	var pennant: PackedVector2Array = parts[1]
	if pennant.size() < 3:
		return "the flag's pennant has %d point(s), expected 3" % pennant.size()
	return ""


## The jail is three bars, and the COUNT is the fact.
static func test_jail_is_three_bars() -> String:
	var bars := StateGlyphs.jail_bars(Rect2(0, 0, 36, 36))
	if bars.size() != 3:
		return "the jail mark has %d bar(s), expected 3" % bars.size()
	# the bars must not overlap - three bars that touch read as one shape
	for i in bars.size():
		for j in range(i + 1, bars.size()):
			if bars[i].intersects(bars[j]):
				return "jail bars %d and %d overlap - they read as one shape" % [i, j]
	return ""


## The jail card must not be mistaken for a house.
static func test_jail_card_is_not_a_house() -> String:
	var card := StateGlyphs.stroke_points(StateGlyphs.PATHS["card"], "card")
	var house := StateGlyphs.fill_points(StateGlyphs.PATHS["house"])
	if card.size() < 2:
		return "the jail card has no outline"
	if house.size() < 3:
		return "the house has no outline"
	if card.size() == house.size() and _same_points(card, house):
		return "the jail card and the house have the same outline"
	return ""


## The house row GROWS with the count: one house is narrower than two, which is what makes
## "how many" readable without reading a number.
static func test_house_row_grows_with_the_count() -> String:
	var one := StateGlyphs.house_glyph_count(1)
	var four := StateGlyphs.house_glyph_count(4)
	if four <= one:
		return "the house row does not grow with the count (%d -> %d)" % [one, four]
	return ""


## A house is BIGGER THAN A DOT. The old board drew the house counter as 5x5 px squares: at
## 720p that is 4.5px, and a 4.5px square is a dot, not a house. The silhouette has to
## occupy a real share of the cell.
static func test_a_house_is_bigger_than_a_dot() -> String:
	var pts := StateGlyphs.fill_points(StateGlyphs.PATHS["house"])
	if pts.size() < 3:
		return "the house has no outline"
	var minx := 99.0
	var maxx := -99.0
	var miny := 99.0
	var maxy := -99.0
	for p in pts:
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y); maxy = maxf(maxy, p.y)
	var area := (maxx - minx) * (maxy - miny)
	# the house box in the 14-unit space is about 10.4 x 10.4
	if area < 40.0:
		return ("the house silhouette occupies %.1f square units of the 14x14 box - a shape "
			+ "that small is a dot") % area
	return ""
