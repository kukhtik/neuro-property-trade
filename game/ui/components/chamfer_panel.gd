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

## Shade the fill vertically, light at the top to dark at the bottom (0 = flat).
##
## The mockup's colour bands are `linear-gradient(180deg, lighter, base, darker)`: a solid
## stripe reads as a flat sticker, a shaded one reads as a solid object catching light. The
## component asks for a shade, the skin supplies the amount, nothing is hardcoded.
var fill_shade := 0.0

## A texture to paint INSIDE the polygon instead of a flat colour.
##
## The mockup gives every tile type its own background — hatched for jail, accent-tinted for
## GO, striped for tax, the group's colour for a property. A single colour cannot express
## that, so a component may hand in a texture and it is clipped to the same outline.
var fill_texture: Texture2D = null
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


## Mix two colours. GDScript's lerp works on floats only.
func _mixc(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), a.a)


## Paint a texture inside the polygon. Each horizontal span is drawn as its own quad, which
## clips the texture to the outline without a second viewport or a shader.
func _draw_textured(pts: PackedVector2Array, s: Vector2) -> void:
	if pts.size() < 3 or s.y <= 0.0:
		return
	var tex_size := fill_texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	# the polygon's own bounding box, so the texture maps to the shape not the screen
	var min_y := pts[0].y
	var max_y := pts[0].y
	for p in pts:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var rows: int = clampi(int((max_y - min_y) / 2.0), 1, 96)
	var step: float = (max_y - min_y) / float(rows)
	for i in range(rows):
		var y0: float = min_y + step * float(i)
		var y1: float = y0 + step + 0.5
		# the horizontal span of the OUTLINE at this row: leftmost and rightmost crossing
		var left := INF
		var right := -INF
		var n := pts.size()
		for j in range(n):
			var a := pts[j]
			var b := pts[(j + 1) % n]
			if absf(b.y - a.y) < 0.001:
				continue
			for yy in [y0, y1]:
				if (yy >= minf(a.y, b.y)) and (yy <= maxf(a.y, b.y)):
					var t: float = (yy - a.y) / (b.y - a.y)
					var x: float = a.x + (b.x - a.x) * t
					left = minf(left, x)
					right = maxf(right, x)
		# also account for a horizontal edge crossing the row
		for p in pts:
			if p.y >= y0 and p.y <= y1:
				left = minf(left, p.x)
				right = maxf(right, p.x)
		if left >= right:
			continue
		var span := Rect2(left, y0, right - left, y1 - y0)
		var src := Rect2(
			(left / s.x) * tex_size.x, ((y0 - min_y) / maxf(max_y - min_y, 1.0)) * tex_size.y,
			((right - left) / maxf(s.x, 1.0)) * tex_size.x,
			((y1 - y0) / maxf(max_y - min_y, 1.0)) * tex_size.y)
		draw_texture_rect_region(fill_texture, span, src)


## Size to the content, as a PanelContainer does.
##
## `Panel` reports a MINIMUM SIZE OF ZERO regardless of what is inside it. Every dialog built
## on this component therefore collapsed to a 440-px line with all its content spilling out of
## the frame — which is what the modal windows had been doing all along.
func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible:
			var cm: Vector2 = (c as Control).get_combined_minimum_size()
			m = m.max(cm)
	return m


## A child changing shape must re-measure the frame. The `resized` signal is connected in
## `_build_nodes`, and children added later are picked up by `update_minimum_size` in `_draw`.
func _reflow() -> void:
	update_minimum_size()
	queue_redraw()


func _ready() -> void:
	# `Panel` never re-measures itself; every child must tell us when it changed shape
	for c in get_children():
		if c is Control and not (c as Control).resized.is_connected(_reflow):
			(c as Control).resized.connect(_reflow)


func _draw() -> void:
	var sk := _skin_or_default()
	var s := size
	var ch: float = sk.shape("chamfer", 9.0)
	# never let the chamfer eat more than a third of the shorter side
	var lim: float = minf(s.x, s.y) / 3.0
	ch = clampf(ch, 0.0, lim)

	var pts := _polygon(Vector2.ZERO, s, ch, cut)
	var fill: Color = sk.color(fill_token, Color(0, 0, 0, 0))

	# A texture is clipped to the outline with a Polygon2D mask: `draw_texture_rect` alone
	# would paint the shape's bounding box, which for a cut corner leaves a square.
	if fill_texture != null:
		_draw_textured(pts, s)
	else:
		# A shaded fill is painted as horizontal bands inside the same polygon. The mockup
		# grades its colour bands; a flat fill is why ours read as stickers rather than chips.
		if fill_shade > 0.0 and s.y > 2.0:
			var steps: int = clampi(int(s.y / 3.0), 2, 48)
			var band_h: float = s.y / float(steps)
			for i in range(steps):
				# 0 at the top (lightest), 1 at the bottom (darkest)
				var t := float(i) / float(steps - 1)
				var shade := _mixc(fill, Color.WHITE, fill_shade * 0.5 * (1.0 - t * 2.0))
				if t > 0.5:
					shade = _mixc(fill, Color.BLACK, fill_shade * (t - 0.5) * 2.0)
				var y0: float = band_h * float(i)
				var band := PackedVector2Array([
					Vector2(0, y0), Vector2(s.x, y0),
					Vector2(s.x, y0 + band_h + 1.0), Vector2(0, y0 + band_h + 1.0)])
				draw_colored_polygon(band, shade)
		else:
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
