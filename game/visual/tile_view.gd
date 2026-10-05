class_name TileView
extends Control
## A single board tile rendered as a structured widget (spec §4.2, P2, P6).
## The base is the dark `tile.svg` (light text). A colored group band sits on
## the edge facing the board center; houses/hotel are SVG sprites on the band;
## the name is up to 2 lines (auto-fit) in full mode, one line with ellipsis in
## compact mode; the price sits at the bottom. Ownership is a 2px frame + a
## round badge with the owner's initial at the OUTER edge. A mortgaged tile is
## desaturated + hatched.
##
## SKINNING (P6): every asset path and color is resolved through SkinManager
## (skin.json) — no hardcoded `res://assets/...` or `Color(...)` literals here.
## Swapping the look = replacing the skin directory + config.
##
## ORIENTATION (P6): the band always faces the board CENTER. tile_layout seg 1
## is the LEFT column (x=0) and seg 3 the RIGHT column (x=s), so seg 1 -> band
## on the RIGHT edge (3) and seg 3 -> band on the LEFT edge (1). The old
## `[0,1,2,3][seg]` mapping put both vertical bands OUTWARD (the bug).
##
## Highlights (spec §4.2): active tile = glowing accent frame (pulse 0.8 Hz);
## inspector-selected = dashed accent frame; valid management targets = soft
## 12% fill. All sizes are PROPORTIONAL to the cell so tiles stay readable at
## any board scale.

const TL := preload("res://visual/tile_layout.gd")
const PI := preload("res://core/player_identity.gd")
const SkinManager := preload("res://visual/skin_manager.gd")

const COMPACT_THRESHOLD := 44   # below this cell, compact mode (spec §4.2)

var _cell := 64
var _tile_count := 0   # set by build(); never assume 40 — the board is parametric
var _index := 0
var _band_edge := 0   # 0=top,1=left,2=bottom,3=right (edge facing board center)
var _compact := false
var _skin: SkinManager

# children
var _base: TextureRect
var _band: ColorRect
var _name: Label
var _price: Label
var _icon: TextureRect
var _house_row: HBoxContainer
var _owner_frame: ColorRect
var _owner_badge: Control
var _badge_label: Label
var _mortgage_hatch: Control
var _active_frame: ColorRect
var _select_frame: ColorRect
var _target_fill: ColorRect

var _active := false
var _selected := false
var _target := false
var _pulse_phase := 0.0
var _type := "property"   # last tile type from refresh (for probes/tests)

## Build the tile widget for `index`. `cell` is the tile size in px.
func build(index: int, tile_count: int, cell: int, skin: SkinManager = null) -> void:
	_index = index
	_tile_count = tile_count
	_cell = cell
	_skin = skin if skin != null else SkinManager.new()
	_skin.load_skin()
	_compact = cell < _skin.compact_threshold()
	custom_minimum_size = Vector2(cell, cell)
	size = Vector2(cell, cell)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# base: dark tile.svg (light text). Fall back to a flat dark panel if the
	# asset is missing (code-built seam so art can swap without logic changes).
	_base = TextureRect.new()
	_base.texture = _skin.texture("tile_bg")
	_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	if _base.texture == null:
		var flat := ColorRect.new()
		flat.color = _skin.color("tile_bg", Color("20252f"))
		flat.set_anchors_preset(Control.PRESET_FULL_RECT)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_base.add_child(flat)

	# group band on the edge facing the board center
	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	# owner frame: 2px border around the whole tile (spec §4.2)
	_owner_frame = ColorRect.new()
	_owner_frame.color = Color.TRANSPARENT
	_owner_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_owner_frame)

	# owner badge: round ⌀12px with the owner's initial, in the corner at the
	# OUTER edge (opposite the band)
	_owner_badge = Control.new()
	_owner_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_owner_badge)
	_badge_label = Label.new()
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", maxi(7, int(_cell * 0.16)))
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_badge_label.add_theme_constant_override("outline_size", 1)
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_owner_badge.add_child(_badge_label)

	# mortgage hatch: diagonal stripes overlay (drawn via _draw)
	_mortgage_hatch = _make_hatch()
	_mortgage_hatch.visible = false
	_mortgage_hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mortgage_hatch)

	# name label (centered) — up to 2 lines in full mode, 1 line ellipsis in
	# compact mode (spec §4.2)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if not _compact else TextServer.AUTOWRAP_OFF
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.add_theme_font_size_override("font_size", _font_for_name())
	_name.add_theme_color_override("font_color", _skin.color("tile_text", Color("e8edf3")))
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	# price / amount label (bottom) — hidden in compact mode (spec §4.2)
	_price = Label.new()
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.add_theme_font_size_override("font_size", _font_for_price())
	_price.add_theme_color_override("font_color", _skin.color("tile_price", Color("c8d0dc")))
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price.visible = not _compact
	add_child(_price)

	# corner / type icon (SVG sprite) — sized <= 0.35*cell, centered in the
	# content area so it never overlaps the name/price (P6)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)

	# houses row along the band edge
	_house_row = HBoxContainer.new()
	_house_row.add_theme_constant_override("separation", 2)
	_house_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_house_row)

	# highlight frames (spec §4.2): active = glowing accent, selected = dashed
	_active_frame = ColorRect.new()
	_active_frame.color = Color.TRANSPARENT
	_active_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_active_frame.visible = false
	add_child(_active_frame)
	_select_frame = ColorRect.new()
	_select_frame.color = Color.TRANSPARENT
	_select_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_frame.visible = false
	add_child(_select_frame)
	# soft fill for valid management targets (P6: color from skin)
	_target_fill = ColorRect.new()
	_target_fill.color = _with_alpha(_skin.color("highlight.active", Color("4fb3d9")),
		_skin.proportion("highlight.target_alpha", 0.12))
	_target_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_fill.visible = false
	add_child(_target_fill)

	_layout_edges()

## Font sizes scale with the cell so tiles stay readable at any board scale.
func _font_for_name() -> int:
	# auto-fit 9..13px (spec §4.2): scale with cell, clamped
	return clampi(int(_cell * 0.20), 9, 13)
func _font_for_price() -> int:
	# small enough that the label's line height fits the price band (P6)
	return maxi(7, int(_cell * 0.13))

## Build the mortgage hatch overlay (diagonal stripes via _draw).
func _make_hatch() -> Control:
	var c := Control.new()
	c.set_script(_HatchScript)
	return c

const _HatchScript := preload("res://visual/tile_hatch.gd")

## Position the band, name, price, icon, houses, owner frame/badge and
## highlight frames based on which edge faces the board center.
## Layout the tile's children. The icon sits in the corner NEAR the band edge
## (inner corner), and the name is centered in the remaining content area with
## its width/height clamped so it can NEVER overlap the icon (C2: text on icon).
## Corner tiles (GO/jail/etc) override the icon to center in refresh().
func _layout_edges() -> void:
	var c := float(_cell)
	var band_w := maxf(9.0, c * _skin.proportion("band_thickness", 0.25))
	var pad := maxf(2.0, c * 0.05)
	# The price label's minimum height is ~23px (default font line height), so
	# the price band must be at least that tall or the label overflows (P6).
	var price_h := maxf(23.0, c * 0.22)
	var seg := _index / (_tile_count / 4)
	# P6 band orientation fix: seg 1 is the LEFT column (x=0) and seg 3 the
	# RIGHT column (x=s). The band must face the board CENTER, so:
	#   seg 0 (bottom row)  -> band on TOP    (0)
	#   seg 1 (left col)    -> band on RIGHT  (3)   [center is to the right]
	#   seg 2 (top row)     -> band on BOTTOM (2)
	#   seg 3 (right col)   -> band on LEFT   (1)   [center is to the left]
	_band_edge = [0, 3, 2, 1][seg]

	# owner badge sits at the OUTER edge (opposite the band)
	var badge_d := maxf(10.0, c * _skin.proportion("badge_frac", 0.20))
	var badge_off := maxf(2.0, c * 0.04)

	# highlight frames cover the whole tile
	for f in [_active_frame, _select_frame, _target_fill]:
		f.position = Vector2.ZERO
		f.size = Vector2(c, c)

	# icon: proportional, <= 0.35*cell, in the inner corner near the band.
	# The floor is small (8px) so it never exceeds 0.35*cell on small tiles.
	var icon_max := c * _skin.proportion("icon_max_frac", 0.35)
	var icon_d := maxf(8.0, icon_max)

	# Force exact label rects so a label's font minimum height can't push it
	# past the tile edge (P6 overflow fix). clip_text keeps the text inside.
	# Pin custom_minimum_size to the CLAMPED size (>=0) so the font's ~23px
	# minimum can't force the rect past the tile at small cells (36px).
	_name.clip_text = true
	_price.clip_text = true

	match _band_edge:
		0:  # top band — icon in top-right corner, name left of it
			_band.position = Vector2(0, 0)
			_band.size = Vector2(c, band_w)
			_icon.position = Vector2(c - icon_d - pad, band_w + pad)
			_icon.size = Vector2(icon_d, icon_d)
			_name.position = Vector2(pad, band_w + pad)
			_name.size = Vector2(maxf(0.0, c - pad * 2 - icon_d), maxf(0.0, c - band_w - price_h - pad * 2))
			_name.custom_minimum_size = _name.size
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c, price_h)
			_price.custom_minimum_size = _price.size
			_house_row.position = Vector2(pad, band_w + pad)
			_house_row.size = Vector2(c - pad * 2, 8)
			_owner_badge.position = Vector2(c - badge_d - badge_off, c - badge_d - badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		1:  # left band — icon in top-left corner, name to its RIGHT (horizontal,
			# so the name keeps full height even at small cells where stacking
			# icon-above-name would overflow the tile)
			_band.position = Vector2(0, 0)
			_band.size = Vector2(band_w, c)
			_icon.position = Vector2(band_w + pad, pad)
			_icon.size = Vector2(icon_d, icon_d)
			_name.position = Vector2(band_w + pad + icon_d, pad)
			_name.size = Vector2(maxf(0.0, c - band_w - pad * 2 - icon_d), maxf(0.0, c - price_h - pad * 2))
			_name.custom_minimum_size = _name.size
			_price.position = Vector2(band_w, c - price_h)
			_price.size = Vector2(c - band_w, price_h)
			_price.custom_minimum_size = _price.size
			_house_row.position = Vector2(band_w + pad, pad)
			_house_row.size = Vector2(c - band_w - pad * 2, 8)
			_owner_badge.position = Vector2(c - badge_d - badge_off, c - badge_d - badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		2:  # bottom band — icon in top-right corner, name left of it
			_band.position = Vector2(0, c - band_w)
			_band.size = Vector2(c, band_w)
			_icon.position = Vector2(c - icon_d - pad, pad)
			_icon.size = Vector2(icon_d, icon_d)
			_name.position = Vector2(pad, pad)
			_name.size = Vector2(maxf(0.0, c - pad * 2 - icon_d), maxf(0.0, c - band_w - price_h - pad * 2))
			_name.custom_minimum_size = _name.size
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c, price_h)
			_price.custom_minimum_size = _price.size
			_house_row.position = Vector2(pad, c - band_w - 10)
			_house_row.size = Vector2(c - pad * 2, 8)
			_owner_badge.position = Vector2(badge_off, badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		3:  # right band — icon in top-left corner, name right of it
			_band.position = Vector2(c - band_w, 0)
			_band.size = Vector2(band_w, c)
			_icon.position = Vector2(pad, pad)
			_icon.size = Vector2(icon_d, icon_d)
			_name.position = Vector2(pad + icon_d, pad)
			_name.size = Vector2(maxf(0.0, c - band_w - pad * 2 - icon_d), maxf(0.0, c - price_h - pad * 2))
			_name.custom_minimum_size = _name.size
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c - band_w, price_h)
			_price.custom_minimum_size = _price.size
			_house_row.position = Vector2(pad, pad)
			_house_row.size = Vector2(c - band_w - pad * 2, 8)
			_owner_badge.position = Vector2(badge_off, badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)

## Repaint from a projection tile entry.
func refresh(entry: Dictionary) -> void:
	var typ: String = str(entry.get("type", "property"))
	_type = typ
	var is_corner: bool = TL.is_corner(_index, _tile_count)
	var is_property: bool = (typ == "property")

	# band color: group color for properties, type color otherwise
	_band.color = _tile_color(entry)

	# name: use `short` in compact mode, full name in full mode (spec §4.2)
	var short: String = str(entry.get("short", entry.get("name", "")))
	var full: String = str(entry.get("name", ""))
	_name.text = short if _compact else full
	_name.visible = not is_corner

	# price / amount
	if is_corner:
		_price.text = ""
		_icon.visible = true
		_icon.texture = _skin.texture("corner_icons." + typ)
		# corner tiles have no name — center the icon in the tile (C2)
		var c := float(_cell)
		var icon_d: float = _icon.size.x
		_icon.position = Vector2((c - icon_d) * 0.5, (c - icon_d) * 0.5)
	elif is_property:
		_price.text = "$%d" % int(entry.get("cost", 0))
		_icon.visible = false
	elif typ == "tax":
		_price.text = "$%d" % int(entry.get("amount", 0))
		_icon.visible = true
		_icon.texture = _skin.texture("type_icons." + typ)
	else:
		# railroad / utility / chance / community: show cost or icon
		var cost: int = int(entry.get("cost", 0))
		_price.text = ("$%d" % cost) if cost > 0 else ""
		_icon.visible = true
		_icon.texture = _skin.texture("type_icons." + typ)
	# compact mode hides the price (spec §4.2)
	_price.visible = not _compact

	# owner frame + badge
	var ow: int = int(entry.get("owner", -1))
	if ow >= 0:
		var col: Color = PI.color_of(ow)
		_owner_frame.color = col
		_owner_frame.visible = true
		_owner_badge.visible = true
		_badge_label.text = _initial_of(str(entry.get("owner_name", "")))
		_badge_label.add_theme_color_override("font_color", _contrast(col))
	else:
		_owner_frame.color = Color.TRANSPARENT
		_owner_frame.visible = false
		_owner_badge.visible = false

	# houses as SVG sprites along the band edge
	_clear_houses()
	var h: int = int(entry.get("houses", 0))
	if is_property and h > 0:
		var hs := maxi(8, int(_cell * _skin.proportion("house_frac", 0.20)))
		var n: int = mini(h, 4)
		for i in n:
			_house_row.add_child(_make_house_sprite(_skin.path("houses.house"), hs))
		if h >= 5:
			_house_row.add_child(_make_house_sprite(_skin.path("houses.hotel"), hs + 2))

	# mortgage: desaturate the base + hatch overlay (P6: dim color from skin)
	var mortgaged: bool = bool(entry.get("mortgaged", false))
	_mortgage_hatch.visible = mortgaged
	if mortgaged:
		var dim: Color = _skin.color("mortgage.dim", Color("999999"))
		_base.modulate = dim
		_band.modulate = dim
		_owner_frame.color = _owner_frame.color.darkened(0.4)
	else:
		_base.modulate = Color.WHITE
		_band.modulate = Color.WHITE

## Tile fill color from the skin (group color for properties, type otherwise).
func _tile_color(entry: Dictionary) -> Color:
	var t: String = str(entry.get("type", "property"))
	if t == "property":
		var g: String = str(entry.get("group", ""))
		return _skin.color("group." + g, _skin.color("type.property", Color("c8ccd4")))
	return _skin.color("type." + t, Color.WHITE)

## A house/hotel SVG sprite sized to `px`.
func _make_house_sprite(path: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _load_or_null(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## Load a texture by path, returning null if missing.
func _load_or_null(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null

func _clear_houses() -> void:
	for c in _house_row.get_children():
		_house_row.remove_child(c)
		c.queue_free()

## First letter of a name, uppercased (fallback to a pid letter).
func _initial_of(name: String) -> String:
	var n := name.strip_edges()
	if n.length() > 0:
		return n.substr(0, 1).to_upper()
	return "?"

## A readable text color on a given background (white on dark, black on light).
func _contrast(bg: Color) -> Color:
	var lum: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color.BLACK if lum > 0.6 else Color.WHITE

## Highlight state setters (spec §4.2). Active = glowing accent frame,
## selected = dashed accent frame, target = soft fill. Colors from skin (P6).
func set_active(v: bool) -> void:
	_active = v
	_active_frame.visible = v
	if v:
		_active_frame.color = _with_alpha(_skin.color("highlight.active", Color("4fb3d9")),
			_skin.proportion("highlight.active_alpha", 0.9))
	else:
		_active_frame.color = Color.TRANSPARENT

func set_selected(v: bool) -> void:
	_selected = v
	_select_frame.visible = v
	if v:
		_select_frame.color = _with_alpha(_skin.color("highlight.active", Color("4fb3d9")),
			_skin.proportion("highlight.selected_alpha", 0.6))
	else:
		_select_frame.color = Color.TRANSPARENT

func set_target(v: bool) -> void:
	_target = v
	_target_fill.visible = v

func _process(delta: float) -> void:
	# active frame pulse (0.8 Hz) — spec §4.2
	if _active:
		_pulse_phase += delta * TAU * 0.8
		var min_a: float = _skin.proportion("highlight.pulse_min_alpha", 0.5)
		var amp: float = _skin.proportion("highlight.pulse_amp", 0.4)
		var a := min_a + amp * (0.5 + 0.5 * sin(_pulse_phase))
		_active_frame.color = _with_alpha(_skin.color("highlight.active", Color("4fb3d9")), a)

## Set a color's alpha (Godot 4.7 Color has no with_alpha()).
func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
