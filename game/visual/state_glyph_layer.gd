class_name StateGlyphLayer
extends Control
## The board cell's STATE, drawn as shapes - the owner, the houses, the mortgage.
##
## This is the layer that answers the owner's complaint (20.10): "не пиши, а показывай в
## дизайне (к примеру кто владеет и состояние, сколько отелей и так далеве)".
##
## Before this layer the cell said all of it in WORDS:
##   owner      a Label with the owner's first letter ("N", "M", "e") in a coloured box
##   houses     5x5 px squares plus the text "×3"
##   mortgage   a Label with the letter "M"
## A letter is not a shape, "×3" is not a count, and a 5px square is a dot. What the owner
## asked for is that a viewer who does NOT read the numbers still knows who owns the tile
## and how built up it is.
##
## After this layer the cell says it in FORMS, taken from the concept A mockup
## (design/variants/v5/concept-a-composition.html):
##   owner      a filled flag in the owner's colour, standing on the cell's inner edge
##   houses     one house silhouette per house, side by side (a hotel is a different shape)
##   mortgage   diagonal hatching across the cell, not a letter
##
## WHY A SEPARATE CONTROL AND NOT PAINTING IN `TileView`: the tile already owns its face,
## its band and its text. This layer is a transparent overlay ON TOP of them, positioned by
## the tile, and it redraws only when the STATE changes - not on every layout pass. The
## board has 40 cells; a redraw per cell per frame would be the kind of cost the owner
## feels on a weak machine ("медленно на слабых").
##
## COLOURS: never hardcoded. The caller passes the owner's colour and the theme's danger
## colour in; the visual layer does not decide what a colour means.

const StateGlyphs := preload("res://visual/state_glyphs.gd")

## The state to draw. Read at draw time, so a change is one `queue_redraw()` away.
var owner_index: int = -1
var owner_colour: Color = Color.WHITE
var houses: int = 0
var mortgaged: bool = false

## Where the marks go, in this control's own coordinates. The tile sets them.
var owner_rect: Rect2 = Rect2()
var houses_rect: Rect2 = Rect2()
var mortgage_rect: Rect2 = Rect2()
## The colour the hatching and the houses are drawn in. Set by the tile from the theme.
var house_colour: Color = Color.WHITE
var danger_colour: Color = Color.RED


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Apply a projection entry: the same dictionary `TileView.apply()` receives.
func apply(entry: Dictionary, theme_success: Color, theme_danger: Color) -> void:
	owner_index = int(entry.get("owner", -1))
	owner_colour = entry.get("owner_color", Color.WHITE)
	houses = int(entry.get("houses", 0))
	mortgaged = bool(entry.get("mortgaged", false))
	house_colour = theme_success
	danger_colour = theme_danger
	queue_redraw()


func _draw() -> void:
	# the mortgage is UNDER the other marks: hatching is a texture of the cell, the flag and
	# the houses are things ON it. A viewer reads the texture first and the things second.
	if mortgaged:
		StateGlyphs.draw_mortgage(self, mortgage_rect, danger_colour)
	if houses > 0:
		StateGlyphs.house_row(self, houses, houses_rect, house_colour)
	if owner_index >= 0:
		StateGlyphs.draw_owner_flag(self, owner_rect, owner_colour)
