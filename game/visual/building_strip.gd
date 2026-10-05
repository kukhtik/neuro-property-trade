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
	var px: float = maxf(4.0, minf(float(cell) * skin.metric("house_size", 0.019) * 7.0, s * 0.8))
	var hotel: bool = count >= 5
	var n: int = 1 if hotel else mini(count, 4)
	var tex: Texture2D = skin.texture(SLOT_HOTEL if hotel else SLOT_HOUSE)
	var gap: float = maxf(1.0, px * 0.15)
	var total: float = float(n) * px + float(n - 1) * gap
	var x: float = (size.x - (px if vertical else total)) * 0.5
	var y: float = (size.y - (total if vertical else px)) * 0.5

	for i in n:
		var r := Rect2(Vector2(x, y), Vector2(px, px))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			_draw_fallback(r, hotel)
		if vertical:
			y += px + gap
		else:
			x += px + gap


## A token-coloured house/hotel when the skin ships no art.
func _draw_fallback(r: Rect2, hotel: bool) -> void:
	var body: Color = skin.color("money", skin.color("accent"))
	var roof: Color = skin.color("accent")
	if hotel:
		draw_rect(r, body)
		draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, r.size.y * 0.25))), roof)
	else:
		# house: a roof triangle-ish band over a body
		var roof_h: float = maxf(1.5, r.size.y * 0.38)
		draw_rect(Rect2(r.position + Vector2(r.size.x * 0.15, roof_h),
			Vector2(r.size.x * 0.7, r.size.y - roof_h)), body)
		draw_rect(Rect2(r.position + Vector2(r.size.x * 0.15, 0.0),
			Vector2(r.size.x * 0.7, roof_h)), roof)
