extends RefCounted
class_name SkinPaint
## Visual EFFECTS the mockup draws that a plain colour cannot express.
##
## The mockup is not built from colours — it is built from gradients, glows, shadows and
## stripes. Comparing palettes matched 11 of 11 tokens and still missed the whole look,
## because none of that language existed on our side: a board drawn with one flat fill can
## never look like a board that floats on a radial gradient with an accent halo.
##
## Everything here derives from the skin's OWN tokens, so a skin still describes itself and
## no colour is hard-coded. Pure functions returning styles and textures: headless-testable.

const SkinManager := preload("res://visual/skin_manager.gd")

## How strongly a mixed effect leans toward its own colour (0..1 of the blend).
const ACCENT_IN_STAGE := 0.10
const ACCENT_AT_CORNER := 0.20
const HI_AT_CORNER := 0.18
const FRAME_EDGE := 0.45


## Mix `a` toward `b`. GDScript has lerp for floats only.
static func mix(a: Color, b: Color, t: float) -> Color:
	return Color(
		lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), lerpf(a.a, b.a, t))


## Mix with transparency, the way `color-mix(..., transparent)` behaves: keep the colour,
## scale the alpha. This is what the mockup's corner glows actually do.
static func tint(c: Color, t: float) -> Color:
	return Color(c.r, c.g, c.b, t)


## The scene behind the board: pools of accent light, fading into the backdrop.
##
## The mockup's final `#stage` is TWO radial gradients — accent at one corner and accent2 at
## the opposite — not one. A single pool lights the board from a side; two give it an
## environment. `size` only matters as an aspect hint for the texture.
static func stage_texture(skin: SkinManager, size: Vector2) -> GradientTexture2D:
	var bg: Color = skin.color("bg")
	var ac: Color = skin.color("accent")
	var hi: Color = skin.color("accent2", ac)
	var tex := GradientTexture2D.new()
	# the texture is stretched to the frame, so this is a shape hint: the gradient runs
	# from the top-left corner outward, and a second pass (below) is added by the caller's
	# own overlay when it wants the opposite corner
	tex.width = maxi(8, int(size.x))
	tex.height = maxi(8, int(size.y))
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.12, 0.08)
	tex.fill_to = Vector2(0.75, 0.70)
	var g := Gradient.new()
	# accent in the top-left, fading out; accent2 is layered on top by the caller
	g.set_color(0, mix(bg, ac, ACCENT_AT_CORNER))
	g.set_color(1, bg)
	g.add_point(0.45, mix(bg, ac, ACCENT_AT_CORNER * 0.22))
	g.set_offset(0, 0.0)
	g.set_offset(1, 1.0)
	tex.gradient = g
	return tex


## The board's own frame: a diagonal blend of accent into the line colour and out the other
## side through accent2. `#board` background in the mockup.
static func frame_texture(skin: SkinManager, size: Vector2) -> GradientTexture2D:
	var line: Color = skin.color("line")
	var ac: Color = skin.color("accent")
	var hi: Color = skin.color("accent2", ac)
	var tex := GradientTexture2D.new()
	tex.width = maxi(8, int(size.x))
	tex.height = maxi(8, int(size.y))
	tex.fill = GradientTexture2D.FILL_LINEAR
	# 135deg: top-left to bottom-right
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	var g := Gradient.new()
	g.set_color(0, mix(line, ac, FRAME_EDGE))
	g.set_color(1, mix(line, hi, FRAME_EDGE))
	g.add_point(0.35, line)
	g.add_point(0.65, line)
	tex.gradient = g
	return tex


## A tile's colour band: a vertical shade so it reads as a solid object rather than a stripe.
## `.t .bar` in the mockup.
static func band_texture(colour: Color, vertical: bool = true) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 4 if vertical else 8
	tex.height = 8 if vertical else 4
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var g := Gradient.new()
	g.set_color(0, mix(colour, Color.WHITE, 0.22))
	g.set_color(1, mix(colour, Color.BLACK, 0.32))
	g.add_point(0.5, colour)
	tex.gradient = g
	return tex


## A glow behind an object: transparent at the centre, the colour at the rim. The mockup
## uses `0 0 40px var(--gl)`; Godot has no box-shadow, so it is a soft frame instead.
static func glow_box(colour: Color, width: int = 2, radius: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint(colour, 0.16)
	sb.border_color = tint(colour, 0.55)
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = tint(colour, 0.30)
	sb.shadow_size = 14
	return sb


## A drop shadow for a panel, so it sits ABOVE the backdrop instead of being pasted on it.
## The mockup's `0 24px 70px #000b`, approximated with the shadow the engine has.
static func lift_box(bg: Color, radius: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 8)
	sb.set_corner_radius_all(radius)
	return sb


## The animated sweep under the header: a gradient from transparent through accent and
## accent2 and back. `#top::after` in the mockup.
static func sweep_texture(skin: SkinManager, width: int = 300) -> GradientTexture2D:
	var ac: Color = skin.color("accent")
	var hi: Color = skin.color("accent2", ac)
	var tex := GradientTexture2D.new()
	tex.width = width
	tex.height = 2
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	var g := Gradient.new()
	g.set_color(0, tint(ac, 0.0))
	g.set_color(1, tint(hi, 0.0))
	g.add_point(0.25, ac)
	g.add_point(0.5, hi)
	g.add_point(0.75, ac)
	tex.gradient = g
	return tex


## A hatched stripe pattern, for a band that must read as "under construction" rather than
## flat. `.t .bar` repeating-linear-gradient in the mockup.
static func hatch_texture(a: Color, b: Color, step: int = 6) -> ImageTexture:
	var n := step * 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			# 135 degrees: the diagonal decides which stripe this pixel is in
			img.set_pixel(x, y, a if ((x + y) / step) % 2 == 0 else b)
	return ImageTexture.create_from_image(img)


## The face of a tile.
##
## The mockup gives EVERY tile type its own background: `k-GO` is accent-tinted, `k-jail` is
## hatched, `k-ch` and `k-cc` lean on accent and accent2, `k-tax` is diagonally striped, and a
## plain property carries a hint of its GROUP colour. One shared `surface.1` for all of them
## is a large part of why our board read as a grid of identical rectangles.
##
## Derived entirely from the skin: `kind` selects the shape, the skin supplies the colours.
static func tile_face(skin: SkinManager, kind: String, group: Color, size: Vector2) -> Texture2D:
	var s1: Color = skin.color("surface.1")
	var s2: Color = skin.color("surface.2")
	var ac: Color = skin.color("accent")
	var hi: Color = skin.color("accent2", ac)
	var bad: Color = skin.color("danger")
	var warn: Color = skin.color("warn", Color("#e08a3c"))
	var jail: Color = skin.color("jail", bad)

	match kind:
		"go":
			return _grad(skin, mix(s2, ac, 0.35), s1, 145.0)
		"jail":
			# a hatched overlay plus a coloured wash, exactly as `.t.k-jail` layers them
			var base := _grad(skin, mix(s1, jail, 0.20), s1, 145.0)
			return _overlay_hatch(skin, base, Color(1, 1, 1, 0.05), 3, 11, 90.0)
		"parking":
			return _grad(skin, mix(s1, skin.color("park", hi), 0.20), s1, 145.0)
		"goto_jail":
			return _grad(skin, mix(s1, bad, 0.22), s1, 145.0)
		"chance":
			return _grad(skin, mix(s2, ac, 0.38), s1, 145.0)
		"chest":
			return _grad(skin, mix(s2, hi, 0.38), s1, 145.0)
		"tax":
			var t := _grad(skin, s1, s1, 0.0)
			return _overlay_hatch(skin, t, Color(warn.r, warn.g, warn.b, 0.11), 7, 7, 45.0)
		_:
			# a property: the group colour, faint, fading into the surface
			return _grad(skin, mix(s2, group, 0.16), s1, 160.0)


## A two-stop linear gradient at an angle, as a stretchable texture.
static func _grad(skin: SkinManager, from: Color, to: Color, deg: float) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_LINEAR
	var a := deg_to_rad(deg)
	var d := Vector2(cos(a), sin(a)) * 0.5
	tex.fill_from = Vector2(0.5, 0.5) - d
	tex.fill_to = Vector2(0.5, 0.5) + d
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	tex.gradient = g
	return tex


## Lay a stripe pattern over a base texture by drawing both into one image.
static func _overlay_hatch(skin: SkinManager, base: Texture2D, col: Color, on: int, off: int,
		deg: float) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# the base gradient, sampled as a two-colour ramp so no texture round-trip is needed
	var g: Gradient = base.gradient if base is GradientTexture2D else null
	var c0: Color = g.get_color(0) if g != null else Color.BLACK
	var c1: Color = g.get_color(1) if g != null else Color.WHITE
	var a := deg_to_rad(deg)
	var dir := Vector2(cos(a), sin(a))
	var period := float(on + off)
	for y in range(n):
		for x in range(n):
			var t := (Vector2(x, y) / float(n) - Vector2(0.5, 0.5)).dot(dir) + 0.5
			t = clampf(t, 0.0, 1.0)
			var px := mix(c0, c1, t)
			var phase: float = fposmod((Vector2(x, y).dot(dir)), period)
			if phase < float(on):
				px = mix(px, col, col.a)
			img.set_pixel(x, y, Color(px.r, px.g, px.b, 1.0))
	return ImageTexture.create_from_image(img)


## The token that stands on a tile, with its shadow.
##
## The mockup gives a token three things: a pentagon (`.tok b` clip-path), a halo in the
## player's colour (`0 0 14px var(--c)`), and a soft shadow underneath (`::after` blurred).
## We had the pentagon shape and nothing else, so the pieces read as flat stickers that never
## looked like they were standing on the board.
static func token_shadow(skin: SkinManager, size: float) -> Control:
	var c := Control.new()
	c.name = "TokenShadow"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(size, size * 0.22)
	var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
	# a soft ellipse, dark in the middle and fading at the rim
	for y in range(8):
		for x in range(32):
			var u := (float(x) / 31.0 - 0.5) * 2.0
			var v := (float(y) / 7.0 - 0.5) * 2.0
			var r := sqrt(u * u + v * v)
			var a := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a * 0.55))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tr)
	return c


## The halo behind a token: transparent at the centre, the colour at the rim. Godot has no
## box-shadow, so the glow is its own texture.
static func token_halo(colour: Color, size: float) -> TextureRect:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) / 2.0 - 0.5
	for y in range(n):
		for x in range(n):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			# bright at the edge, nothing in the middle: a ring of light, not a blob
			var a := clampf(1.0 - absf(d - 0.82) / 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(colour.r, colour.g, colour.b, a * 0.55))
	var tr := TextureRect.new()
	tr.name = "TokenHalo"
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
