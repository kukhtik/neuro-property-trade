class_name ChamferPanel
extends Panel
## A panel with a cut (chamfered) corner — the project's signature shape.
## `StyleBoxFlat` cannot do cut corners, so this draws the polygon itself.
##
## Everything visual comes from the skin: the chamfer size is `shape.chamfer`,
## the fill is a token color (or a slot texture when the artist ships one).
## A component may set `fill_token` / `corner` before the first draw; nothing
## visual is hardcoded here.

## Skin token path for the fill, e.g. "surface.1" or "accent".
var fill_token := "surface.1"
## Skin token path for the border, e.g. "line" or "accent".
var border_token := "line"
## Which corner is cut: "tl", "tr", "br", "bl" or "none".
var cut := "tr"
## Extra border width in px added to `shape.line` (0 = skin default).
var border_bonus := 0

var _skin: SkinManager


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


## Attach a skin (components call this on build and on skin_changed).
func set_skin(skin: SkinManager) -> void:
	_skin = skin
	queue_redraw()


func _skin_or_default() -> SkinManager:
	if _skin == null:
		_skin = SkinManager.new()
		_skin.load_skin()
	return _skin


func _draw() -> void:
	var sk := _skin_or_default()
	var s := size
	var ch: float = sk.shape("chamfer", 9.0)
	# never let the chamfer eat more than a third of the shorter side
	var lim: float = minf(s.x, s.y) / 3.0
	ch = clampf(ch, 0.0, lim)

	var pts := _polygon(Vector2.ZERO, s, ch, cut)
	var fill: Color = sk.color(fill_token, Color(0, 0, 0, 0))
	draw_colored_polygon(pts, fill)

	var w := int(sk.shape("line", 1.0)) + border_bonus
	if w > 0:
		var bc: Color = sk.color(border_token, Color.WHITE)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, bc, float(w), true)


## Build the chamfered rectangle outline, clockwise from the top-left.
static func _polygon(o: Vector2, s: Vector2, ch: float, cut_corner: String) -> PackedVector2Array:
	if ch <= 0.0 or cut_corner == "none":
		return PackedVector2Array([o, o + Vector2(s.x, 0), o + s, o + Vector2(0, s.y)])
	match cut_corner:
		"tl":
			return PackedVector2Array([
				o + Vector2(ch, 0), o + Vector2(s.x, 0), o + s, o + Vector2(0, s.y), o + Vector2(0, ch),
			])
		"br":
			return PackedVector2Array([
				o, o + Vector2(s.x, 0), o + Vector2(s.x, s.y - ch), o + Vector2(s.x - ch, s.y), o + Vector2(0, s.y),
			])
		"bl":
			return PackedVector2Array([
				o, o + Vector2(s.x, 0), o + s, o + Vector2(ch, s.y), o + Vector2(0, s.y - ch),
			])
		_: # "tr" (default, matches the mock-up's primary button)
			return PackedVector2Array([
				o, o + Vector2(s.x - ch, 0), o + Vector2(s.x, ch), o + s, o + Vector2(0, s.y),
			])
