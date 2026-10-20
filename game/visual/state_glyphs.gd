class_name StateGlyphs
extends RefCounted
## THE VISUAL GRAMMAR OF THE BOARD - a fact about a cell is a FORM, not a word.
##
## The owner's complaint (20.10): "не пиши, а показывай в дизайне (к примеру кто владеет и
## состояние, сколько отелей и так далее)". The board answered it in words: the owner was a
## LETTER in a badge ("N", "M", "e"), the house count was the text "×3" beside 5x5 squares,
## and the mortgage was the letter "M". A letter is not a shape; "×3" is not a count.
##
## This module is the grammar, ported from the concept A mockup
## (design/variants/v5/concept-a-composition.html) and made reusable:
##
##   owner      a filled flag in the OWNER'S COLOUR, plus the owner's colour band on the
##              cell's inner edge - shape AND colour, so it survives colour-blindness (R-26)
##   house      a house silhouette; 1..4 of them, side by side
##   hotel      a wide slab with a spire - a DIFFERENT silhouette, not a bigger house (R-23)
##   mortgage   diagonal hatching, not the letter "M" (R-24)
##   jail       three vertical bars
##   jail card  a receipt with a torn corner
##   active     a ring around the current player's mark
##   pot        a stack of coins (the parking pot)
##
## Everything is drawn as inline SVG paths, so a glyph costs no asset, scales with the cell
## and inherits the colour it is given. The paths are 14x14 viewBox units.
##
## WHY A STATIC HELPER AND NOT A SCENE: the board draws hundreds of cells; a node per glyph
## per cell would be hundreds of nodes that exist only to hold a path. A Control with a
## `draw` override draws the same path for a fraction of the cost, and it keeps the
## visual layer free of scene-tree churn on every board rebuild.
##
## The COLOURS come from the caller (UiTheme/skin), never from here: the visual layer never
## hardcodes a colour literal. A glyph is drawn in `currentColor` terms - the caller sets
## `modulate`.

const VIEW := 14.0
## The path data of every glyph, in the 14x14 viewBox of the concept mockup. Kept verbatim
## from design/variants/v5/concept-a-composition.html so the board and the mockup show the
## same shapes.
const PATHS := {
	"house": "M6 .8 11.2 4.8v6.4H.8V4.8Z",
	"hotel": "M.8 11.2V4.4h4V2h4v2.4h4v6.8Z",
	"card": "M1 1h10v14H1Z",
	"bars": "M1 1.4h12M1 12.6h12M3 2v10M6 2v10M9 2v10M12 2v10",
	"star": "M7 .6 8.6 5.4 13.4 7 8.6 8.6 7 13.4 5.4 8.6.6 7 5.4 5.4Z",
	"coin": "M7 1a6 6 0 1 0 0 12 6 6 0 1 0 0-12Z",
	"station": "M1 6 8 1l7 5v1.4H1Z",
	"tower": "M7 1v14M4 4h6M2.6 15 7 4l4.4 11M1 15h12",
	"pin": "M6 1a4.4 4.4 0 0 1 4.4 4.4c0 3.2-4.4 9.6-4.4 9.6S1.6 8.6 1.6 5.4A4.4 4.4 0 0 1 6 1Z",
	"meeple": "M8 1 14.4 6v6.4L8 19 1.6 12.4V6Z",
	"arrow": "M1.5 6h11M8.4 1.8 12.6 6l-4.2 4.2",
	"hatch": "M1 9 9 1M4 9l5-5",
	"dice": "M1 1h14v14H1Z",
}
## The glyphs that are STROKED, not filled. The rest are filled shapes.
const STROKED := {
	"card": 1.4, "bars": 1.5, "coin": 1.4, "station": 1.3, "tower": 1.3,
	"arrow": 1.7, "hatch": 1.4, "dice": 1.4, "pin": 0.0,
}


## The number of house silhouettes that stands for a given house count.
##
## 0 -> none, 1..4 -> that many, 5 (a hotel) -> a single HOTEL silhouette. The hotel is NOT
## five houses and NOT a wider house: a different shape, so it reads as a different fact
## (R-23: five distinguishable states by silhouette).
static func house_glyph_count(houses: int) -> int:
	if houses <= 0:
		return 0
	if houses >= 5:
		return 1
	return mini(houses, 4)


## Whether the given house count is a HOTEL (5) rather than houses.
static func is_hotel(houses: int) -> bool:
	return houses >= 5


## Draw one glyph into a CanvasItem, centred in the given rect.
##
## `which` is a key of PATHS. An unknown key draws nothing rather than crashing: a missing
## glyph is a hole in the grammar, and the board must still render.
static func draw_glyph(ci: CanvasItem, which: String, rect: Rect2, colour: Color,
		width_scale: float = 1.0) -> void:
	if not PATHS.has(which):
		return
	var d: String = PATHS[which]
	# the strokes are authored on the 14-unit box; the path data is scaled from it
	var s: float = minf(rect.size.x, rect.size.y) / VIEW
	if s <= 0.0:
		return
	var origin := rect.position + (rect.size - Vector2(VIEW, VIEW) * s) * 0.5
	# The points are SCALED AND MOVED HERE, not through `draw_set_transform`. The transform
	# version looked right and drew the shape in the top-left corner of the cell at 1/14 of
	# its size - and the probe measured it as "one house and three houses draw the same
	# ink", because every house landed on the same few pixels. Transforming the points
	# cannot get out of step with the drawing.
	var col := colour
	if STROKED.has(which):
		var pts := PackedVector2Array()
		for p in stroke_points(d, which):
			pts.append(origin + p * s)
		ci.draw_polyline(pts, col, float(STROKED[which]) * width_scale, true)
	else:
		var poly := PackedVector2Array()
		for p in fill_points(d):
			poly.append(origin + p * s)
		ci.draw_colored_polygon(poly, col)


## The house counter as a FORM: `count` silhouettes side by side, a hotel instead of houses.
##
## Returns the rect the row occupies, so the caller can place it.
static func house_row(ci: CanvasItem, houses: int, rect: Rect2, colour: Color) -> Rect2:
	if houses <= 0:
		return Rect2()
	var hotel := is_hotel(houses)
	var n := house_glyph_count(houses)
	var gap := rect.size.x * 0.12 / maxf(1.0, float(n))
	var w: float = (rect.size.x - gap * float(n - 1)) / float(n)
	var h: float = minf(rect.size.y, w)
	for i in n:
		var cell := Rect2(rect.position.x + (w + gap) * float(i), rect.position.y, w, h)
		draw_glyph(ci, "hotel" if hotel else "house", cell, colour)
	return Rect2(rect.position, Vector2(w * float(n) + gap * float(n - 1), h))


## The mortgage mark: diagonal hatching, drawn as lines, not the letter "M" (R-24).
## The lines are DATA (`hatch_lines`): a hatch that reaches every corner is a texture over
## the cell; a letter is a glyph in the middle of it.
static func hatch_lines(rect: Rect2) -> Array[PackedVector2Array]:
	var step: float = maxf(3.0, rect.size.x * 0.28)
	var out: Array[PackedVector2Array] = []
	var x := rect.position.x - rect.size.y
	while x < rect.position.x + rect.size.x:
		out.append(PackedVector2Array([
			Vector2(x, rect.position.y + rect.size.y),
			Vector2(x + rect.size.y, rect.position.y)]))
		x += step
	return out


static func draw_mortgage(ci: CanvasItem, rect: Rect2, colour: Color) -> void:
	var w: float = maxf(1.0, rect.size.x * 0.10)
	for seg in hatch_lines(rect):
		ci.draw_line(seg[0], seg[1], colour, w, true)


## The owner mark: a filled flag in the owner's colour (R-22 - shape AND colour, R-26).
## A POLE and a PENNANT: two parts, so "there is a flag here" is a shape and not a letter.
static func owner_flag_parts(rect: Rect2) -> Array:
	var pole_w: float = maxf(1.0, rect.size.x * 0.16)
	var fx := rect.position.x + pole_w
	var fw := rect.size.x - pole_w
	var pennant := PackedVector2Array([
		Vector2(fx, rect.position.y),
		Vector2(fx + fw, rect.position.y + rect.size.y * 0.5),
		Vector2(fx, rect.position.y + rect.size.y),
	])
	return [Rect2(rect.position, Vector2(pole_w, rect.size.y)), pennant]


static func draw_owner_flag(ci: CanvasItem, rect: Rect2, colour: Color) -> void:
	var parts := owner_flag_parts(rect)
	ci.draw_rect(parts[0], colour, true)
	if parts[1].size() >= 3:
		ci.draw_colored_polygon(parts[1], colour)


## The jail mark: three vertical bars. The bars are DATA (`jail_bars`), the drawing is the
## renderer - so "is it really three bars" is a question a test can answer.
static func jail_bars(rect: Rect2) -> Array[Rect2]:
	var n := 3
	var gap := rect.size.x * 0.18
	var w: float = (rect.size.x - gap * float(n - 1)) / float(n)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(rect.position.x + (w + gap) * float(i), rect.position.y, w,
			rect.size.y))
	return out


## The jail mark: three vertical bars.
static func draw_jail(ci: CanvasItem, rect: Rect2, colour: Color) -> void:
	for bar in jail_bars(rect):
		ci.draw_rect(bar, colour, true)


## The "get out of jail" card: a receipt with a torn corner.
static func draw_card(ci: CanvasItem, rect: Rect2, colour: Color) -> void:
	var w: float = rect.size.x * 0.7
	var h: float = rect.size.y
	ci.draw_rect(Rect2(rect.position, Vector2(w, h)), colour, false, maxf(1.0, w * 0.10))
	# the torn corner: three short lines biting into the top-right
	var bite: float = w * 0.3
	ci.draw_line(Vector2(rect.position.x + w - bite, rect.position.y),
		Vector2(rect.position.x + w, rect.position.y + bite), colour,
		maxf(1.0, w * 0.10), true)


# --- the path helpers ---------------------------------------------------------------
#
# The glyph paths above are SVG path DATA. Godot's CanvasItem cannot draw an SVG path
# string directly, so the few shapes we need are reconstructed from their geometry. A
# glyph that cannot be reconstructed is drawn as its bounding form, never as a crash.

## The filled outline of a glyph, in the 14x14 box. PUBLIC: the grammar is DATA, the
## drawing is a thin renderer over it. A test can then ask what a shape IS without a
## frame - the runner calls test functions synchronously, so a test that awaited a rendered
## frame would never get its result.
static func fill_points(d: String) -> PackedVector2Array:
	match d:
		"M6 .8 11.2 4.8v6.4H.8V4.8Z":
			# house: a pentagon
			return PackedVector2Array([Vector2(6, .8), Vector2(11.2, 4.8),
				Vector2(11.2, 11.2), Vector2(.8, 11.2), Vector2(.8, 4.8)])
		"M.8 11.2V4.4h4V2h4v2.4h4v6.8Z":
			# hotel: a stepped slab
			return PackedVector2Array([Vector2(.8, 11.2), Vector2(.8, 4.4),
				Vector2(4.8, 4.4), Vector2(4.8, 2), Vector2(8.8, 2), Vector2(8.8, 4.4),
				Vector2(12.8, 4.4), Vector2(12.8, 11.2)])
		"M7 .6 8.6 5.4 13.4 7 8.6 8.6 7 13.4 5.4 8.6.6 7 5.4 5.4Z":
			# star: five points
			return PackedVector2Array([Vector2(7, .6), Vector2(8.6, 5.4), Vector2(13.4, 7),
				Vector2(8.6, 8.6), Vector2(7, 13.4), Vector2(5.4, 8.6), Vector2(.6, 7),
				Vector2(5.4, 5.4)])
		"M6 1a4.4 4.4 0 0 1 4.4 4.4c0 3.2-4.4 9.6-4.4 9.6S1.6 8.6 1.6 5.4A4.4 4.4 0 0 1 6 1Z":
			# pin: a teardrop
			var pts := PackedVector2Array()
			for i in 25:
				var t := TAU * float(i) / 24.0
				pts.append(Vector2(6 + 4.4 * sin(t), 5.4 - 4.4 * cos(t)))
			pts.append(Vector2(6, 15))
			return pts
		"M8 1 14.4 6v6.4L8 19 1.6 12.4V6Z":
			# meeple: a body
			return PackedVector2Array([Vector2(8, 1), Vector2(14.4, 6), Vector2(14.4, 12.4),
				Vector2(8, 19), Vector2(1.6, 12.4), Vector2(1.6, 6)])
		"M1 6 8 1l7 5v1.4H1Z":
			# station: a roof
			return PackedVector2Array([Vector2(1, 6), Vector2(8, 1), Vector2(15, 6),
				Vector2(15, 7.4), Vector2(1, 7.4)])
	return PackedVector2Array([Vector2(0, 0), Vector2(VIEW, 0), Vector2(VIEW, VIEW),
		Vector2(0, VIEW)])


## The stroked outline of a glyph, in the 14x14 box. PUBLIC, for the same reason.
static func stroke_points(d: String, which: String) -> PackedVector2Array:
	match which:
		"bars":
			var pts := PackedVector2Array()
			pts.append(Vector2(1, 1.4)); pts.append(Vector2(13, 1.4))
			pts.append(Vector2(1, 12.6)); pts.append(Vector2(13, 12.6))
			for x in [3.0, 6.0, 9.0, 12.0]:
				pts.append(Vector2(x, 2)); pts.append(Vector2(x, 12))
			return pts
		"arrow":
			return PackedVector2Array([Vector2(1.5, 6), Vector2(12.5, 6), Vector2(8.4, 1.8),
				Vector2(12.6, 6), Vector2(8.4, 10.2)])
		"hatch":
			return PackedVector2Array([Vector2(1, 9), Vector2(9, 1), Vector2(4, 9),
				Vector2(9, 4)])
		"tower":
			return PackedVector2Array([Vector2(7, 1), Vector2(7, 15), Vector2(4, 4),
				Vector2(10, 4), Vector2(2.6, 15), Vector2(11.4, 15), Vector2(1, 15),
				Vector2(13, 15)])
		"coin":
			var pts := PackedVector2Array()
			for i in 25:
				var t := TAU * float(i) / 24.0
				pts.append(Vector2(7 + 6 * cos(t), 7 + 6 * sin(t)))
			return pts
		"card":
			return PackedVector2Array([Vector2(1, 1), Vector2(11, 1), Vector2(11, 15),
				Vector2(1, 15), Vector2(1, 1)])
		"dice":
			return PackedVector2Array([Vector2(1, 1), Vector2(15, 1), Vector2(15, 15),
				Vector2(1, 15), Vector2(1, 1)])
	return PackedVector2Array()
