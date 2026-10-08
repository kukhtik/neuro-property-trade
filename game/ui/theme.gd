class_name UiTheme
extends RefCounted
## Widget factory for the game shell — now a THIN ADAPTER over SkinManager.
##
## Historically this held its own hardcoded palette (COL) and built styleboxes
## from it, which made it a second source of visual truth alongside the skin.
## It now resolves every colour, size and shape through SkinManager, so the 12
## panels that call UiTheme.* automatically follow the active skin without a
## single edit at the call sites.
##
## `COL` is kept as a compatibility shim: it resolves lazily from the skin.
## New code should prefer SkinManager directly (token/slot/metric) or the theme
## type variations (`ButtonPrimary`, `PanelHeader`, ...).

const SkinManager := preload("res://visual/skin_manager.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")

## The active skin. Set once at boot (and on a skin change) via use_skin().
static var _skin: SkinManager = null


## Point the factory at a skin. Every later call reads from it.
static func use_skin(skin: SkinManager) -> void:
	_skin = skin


## The active skin, loading the default on first use.
static func skin() -> SkinManager:
	if _skin == null:
		_skin = SkinManager.new()
		_skin.load_skin()
	return _skin


## Compatibility view of the palette, resolved from the skin. Kept so panels
## that read `UiTheme.COL().x` keep working; prefer skin().color("x").
## NOTE: this is a function now, not a const — call sites must use COL() .
## The palette the UI code reads.
##
## This map is a TRANSLATION, not the source: the skin owns the colours and this gives them
## the names components use. It used to expose only 14 of the skin's 27 tokens, so anything
## reaching for `ink`, `on_accent`, `accent2`, `surface2/3` or an `ev.*` colour hit a missing
## key and THREW — 1630 errors and a segfault in one run, from one absent name.
static func COL() -> Dictionary:
	var s := skin()
	var ac: Color = s.color("accent")
	var hi: Color = s.color("accent2", ac)
	return {
		"bg": s.color("bg"),
		"panel": s.color("surface.1"),
		"panel_dark": s.color("surface.2"),
		"surface1": s.color("surface.1"),
		"surface2": s.color("surface.2"),
		"surface3": s.color("surface.3"),
		"border": s.color("line"),
		"border_accent": ac,
		"text": s.color("text"),
		"text_dim": s.color("muted"),
		"muted": s.color("muted"),
		"accent": ac,
		"accent2": hi,
		"accent_hover": hi,
		"accent_press": ac,
		"on_accent": s.color("on_accent", Color(0, 0, 0)),
		"on_panel": s.color("on_panel", s.color("text")),
		"ink": s.color("ink", Color(0, 0, 0)),
		"danger": s.color("danger"),
		"warn": s.color("warn", Color("#e08a3c")),
		"success": s.color("money", Color("6fbf73")),
		"money": s.color("money"),
		"gold": s.color("money"),
		"jail": s.color("warn", Color("9a86c9")),
		"board_bg2": s.color("board.bg2", s.color("bg")),
		"board_bg3": s.color("board.bg3", s.color("surface.2")),
	}


## Build a flat StyleBox with a fill + border. Radius comes from the skin so a
## skin with rounded corners actually round.
static func box(bg: Color, border_col: Color = Color.TRANSPARENT, w: int = 1, radius: int = -1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	if border_col.a <= 0.0:
		border_col = skin().color("line")
	b.border_color = border_col
	b.set_border_width_all(w)
	var r: int = int(skin().shape("radius", 0.0)) if radius < 0 else radius
	b.corner_radius_top_left = r
	b.corner_radius_top_right = r
	b.corner_radius_bottom_left = r
	b.corner_radius_bottom_right = r
	return b


## PanelContainer with the standard panel fill + border.
static func panel(custom_min: Vector2 = Vector2.ZERO) -> PanelContainer:
	var s := skin()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(s.color("surface.1"), s.color("line"), 1))
	if custom_min != Vector2.ZERO:
		p.custom_minimum_size = custom_min
	return p


## A chamfered panel (the project's signature cut corner) instead of a radius.
static func chamfer_panel(cut: String = "tr") -> Chamfer:
	var c := Chamfer.new()
	c.set_skin(skin())
	c.cut = cut
	return c


## Label with a skin font size + colour. `size` is a px override; -1 means the
## skin's default body size.
static func label(text: String, size: int = -1, color: Color = Color.TRANSPARENT) -> Label:
	var s := skin()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", s.size("m", 14) if size < 0 else size)
	l.add_theme_color_override("font_color", s.color("text") if color.a <= 0.0 else color)
	return l


## A muted (secondary) label.
static func label_muted(text: String, size: int = -1) -> Label:
	return label(text, size, skin().color("muted"))


## A money label (monospace-ish colour token).
static func label_money(text: String, size: int = -1) -> Label:
	return label(text, size, skin().color("money"))


## Standard styled Button. `tooltip` (optional) shows a styled description on
## hover — every interactive button should pass one.
static func button(text: String, tooltip: String = "") -> Button:
	var s := skin()
	var b := Button.new()
	b.text = text
	if tooltip != "":
		b.tooltip_text = tooltip
		_style_tooltip(b)
	b.add_theme_font_size_override("font_size", s.size("m", 14))
	# the mockup's control bar: `#act button` is 46px tall with 20px of side padding, and the
	# primary is 50px with 26px. These are the numbers that make the bar feel like a control
	# panel rather than a stack of small form buttons.
	b.custom_minimum_size.y = 46
	b.add_theme_constant_override("padding_left", 20)
	b.add_theme_constant_override("padding_right", 20)
	b.add_theme_color_override("font_color", s.color("text"))
	var r: int = int(s.shape("radius", 0.0))
	var w: int = int(s.shape("line", 1.0))
	b.add_theme_stylebox_override("normal", box(s.color("surface.2"), s.color("line"), w, r))
	b.add_theme_stylebox_override("hover", box(s.color("surface.1"), s.color("accent"), w, r))
	b.add_theme_stylebox_override("pressed", box(s.color("surface.1"), s.color("accent"), int(s.shape("line_active", 2.0)), r))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	return b


## Accent (primary) button — filled with the accent, text in on_accent.
static func button_accent(text: String, tooltip: String = "") -> Button:
	var s := skin()
	var b := button(text, tooltip)
	var r: int = int(s.shape("radius", 0.0))
	b.add_theme_stylebox_override("normal", box(s.color("accent"), s.color("accent"), 1, r))
	b.add_theme_stylebox_override("hover", box(s.color("accent2", s.color("accent")), s.color("accent"), int(s.shape("line_active", 2.0)), r))
	b.add_theme_stylebox_override("pressed", box(s.color("accent"), s.color("accent"), int(s.shape("line_active", 2.0)), r))
	b.add_theme_color_override("font_color", s.color("on_accent"))
	b.custom_minimum_size.y = 50   # the mockup's primary: `#act button.pri`
	b.add_theme_constant_override("padding_left", 26)
	b.add_theme_constant_override("padding_right", 26)
	return b


## A primary button with the skin's cut corner.
static func button_primary_chamfer(text: String, tooltip: String = "") -> Chamfer:
	var c := chamfer_panel("tr")
	c.fill_token = "accent"
	c.border_token = "accent"
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", skin().color("on_accent"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	if tooltip != "":
		c.tooltip_text = tooltip
	return c


## Apply a bordered tooltip style to a control that has a tooltip_text.
static func _style_tooltip(c: Control) -> void:
	var s := skin()
	c.add_theme_stylebox_override("TooltipPanel", box(s.color("surface.2"), s.color("accent"), 1))
	c.add_theme_color_override("TooltipLabel/font_color", s.color("text"))
	c.add_theme_font_size_override("TooltipLabel/font_size", s.size("s", 12))


## VBox with consistent separation. The margin argument is kept for call-site
## compatibility; spacing comes from the skin scale.
static func vbox(sep: int = -1, _margin: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", skin().space(2, 8) if sep < 0 else sep)
	return v


## HBox sibling of vbox().
static func hbox(sep: int = -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", skin().space(2, 8) if sep < 0 else sep)
	return h
