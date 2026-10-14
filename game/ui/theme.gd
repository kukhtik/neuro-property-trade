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
static func box(bg: Color, border_col: Color = Color.TRANSPARENT, w: int = 1, radius: int = -1, pad_x: float = 0.0) -> StyleBoxFlat:
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
	if pad_x > 0.0:
		# THE way a Button gets side padding: content margins on its styleboxes. The swap-era
		# code set `padding_left/right` theme CONSTANTS, which Button never reads - the control
		# row silently lost its 20px and every caption sat one pixel from its border (SG-11).
		b.content_margin_left = pad_x
		b.content_margin_right = pad_x
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
##
## THIS IS THE *VALUE* ROLE: one line, sized to its own content. It neither wraps nor
## stretches. A value inside an HBox that also stretches takes the free width and pushes
## its neighbours out of the row — money, badges, counters and hotkeys are values and must
## not do that. Prose goes through `label_wrap` below.
static func label(text: String, size: int = -1, color: Color = Color.TRANSPARENT) -> Label:
	var s := skin()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", s.size("m", 14) if size < 0 else size)
	l.add_theme_color_override("font_color", s.color("text") if color.a <= 0.0 else color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


## THE *PARAGRAPH* ROLE: prose that wraps by words and takes the width of its parent
## column — rules, a tile description, a hint, invitation text.
##
## WHY THERE ARE TWO: one factory used to force WORD_SMART + EXPAND_FILL on all 86 call
## sites. That is right for a rail's prose and wrong for every value in a row: layout got
## 2.6-3.6x more expensive (measured; docs/specs/ui-defect-report.md) and the values pushed
## their neighbours around. The wrap belongs to the text that IS a paragraph, not to the
## widget that happens to be a label — the two roles are different components.
static func label_wrap(text: String, size: int = -1, color: Color = Color.TRANSPARENT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A muted (secondary) label — the VALUE role (see label()).
static func label_muted(text: String, size: int = -1) -> Label:
	return label(text, size, skin().color("muted"))


## A money label (monospace-ish colour token) — the VALUE role (see label()).
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
	b.add_theme_color_override("font_color", s.color("text"))
	var r: int = int(s.shape("radius", 0.0))
	var w: int = int(s.shape("line", 1.0))
	b.add_theme_stylebox_override("normal", box(s.color("surface.2"), s.color("line"), w, r, 20.0))
	b.add_theme_stylebox_override("hover", box(s.color("surface.1"), s.color("accent"), w, r, 20.0))
	b.add_theme_stylebox_override("pressed", box(s.color("surface.1"), s.color("accent"), int(s.shape("line_active", 2.0)), r, 20.0))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 20.0))
	return b


## Accent (primary) button — filled with the accent, text in on_accent.
static func button_accent(text: String, tooltip: String = "") -> Button:
	var s := skin()
	var b := button(text, tooltip)
	var r: int = int(s.shape("radius", 0.0))
	b.add_theme_stylebox_override("normal", box(s.color("accent"), s.color("accent"), 1, r, 26.0))
	b.add_theme_stylebox_override("hover", box(s.color("accent2", s.color("accent")), s.color("accent"), int(s.shape("line_active", 2.0)), r, 26.0))
	b.add_theme_stylebox_override("pressed", box(s.color("accent"), s.color("accent"), int(s.shape("line_active", 2.0)), r, 26.0))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 26.0))
	b.add_theme_color_override("font_color", s.color("on_accent"))
	b.custom_minimum_size.y = 50   # the mockup's primary: `#act button.pri`
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
