extends Control
## One board tile drawn the way the prototype draws it (`.tile`): a padded face, a group
## band on the INNER edge, the name, the price, the house marks on the band, the owner
## badge and the state frame (owned / active / selected / target / dimmed / mortgaged).
##
## v3 rebuild — replaces the archived tile. Everything is built from skin tokens; the
## board scene rebuilds tiles when the cell size changes, so fonts stay right.

signal pressed(index: int)

const UiTheme := preload("res://ui/theme.gd")
const SkinManager := preload("res://visual/skin_manager.gd")
const MoneyFmt := preload("res://ui/core/money.gd")
const I18n := preload("res://i18n/i18n.gd")

var index := 0
var _skin: SkinManager
var _cell := 64.0
var _side := "b"           # which ring edge: "b" bottom, "l" left, "t" top, "r" right
var _type := "property"
var _group := ""
var _corner := false

var _face: Panel
var _band: ColorRect
var _name: Label
var _price: Label
var _houses: HBoxContainer
var _badge: Label
var _state: Panel
var _mortgaged: Label


func setup(skin: SkinManager, idx: int, data: Dictionary, cell: float, side: String) -> void:
	_skin = skin
	index = idx
	_cell = cell
	_side = side
	_type = str(data.get("type", "property"))
	_group = str(data.get("group", ""))
	_corner = side == "corner"
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _face != null:
		return   # reuse: only re-layout below
	_build(data)
	_layout_children()


func _build(data: Dictionary) -> void:
	_face = Panel.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.COL().panel_dark if _corner else UiTheme.COL().panel, UiTheme.COL().border, 1, 0))
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.color = _band_colour()
	add_child(_band)

	_name = UiTheme.label(str(data.get("name", "")), 10, UiTheme.COL().text)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	var cost: int = int(data.get("cost", 0))
	_price = UiTheme.label(MoneyFmt.make("$").amount(cost) if cost > 0 else "", 8, UiTheme.COL().money)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_price)

	_houses = UiTheme.hbox(1)
	_houses.visible = false
	_houses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_houses)

	_badge = UiTheme.label("", 9, UiTheme.COL().text)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	_mortgaged = UiTheme.label("M", 9, UiTheme.COL().danger)
	_mortgaged.visible = false
	_mortgaged.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mortgaged)

	_state = Panel.new()
	_state.set_anchors_preset(Control.PRESET_FULL_RECT)
	_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state.visible = false
	add_child(_state)


func _band_colour() -> Color:
	if _type == "property" and _group != "":
		return UiTheme.skin().group_color(_group)
	match _type:
		"go":
			return UiTheme.COL().success
		"chance", "community":
			return UiTheme.COL().accent2
		"tax", "go_to_jail":
			return UiTheme.COL().danger
		"railroad", "utility":
			return UiTheme.COL().text_dim
	return UiTheme.COL().border


func _layout_children() -> void:
	var c := _cell
	var pad := 2.0
	var inner := Rect2(pad, pad, c - pad * 2.0, c - pad * 2.0)
	# band thickness: full strip along the INNER edge
	var bt: float = maxf(4.0, minf(c * 0.16, 13.0))
	if _side == "corner":
		bt = 0.0
	# face occupies the padded rect
	_face.position = inner.position
	_face.size = inner.size
	var band := Rect2()
	match _side:
		"b":   # bottom row → band on top (facing centre)
			band = Rect2(inner.position, Vector2(inner.size.x, bt))
		"t":
			band = Rect2(inner.position + Vector2(0, inner.size.y - bt), Vector2(inner.size.x, bt))
		"l":
			band = Rect2(inner.position + Vector2(inner.size.x - maxf(4.0, c * 0.10), 0),
				Vector2(maxf(4.0, c * 0.10), inner.size.y))
		"r":
			band = Rect2(inner.position, Vector2(maxf(4.0, c * 0.10), inner.size.y))
	_band.position = band.position
	_band.size = band.size
	# text block: the inner rect minus the band
	var text_rect := inner
	if _side == "b":
		text_rect.position.y += bt
		text_rect.size.y -= bt
	elif _side == "t":
		text_rect.size.y -= bt
	elif _side == "l":
		text_rect.size.x -= band.size.x
	else:
		text_rect.position.x += band.size.x
		text_rect.size.x -= band.size.x
	var fname: int = clampi(int(c * 0.145), 8, 13)
	var fprice: int = clampi(int(c * 0.115), 7, 12)
	_name.add_theme_font_size_override("font_size", fname)
	_price.add_theme_font_size_override("font_size", fprice)
	var half := text_rect.size.y * 0.5
	_name.position = text_rect.position
	_name.size = Vector2(text_rect.size.x, half)
	_price.position = text_rect.position + Vector2(0, half)
	_price.size = Vector2(text_rect.size.x, text_rect.size.y - half)
	# houses ride the band centre
	var house_w: float = minf(band.size.x - 4.0, 5.0 * 6.0 + 5.0)
	_houses.position = band.position + Vector2((band.size.x - house_w) * 0.5, maxf(0.0, (band.size.y - 8.0) * 0.5))
	# owner badge: bottom-left of the face
	var bs: float = maxf(10.0, c * 0.17)
	_badge.position = inner.position + Vector2(1, inner.size.y - bs - 1)
	_badge.size = Vector2(bs, bs)
	_mortgaged.position = inner.position + Vector2(1, 1)


## Paint the dynamic state: ownership, houses, mortgage and the highlight frame.
func apply(entry: Dictionary) -> void:
	var owner: int = int(entry.get("owner", -1))
	var owner_col: Color = entry.get("owner_color", UiTheme.COL().accent)
	if owner >= 0:
		_badge.visible = true
		var nm := str(entry.get("owner_name", ""))
		_badge.text = nm.substr(0, 1).to_upper() if nm != "" else str(owner)
		_badge.add_theme_stylebox_override("normal", UiTheme.box(owner_col, UiTheme.COL().border, 1, 0))
		_badge.add_theme_color_override("font_color", Color.BLACK if owner_col.get_luminance() > 0.5 else Color.WHITE)
	else:
		_badge.visible = false
	var houses: int = int(entry.get("houses", 0))
	for c in _houses.get_children():
		_houses.remove_child(c)
		c.queue_free()
	_houses.visible = houses > 0
	if houses > 0:
		var n: int = 1 if houses >= 5 else mini(houses, 4)
		for i in n:
			var sq := ColorRect.new()
			sq.color = UiTheme.COL().success
			sq.custom_minimum_size = Vector2(8, 6) if houses >= 5 else Vector2(5, 5)
			_houses.add_child(sq)
	var mortgaged: bool = bool(entry.get("mortgaged", false))
	_mortgaged.visible = mortgaged
	_face.modulate = Color(1, 1, 1, 0.45) if mortgaged else Color.WHITE
	# the state frame: target tint · active ring (glow) · selected marker · owner border
	var ac: Color = UiTheme.COL().accent
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	var show := false
	if bool(entry.get("target", false)):
		sb.bg_color = Color(ac.r, ac.g, ac.b, 0.12)
		sb.draw_center = true
		show = true
	if bool(entry.get("active", false)):
		sb.set_border_width_all(2)
		sb.border_color = ac
		sb.shadow_color = UiTheme.COL().accent
		sb.shadow_size = 8
		show = true
	elif bool(entry.get("selected", false)):
		sb.set_border_width_all(1)
		sb.border_color = UiTheme.COL().text
		sb.expand_margin_left = -3.0
		sb.expand_margin_right = -3.0
		sb.expand_margin_top = -3.0
		sb.expand_margin_bottom = -3.0
		show = true
	elif owner >= 0:
		sb.set_border_width_all(2)
		sb.border_color = owner_col
		show = true
	_state.add_theme_stylebox_override("panel", sb)
	_state.visible = show
	modulate = Color(1, 1, 1, 0.5) if bool(entry.get("dimmed", false)) else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(index)
