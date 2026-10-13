class_name ChamferPanel
extends Panel
## A panel with a cut (chamfered) corner — the project's signature shape, drawn from
## skin tokens. `StyleBoxFlat` cannot cut corners, so the polygon is drawn here.
##
## v3 rebuild: this file replaces the archived `ui-legacy` component. API kept minimal
## on purpose — fill token, border token, cut corner, optional border bonus.

## Skin token path for the fill, e.g. "surface.2" / "accent".
var fill_token := "surface.1"
## Skin token path for the border, e.g. "line" / "accent".
var border_token := "line"
## Which corner is cut: "tl", "tr", "br", "bl" or "none".
var cut := "tr"
## Extra border width in px on top of `shape.line`.
var border_bonus := 0

var _skin: SkinManager


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_skin(skin: SkinManager) -> void:
	_skin = skin
	queue_redraw()


func _skin_or_default() -> SkinManager:
	if _skin == null:
		_skin = SkinManager.new()
		_skin.load_skin()
	return _skin


## Size to the content (Panel itself reports zero minimum).
func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible:
			m = m.max((c as Control).get_combined_minimum_size())
	return m


func _ready() -> void:
	for c in get_children():
		if c is Control and not (c as Control).resized.is_connected(_reflow):
			(c as Control).resized.connect(_reflow)
	if not resized.is_connected(_reflow):
		resized.connect(_reflow)


func _reflow() -> void:
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var sk := _skin_or_default()
	var s := size
	var ch: float = sk.shape("chamfer", 9.0)
	ch = clampf(ch, 0.0, minf(s.x, s.y) / 3.0)
	var pts := _polygon(Vector2.ZERO, s, ch, cut)
	draw_colored_polygon(pts, sk.color(fill_token, Color.TRANSPARENT))
	var w := int(sk.shape("line", 1.0)) + border_bonus
	if w > 0:
		var inset_px := float(w)
		var closed := PackedVector2Array()
		if pts.size() >= 4 and s.x > inset_px * 2.0 and s.y > inset_px * 2.0:
			for p in pts:
				closed.append(Vector2(
					clampf(p.x, inset_px, s.x - inset_px),
					clampf(p.y, inset_px, s.y - inset_px)))
		else:
			closed = pts.duplicate()
		closed.append(closed[0])
		draw_polyline(closed, sk.color(border_token, Color.WHITE), float(w), true)


## The chamfered rectangle outline, clockwise from the top-left.
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
		_:
			return PackedVector2Array([
				o, o + Vector2(s.x - ch, 0), o + Vector2(s.x, ch), o + s, o + Vector2(0, s.y),
			])
