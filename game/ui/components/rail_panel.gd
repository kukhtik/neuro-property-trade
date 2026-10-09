class_name RailPanel
extends PanelContainer
## A side panel that has two states: expanded and rail (spec §5.2).
##
## In the rail state the panel is a ~46px strip carrying a VERTICAL title and a
## chevron; the content is hidden. That is the spec's answer to "a collapsed
## panel must not become an empty strip" — the title and a count stay visible.
##
## The transition animates `custom_minimum_size.x` over `motion.panel`. All
## sizes and colours come from the skin, so a skin swap restyles it.
##
## Usage:
##   var rail := RailPanel.new()
##   rail.setup(skin, "ui.players", false)   # false = left side
##   rail.set_content(my_vbox)               # the thing that hides in the rail
##   rail.set_count("42")                    # optional badge in the rail

signal toggled(collapsed: bool)

const SkinManager := preload("res://visual/skin_manager.gd")
const Chamfer := preload("res://ui/components/chamfer_panel.gd")
const UiTheme := preload("res://ui/theme.gd")

const RAIL_W := 46

var _skin: SkinManager
var _title_key := ""
var _title_text := ""
var _left_side := true
var _collapsed := false
var _content: Control
var _header: Control
var _title_label: Label
var _chevron: Label
var _count_label: Label
var _manual := false      # true once the user toggled it by hand
## The width the panel keeps while EXPANDED. `_apply_state` used to reset
## `custom_minimum_size.x` to 0 on expand, so any width the caller had just set was thrown away
## and the panel grew to whatever its content wanted — the journal rail measured 406px where the
## layout profile said 330, taking 76px off the board. Order of calls decided the layout.
var _expanded_w := 0


func setup(skin: SkinManager, title_key: String, left_side: bool = true) -> void:
	_skin = skin if skin != null else SkinManager.new()
	if _skin.skin_id() == "":
		_skin.load_skin()
	_title_key = title_key
	_left_side = left_side
	mouse_filter = Control.MOUSE_FILTER_PASS
	# A PanelContainer is TRANSPARENT only if someone says so. This one never set a `panel`
	# stylebox, so it fell back to the ENGINE's default theme fill — a grey (#1a1a1a) belonging
	# to no skin — and both side rails painted it behind their content. `PlayersPanel` sets its
	# own box; the rail that wraps it did not, so the surface under the panels was a colour the
	# design never mentions.
	add_theme_stylebox_override("panel",
		UiTheme.box(_skin.color("surface.1"), _skin.color("line"), 1, 0))
	_build()


func _build() -> void:
	# the header is always present: its vertical title is the rail's content
	_header = Chamfer.new()
	(_header as Chamfer).set_skin(_skin)
	(_header as Chamfer).fill_token = "surface.2"
	(_header as Chamfer).border_token = "line"
	(_header as Chamfer).cut = "none"
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	_header.tooltip_text = "Свернуть / развернуть"

	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", _skin.space(1, 4))
	(_header as Chamfer).add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", _skin.size("s", 12))
	_title_label.add_theme_color_override("font_color", _skin.color("muted"))
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", _skin.size("xs", 10))
	_count_label.add_theme_color_override("font_color", _skin.color("muted"))
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_count_label)

	_chevron = Label.new()
	_chevron.text = "‹" if _left_side else "›"
	_chevron.add_theme_font_size_override("font_size", _skin.size("l", 18))
	_chevron.add_theme_color_override("font_color", _skin.color("accent"))
	_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chevron)

	add_child(_header)


## The content that hides when collapsed. Added under the header.
func set_content(c: Control) -> void:
	if _content != null and is_instance_valid(_content):
		_content.queue_free()
	_content = c
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	_apply_state(false)


## The title (set from i18n; call again on a locale change).
func set_title(text: String) -> void:
	_title_text = text
	_title_label.text = text


## A short count/status shown in the rail so it never looks empty.
func set_count(text: String) -> void:
	_count_label.text = text


## The width this panel occupies when EXPANDED. Callers set layout widths through this instead
## of writing `custom_minimum_size.x`, which `_apply_state` overwrites.
func set_expanded_width(w: int) -> void:
	_expanded_w = w
	if not _collapsed:
		custom_minimum_size.x = w


## Collapse/expand programmatically.
func set_collapsed(v: bool, animate: bool = true) -> void:
	if _collapsed == v:
		return
	_collapsed = v
	_apply_state(animate)


func is_collapsed() -> bool:
	return _collapsed


## True when the user collapsed it by hand (so an auto-profile must not undo it).
func is_manual() -> bool:
	return _manual


func _on_header_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_manual = true
		set_collapsed(not _collapsed)
		toggled.emit(_collapsed)


## Apply the state: swap the layout between a rail and a full panel.
func _apply_state(animate: bool) -> void:
	var target_w: int = RAIL_W if _collapsed else _expanded_w
	var t: Tween = null
	if animate:
		t = create_tween()
	if _content != null and is_instance_valid(_content):
		_content.visible = not _collapsed
	# the header becomes a full-height vertical strip when collapsed
	if _collapsed:
		_title_label.add_theme_font_size_override("font_size", _skin.size("s", 12))
		_chevron.text = ("›" if _left_side else "‹")
	else:
		_title_label.add_theme_font_size_override("font_size", _skin.size("s", 12))
		_chevron.text = ("‹" if _left_side else "›")
	if t != null:
		var d: float = _skin.motion("panel", 0.3)
		t.tween_property(self, "custom_minimum_size:x", float(target_w), d)
	else:
		custom_minimum_size.x = target_w
	# in the rail the title reads vertically
	_rotate_title(_collapsed)


## Lay the title vertically in the rail by stacking its characters, which works
## without a rotated-font trick and survives any skin font.
func _rotate_title(vertical: bool) -> void:
	if vertical:
		var chars: Array = []
		for i in _title_text.length():
			chars.append(_title_text[i])
		_title_label.text = "\n".join(chars)
	else:
		_title_label.text = _title_text
