class_name TileView
extends Control
## A single board tile rendered as a structured widget (spec §4.2, P2).
## The base is the dark `assets/tile.svg` (light text). A colored group band
## sits on the edge facing the board center; houses/hotel are SVG sprites on
## the band; the name is up to 2 lines (auto-fit 9..13px) in full mode, one
## line with ellipsis in compact mode; the price sits at the bottom. Ownership
## is a 2px frame around the tile + a round badge with the owner's initial in
## the corner at the OUTER edge. A mortgaged tile is desaturated + hatched.
##
## Highlights (spec §4.2): active tile = glowing accent frame (pulse 0.8 Hz);
## inspector-selected = dashed accent frame; valid management targets = soft
## 12% fill. All sizes are PROPORTIONAL to the cell so tiles stay readable at
## any board scale.

const TL := preload("res://visual/tile_layout.gd")
const BT := preload("res://visual/theme.gd")
const PI := preload("res://core/player_identity.gd")
const UiTheme := preload("res://ui/theme.gd")

const TILE_SVG := "res://assets/tile.svg"
const HOUSE_SVG := "res://assets/houses/house.svg"
const HOTEL_SVG := "res://assets/houses/hotel.svg"
const CORNER_ICON_PATHS := {
	"go":            "res://assets/corner_icons/go_arrow.svg",
	"jail":          "res://assets/corner_icons/jail.svg",
	"go_to_jail":    "res://assets/corner_icons/go_to_jail.svg",
	"free_parking":  "res://assets/corner_icons/free_parking.svg",
}
const TYPE_ICON_PATHS := {
	"tax":           "res://assets/type_icons/tax.svg",
	"railroad":      "res://assets/type_icons/railroad.svg",
	"utility":       "res://assets/type_icons/utility.svg",
	"chance":        "res://assets/type_icons/chance.svg",
	"community":     "res://assets/type_icons/community_chest.svg",
}

const COMPACT_THRESHOLD := 44   # below this cell, compact mode (spec §4.2)

var _cell := 64
var _tile_count := 40
var _index := 0
var _band_edge := 0   # 0=top,1=right,2=bottom,3=left (edge facing board center)
var _compact := false

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

## Build the tile widget for `index`. `cell` is the tile size in px.
func build(index: int, tile_count: int, cell: int) -> void:
	_index = index
	_tile_count = tile_count
	_cell = cell
	_compact = cell < COMPACT_THRESHOLD
	custom_minimum_size = Vector2(cell, cell)
	size = Vector2(cell, cell)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# base: dark tile.svg (light text). Fall back to a flat dark panel if the
	# asset is missing (code-built seam so art can swap without logic changes).
	_base = TextureRect.new()
	_base.texture = _load_or_null(TILE_SVG)
	_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	if _base.texture == null:
		var flat := ColorRect.new()
		flat.color = Color("20252f")
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

	# mortgage hatch: diagonal stripes overlay (drawn via a shader-free
	# approach — a set of thin rotated ColorRects is too heavy; use a
	# repeating pattern via a custom draw). We use a Control with _draw().
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
	_name.add_theme_color_override("font_color", Color("e8edf3"))
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	# price / amount label (bottom) — hidden in compact mode (spec §4.2)
	_price = Label.new()
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.add_theme_font_size_override("font_size", _font_for_price())
	_price.add_theme_color_override("font_color", Color("c8d0dc"))
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price.visible = not _compact
	add_child(_price)

	# corner / type icon (SVG sprite)
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
	# soft 12% fill for valid management targets
	_target_fill = ColorRect.new()
	_target_fill.color = Color(0.31, 0.70, 0.85, 0.12)
	_target_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_fill.visible = false
	add_child(_target_fill)

	_layout_edges()

## Font sizes scale with the cell so tiles stay readable at any board scale.
func _font_for_name() -> int:
	# auto-fit 9..13px (spec §4.2): scale with cell, clamped
	return clampi(int(_cell * 0.20), 9, 13)
func _font_for_price() -> int:
	return maxi(7, int(_cell * 0.16))
func _font_for_icon() -> int:
	return maxi(14, int(_cell * 0.42))

## Load a texture, returning null if the asset is missing (code-built seam).
func _load_or_null(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Build the mortgage hatch overlay (diagonal stripes via _draw).
func _make_hatch() -> Control:
	var c := Control.new()
	c.set_script(_HatchScript)
	return c

const _HatchScript := preload("res://visual/tile_hatch.gd")

## Position the band, name, price, icon, houses, owner frame/badge and
## highlight frames based on which edge faces the board center.
func _layout_edges() -> void:
	var c := float(_cell)
	var band_w := maxf(9.0, c * 0.25)   # proportional band thickness
	var pad := maxf(2.0, c * 0.05)
	var price_h := maxf(10.0, c * 0.20)
	var seg := _index / (_tile_count / 4)
	# bottom row (0): band on top; right col (1): band on left; top row (2):
	# band on bottom; left col (3): band on right.
	_band_edge = [0, 1, 2, 3][seg]

	# owner badge sits at the OUTER edge (opposite the band)
	var badge_d := maxf(10.0, c * 0.20)   # ⌀12px-ish, proportional
	var badge_off := maxf(2.0, c * 0.04)

	# highlight frames cover the whole tile
	for f in [_active_frame, _select_frame, _target_fill]:
		f.position = Vector2.ZERO
		f.size = Vector2(c, c)

	match _band_edge:
		0:  # top band
			_band.position = Vector2(0, 0)
			_band.size = Vector2(c, band_w)
			_name.position = Vector2(pad, band_w + pad)
			_name.size = Vector2(c - pad * 2, c - band_w - price_h - pad * 2)
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c, price_h)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_house_row.position = Vector2(pad, band_w + pad)
			_house_row.size = Vector2(c - pad * 2, 8)
			_owner_badge.position = Vector2(c - badge_d - badge_off, c - badge_d - badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		1:  # left band
			_band.position = Vector2(0, 0)
			_band.size = Vector2(band_w, c)
			_name.position = Vector2(band_w + pad, pad)
			_name.size = Vector2(c - band_w - pad * 2, c - price_h - pad * 2)
			_price.position = Vector2(band_w, c - price_h)
			_price.size = Vector2(c - band_w, price_h)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_house_row.position = Vector2(band_w + pad, pad)
			_house_row.size = Vector2(c - band_w - pad * 2, 8)
			_owner_badge.position = Vector2(c - badge_d - badge_off, c - badge_d - badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		2:  # bottom band
			_band.position = Vector2(0, c - band_w)
			_band.size = Vector2(c, band_w)
			_name.position = Vector2(pad, pad)
			_name.size = Vector2(c - pad * 2, c - band_w - price_h - pad * 2)
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c, price_h)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_house_row.position = Vector2(pad, c - band_w - 10)
			_house_row.size = Vector2(c - pad * 2, 8)
			_owner_badge.position = Vector2(badge_off, badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)
		3:  # right band
			_band.position = Vector2(c - band_w, 0)
			_band.size = Vector2(band_w, c)
			_name.position = Vector2(pad, pad)
			_name.size = Vector2(c - band_w - pad * 2, c - price_h - pad * 2)
			_price.position = Vector2(0, c - price_h)
			_price.size = Vector2(c - band_w, price_h)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_house_row.position = Vector2(pad, pad)
			_house_row.size = Vector2(c - band_w - pad * 2, 8)
			_owner_badge.position = Vector2(badge_off, badge_off)
			_owner_badge.size = Vector2(badge_d, badge_d)

## Repaint from a projection tile entry.
func refresh(entry: Dictionary) -> void:
	var typ: String = str(entry.get("type", "property"))
	var is_corner: bool = TL.is_corner(_index, _tile_count)
	var is_property: bool = (typ == "property")

	# band color: group color for properties, type color otherwise
	_band.color = BT.tile_color(entry)

	# name: use `short` in compact mode, full name in full mode (spec §4.2)
	var short: String = str(entry.get("short", entry.get("name", "")))
	var full: String = str(entry.get("name", ""))
	_name.text = short if _compact else full
	_name.visible = not is_corner

	# price / amount
	if is_corner:
		_price.text = ""
		_icon.visible = true
		_icon.texture = _load_or_null(CORNER_ICON_PATHS.get(typ, ""))
	elif is_property:
		_price.text = "$%d" % int(entry.get("cost", 0))
		_icon.visible = false
	elif typ == "tax":
		_price.text = "$%d" % int(entry.get("amount", 0))
		_icon.visible = true
		_icon.texture = _load_or_null(TYPE_ICON_PATHS.get(typ, ""))
	else:
		# railroad / utility / chance / community: show cost or icon
		var cost: int = int(entry.get("cost", 0))
		_price.text = ("$%d" % cost) if cost > 0 else ""
		_icon.visible = true
		_icon.texture = _load_or_null(TYPE_ICON_PATHS.get(typ, ""))
	# compact mode hides the price (spec §4.2) — the label's minimum height
	# would otherwise overflow the small tile
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
		var hs := maxi(8, int(_cell * 0.20))
		var n: int = mini(h, 4)
		for i in n:
			_house_row.add_child(_make_house_sprite(HOUSE_SVG, hs))
		if h >= 5:
			_house_row.add_child(_make_house_sprite(HOTEL_SVG, hs + 2))

	# mortgage: desaturate the base + hatch overlay
	var mortgaged: bool = bool(entry.get("mortgaged", false))
	_mortgage_hatch.visible = mortgaged
	if mortgaged:
		_base.modulate = Color(0.6, 0.6, 0.6, 1.0)
		_band.modulate = Color(0.6, 0.6, 0.6, 1.0)
		_owner_frame.color = _owner_frame.color.darkened(0.4)
	else:
		_base.modulate = Color.WHITE
		_band.modulate = Color.WHITE

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
## selected = dashed accent frame, target = soft fill.
func set_active(v: bool) -> void:
	_active = v
	_active_frame.visible = v
	if v:
		_active_frame.color = Color(0.31, 0.70, 0.85, 0.9)
	else:
		_active_frame.color = Color.TRANSPARENT

func set_selected(v: bool) -> void:
	_selected = v
	_select_frame.visible = v
	if v:
		_select_frame.color = Color(0.31, 0.70, 0.85, 0.6)
	else:
		_select_frame.color = Color.TRANSPARENT

func set_target(v: bool) -> void:
	_target = v
	_target_fill.visible = v

func _process(delta: float) -> void:
	# active frame pulse (0.8 Hz) — spec §4.2
	if _active:
		_pulse_phase += delta * TAU * 0.8
		var a := 0.5 + 0.4 * (0.5 + 0.5 * sin(_pulse_phase))
		_active_frame.color = Color(0.31, 0.70, 0.85, a)
