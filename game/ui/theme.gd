class_name UiTheme
extends RefCounted
## Central UI theme + widget factory for the playable game shell.
## Single source of palette + stylebox construction so every panel/button reads
## from here (no magic colors in scenes). This is the seam where flat shapes
## later get swapped for art: replace the shape construction below, keep the
## public helpers. UI logic never depends on concrete widget internals.

const COL := {
	"bg":            Color("16191f"),   # deep slate backdrop
	"panel":         Color("1e242e"),   # card/panel fill
	"panel_dark":    Color("171c24"),   # recessed fill
	"border":        Color("39404d"),   # default border
	"border_accent": Color("4fb3d9"),   # accent border (selection/active)
	"text":          Color("e8edf3"),   # primary text
	"text_dim":      Color("8b95a5"),   # secondary text
	"accent":        Color("4fb3d9"),   # primary accent (buttons/active)
	"accent_hover":  Color("5fc4ea"),
	"accent_press":  Color("3a95bd"),
	"danger":        Color("d9534f"),
	"success":       Color("5cb85c"),
	"gold":          Color("ffd34d"),
	"jail":          Color("9a86c9"),
}

## Build a flat StyleBox with the panel fill + border. radius in px.
static func box(bg: Color, border_col: Color = COL.border, w: int = 1, radius: int = 6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border_col
	b.set_border_width_all(w)
	b.corner_radius_top_left = radius
	b.corner_radius_top_right = radius
	b.corner_radius_bottom_left = radius
	b.corner_radius_bottom_right = radius
	return b

## PanelContainer with the standard panel fill + border.
static func panel(custom_min: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(COL.panel, COL.border, 1, 8))
	if custom_min != Vector2.ZERO:
		p.custom_minimum_size = custom_min
	return p

## Label with theme font size + color.
static func label(text: String, size: int = 14, color: Color = COL.text) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Standard styled Button. `tooltip` (optional) shows a styled description on
## hover — every interactive button should pass one (A2 requirement).
static func button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if tooltip != "":
		b.tooltip_text = tooltip
		_style_tooltip(b)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", COL.text)
	# normal / hover / pressed styleboxes
	b.add_theme_stylebox_override("normal", box(COL.panel_dark, COL.border, 1, 6))
	b.add_theme_stylebox_override("hover", box(COL.accent, COL.border_accent, 1, 6))
	b.add_theme_stylebox_override("pressed", box(COL.accent_press, COL.border_accent, 1, 6))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	return b

## Accent (primary) button — brighter + accent border. Optional tooltip.
static func button_accent(text: String, tooltip: String = "") -> Button:
	var b := button(text, tooltip)
	b.add_theme_stylebox_override("normal", box(COL.accent, COL.border_accent, 1, 6))
	b.add_theme_stylebox_override("hover", box(COL.accent_hover, COL.border_accent, 2, 6))
	b.add_theme_stylebox_override("pressed", box(COL.accent_press, COL.border_accent, 2, 6))
	b.add_theme_color_override("font_color", Color("0c1218"))
	return b

## Apply a dark, bordered tooltip style to a control that has a tooltip_text.
static func _style_tooltip(c: Control) -> void:
	c.add_theme_stylebox_override("TooltipPanel", box(Color("0d1117"), COL.border_accent, 1, 4))
	c.add_theme_color_override("TooltipLabel/font_color", COL.text)
	c.add_theme_font_size_override("TooltipLabel/font_size", 12)

## VBox with consistent margin + separation.
static func vbox(sep: int = 8, margin: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v
