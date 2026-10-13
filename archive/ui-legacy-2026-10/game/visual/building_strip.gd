class_name BuildingStrip
extends Control
## Houses / hotel drawn along the group band of a tile (spec §5.5).
##
## This is a standalone component so the tile view stays layout-only: the strip
## owns the house count and paints it. It draws in `_draw` rather than spawning
## nodes, so a 64-tile board with houses allocates nothing per frame and the
## count can change without touching the tree.
##
## Art comes from the skin slots `building.house` / `building.hotel`; when a skin
## ships no art the strip draws a token-coloured figure (body + roof) so the
## board still reads. Sizes follow `metrics.house_size`, orientation follows the
## tile's band side.

var count := 0            # 0-4 houses; 5+ means a hotel
var vertical := false     # true on the left/right ring edges
var skin: SkinManager
var cell := 64

## `.tile__houses i` sizes (proto.css): a house is 5x5 px, a hotel 8x6 px.
const HOUSE_PX := 5.0
const HOTEL_W := 8.0
const HOTEL_H := 6.0

## Skin slot ids (so a skin can, if it wants, point these elsewhere).
const SLOT_HOUSE := "building.house"
const SLOT_HOTEL := "building.hotel"


func setup(p_skin: SkinManager, p_cell: int, p_vertical: bool) -> void:
	skin = p_skin
	cell = p_cell
	vertical = p_vertical
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## Set the house count: 0-4 houses, >=5 one hotel.
func set_count(n: int) -> void:
	var clamped: int = maxi(0, n)
	if clamped == count:
		return
	count = clamped
	queue_redraw()


func _draw() -> void:
	if count <= 0 or skin == null:
		return
	var s: float = minf(size.x, size.y)
	if s <= 1.0:
		return
	# `.tile__houses i { width: 5px; height: 5px }` and `.hotel i { width: 8px; height: 6px }`
	# — the mockup's marks are FIXED pixels on the band, not cell-scaled figures.
	var hotel: bool = count >= 5
	var n: int = 1 if hotel else mini(count, 4)
	var w: float = HOTEL_W if hotel else HOUSE_PX
	var h: float = HOTEL_H if hotel else HOUSE_PX
	var tex: Texture2D = skin.texture(SLOT_HOTEL if hotel else SLOT_HOUSE)
	var gap: float = 1.0
	var step: float = (h if vertical else w) + gap
	var total: float = float(n) * (h if vertical else w) + float(n - 1) * gap
	var x: float = (size.x - (w if vertical else total)) * 0.5
	var y: float = (size.y - (total if vertical else h)) * 0.5

	for i in n:
		var r := Rect2(Vector2(x, y), Vector2(h, w) if vertical else Vector2(w, h))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			_draw_fallback(r, hotel)
		if vertical:
			y += step
		else:
			x += step


## `.tile__houses { color: var(--good) }` — solid good-coloured marks when the skin ships
## no house art (none of the four skins does today; the mockup draws plain squares).
func _draw_fallback(r: Rect2, _hotel: bool) -> void:
	draw_rect(r, skin.color("good", skin.color("accent")))
