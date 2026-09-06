class_name TileView
extends Control
## A single board tile rendered as a structured widget (A5): a colored group
## band on the edge, the name centered, the price/amount at the bottom, and a
## distinct icon layout for corner tiles. Ownership is shown by a colored
## marker in the corner + a tinted band. Houses render as small green figures
## along the edge (A4). Code-built from shapes so art can replace it later.
##
## The tile is a square `cell` px. The "band" sits on the edge that faces the
## board center (top for bottom-row tiles, left for right-col, bottom for
## top-row, right for left-col) — computed from the tile index via TileLayout.

const TL := preload("res://visual/tile_layout.gd")
const BT := preload("res://visual/theme.gd")

const CORNER_ICONS := {
	"go": "GO",
	"jail": "⚖",
	"go_to_jail": "→⚖",
	"free_parking": "P",
}
const TYPE_ICONS := {
	"tax": "₽",
	"railroad": "🚂",
	"utility": "⚡",
	"chance": "?",
	"community": "✉",
}

var _cell := 64
var _tile_count := 40
var _index := 0
var _band: ColorRect
var _name: Label
var _price: Label
var _icon: Label
var _owner_marker: ColorRect
var _house_row: HBoxContainer
var _mortgage_stripe: ColorRect
var _band_edge := 0   # 0=top,1=right,2=bottom,3=left (edge facing board center)

## Build the tile widget for `index`. `cell` is the tile size in px.
func build(index: int, tile_count: int, cell: int) -> void:
	_index = index
	_tile_count = tile_count
	_cell = cell
	custom_minimum_size = Vector2(cell, cell)
	size = Vector2(cell, cell)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# base panel (light neutral so text reads)
	var base := ColorRect.new()
	base.color = Color("e8e6df")
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# group band on the edge facing the board center
	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	# owner marker: small square in the corner opposite the band
	_owner_marker = ColorRect.new()
	_owner_marker.color = Color.TRANSPARENT
	_owner_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_owner_marker)

	# mortgage stripe (diagonal-ish overlay when mortgaged)
	_mortgage_stripe = ColorRect.new()
	_mortgage_stripe.color = Color(0, 0, 0, 0.35)
	_mortgage_stripe.visible = false
	_mortgage_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mortgage_stripe)

	# name label (centered)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.add_theme_font_size_override("font_size", 9)
	_name.add_theme_color_override("font_color", Color("1a1a1a"))
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	# price / amount label (bottom)
	_price = Label.new()
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.add_theme_font_size_override("font_size", 8)
	_price.add_theme_color_override("font_color", Color("333333"))
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_price)

	# corner icon (for corner tiles) — big centered glyph
	_icon = Label.new()
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.add_theme_font_size_override("font_size", 20)
	_icon.add_theme_color_override("font_color", Color("1a1a1a"))
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)

	# houses row along the band edge
	_house_row = HBoxContainer.new()
	_house_row.add_theme_constant_override("separation", 2)
	_house_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_house_row)

	_layout_edges()

## Position the band, name, price, icon, houses and owner marker based on which
## edge faces the board center (derived from the tile index).
func _layout_edges() -> void:
	var c := float(_cell)
	var band_w := 10.0
	# which edge faces the board center
	var seg := _index / (_tile_count / 4)
	# bottom row (0): band on top; right col (1): band on left; top row (2):
	# band on bottom; left col (3): band on right.
	_band_edge = [0, 1, 2, 3][seg]
	match _band_edge:
		0:  # top band
			_band.position = Vector2(0, 0)
			_band.size = Vector2(c, band_w)
			_name.position = Vector2(2, band_w + 2)
			_name.size = Vector2(c - 4, c - band_w - 16)
			_price.position = Vector2(0, c - 14)
			_price.size = Vector2(c, 12)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_owner_marker.position = Vector2(c - 8, c - 8)
			_owner_marker.size = Vector2(8, 8)
			_house_row.position = Vector2(2, band_w + 2)
			_house_row.size = Vector2(c - 4, 8)
			_mortgage_stripe.position = Vector2(0, 0)
			_mortgage_stripe.size = Vector2(c, c)
		1:  # left band
			_band.position = Vector2(0, 0)
			_band.size = Vector2(band_w, c)
			_name.position = Vector2(band_w + 2, 2)
			_name.size = Vector2(c - band_w - 4, c - 16)
			_price.position = Vector2(band_w, c - 14)
			_price.size = Vector2(c - band_w, 12)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_owner_marker.position = Vector2(c - 8, c - 8)
			_owner_marker.size = Vector2(8, 8)
			_house_row.position = Vector2(band_w + 2, 2)
			_house_row.size = Vector2(c - band_w - 4, 8)
			_mortgage_stripe.position = Vector2(0, 0)
			_mortgage_stripe.size = Vector2(c, c)
		2:  # bottom band
			_band.position = Vector2(0, c - band_w)
			_band.size = Vector2(c, band_w)
			_name.position = Vector2(2, 2)
			_name.size = Vector2(c - 4, c - band_w - 16)
			_price.position = Vector2(0, c - 14)
			_price.size = Vector2(c, 12)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_owner_marker.position = Vector2(c - 8, 0)
			_owner_marker.size = Vector2(8, 8)
			_house_row.position = Vector2(2, c - band_w - 10)
			_house_row.size = Vector2(c - 4, 8)
			_mortgage_stripe.position = Vector2(0, 0)
			_mortgage_stripe.size = Vector2(c, c)
		3:  # right band
			_band.position = Vector2(c - band_w, 0)
			_band.size = Vector2(band_w, c)
			_name.position = Vector2(2, 2)
			_name.size = Vector2(c - band_w - 4, c - 16)
			_price.position = Vector2(0, c - 14)
			_price.size = Vector2(c - band_w, 12)
			_icon.position = Vector2(0, 0)
			_icon.size = Vector2(c, c)
			_owner_marker.position = Vector2(0, c - 8)
			_owner_marker.size = Vector2(8, 8)
			_house_row.position = Vector2(2, 2)
			_house_row.size = Vector2(c - band_w - 4, 8)
			_mortgage_stripe.position = Vector2(0, 0)
			_mortgage_stripe.size = Vector2(c, c)

## Repaint from a projection tile entry.
func refresh(entry: Dictionary) -> void:
	var typ: String = str(entry.get("type", "property"))
	var is_corner: bool = TL.is_corner(_index, _tile_count)
	var is_property: bool = (typ == "property")

	# band color: group color for properties, type color otherwise
	var band_col: Color = BT.tile_color(entry)
	_band.color = band_col

	# name
	_name.text = str(entry.get("name", ""))
	_name.visible = not is_corner

	# price / amount
	if is_corner:
		_price.text = ""
		_icon.visible = true
		_icon.text = CORNER_ICONS.get(typ, "•")
	elif is_property:
		_price.text = "$%d" % int(entry.get("cost", 0))
		_icon.visible = false
	elif typ == "tax":
		_price.text = "$%d" % int(entry.get("amount", 0))
		_icon.visible = true
		_icon.text = TYPE_ICONS.get(typ, "•")
	else:
		# railroad / utility / chance / community: show cost or icon
		var cost: int = int(entry.get("cost", 0))
		_price.text = ("$%d" % cost) if cost > 0 else ""
		_icon.visible = true
		_icon.text = TYPE_ICONS.get(typ, "•")

	# owner marker
	var ow: int = int(entry.get("owner", -1))
	if ow >= 0:
		_owner_marker.color = _owner_color(ow)
	else:
		_owner_marker.color = Color.TRANSPARENT

	# houses as small green figures along the band edge
	_clear_houses()
	var h: int = int(entry.get("houses", 0))
	if is_property and h > 0:
		var n: int = mini(h, 4)
		for i in n:
			var house := ColorRect.new()
			house.color = Color("2e8b57")
			house.custom_minimum_size = Vector2(6, 6)
			house.size = Vector2(6, 6)
			house.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_house_row.add_child(house)
		if h >= 5:
			var hotel := ColorRect.new()
			hotel.color = Color("b3403d")
			hotel.custom_minimum_size = Vector2(8, 8)
			hotel.size = Vector2(8, 8)
			hotel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_house_row.add_child(hotel)

	# mortgage overlay
	_mortgage_stripe.visible = bool(entry.get("mortgaged", false))

func _clear_houses() -> void:
	for c in _house_row.get_children():
		_house_row.remove_child(c)
		c.queue_free()

func _owner_color(pid: int) -> Color:
	var colors := [Color("e74c3c"), Color("3498db"), Color("2ecc71"),
		Color("f1c40f"), Color("9b59b6"), Color("e67e22")]
	return colors[pid % colors.size()]
