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
const I18n := preload("res://i18n/i18n.gd")

const RAIL_W := 48

var _skin: SkinManager
var _title_key := ""
var _title_text := ""
var _left_side := true
var _collapsed := false
var _content: Control
var _header: Control
var _title_label: Label
## Holds the rotated title in the rail. The label keeps its natural size (a Label cannot be narrowed
## below its text) and turns inside this holder, which IS the rail's rectangle - so the layout, and
## SG-02, measure the rail rather than a word wider than it. See `_apply_rail_title`.
var _title_holder: Control
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
	# THE TOOLTIP GOES ON THE RAIL AS WELL AS THE HEADER, and it is LOCALIZED.
	#
	# It used to be a hard-coded Russian string on the header only, so a reader of the rail
	# (the thing that is actually clickable when collapsed) found `tooltip=''` in English - and the
	# collapsed state showed nothing but a chevron beside an unlabelled vertical title. The owner's
	# report: "не просто кнопку оставлять, а кнопку с подписью что это". A control nobody can name is
	# a control nobody presses.
	_header.tooltip_text = _collapse_tip()
	tooltip_text = _collapse_tip()

	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", _skin.space(1, 4))
	(_header as Chamfer).add_child(box)

	# THE TITLE LIVES IN A FIXED HOLDER, ROTATED.
	#
	# Two Godot facts forced this shape, both measured:
	#   1. A Control inside a Container has its rotation reset to 0 on the next frame;
	#   2. a Label cannot be given a box narrower than its text - assigning 18x98 reads back 98x98.
	# So the label keeps its natural size and is turned inside a holder that IS the rail's rectangle.
	# The holder is what the layout (and SG-02) measures, so a 65px word in a 48px rail is reported
	# against the rail, which is also what the eye sees.
	_title_holder = Control.new()
	_title_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_holder.clip_contents = true
	(_header as Chamfer).add_child(_title_holder)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", _skin.size("s", 12))
	_title_label.add_theme_color_override("font_color", _skin.color("muted"))
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# no ellipsis: the rail lays the word out itself, and trimming would eat the vertical text
	_title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_holder.add_child(_title_label)

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


## The tooltip for the collapse control, in the ACTIVE locale, and it names the panel it belongs to
## so a collapsed strip still says what expanding it will bring back.
func _collapse_tip() -> String:
	var what := _title_text if _title_text != "" else _title_key
	var verb := "rail.expand" if _collapsed else "rail.collapse"
	return "%s: %s" % [I18n.t(verb), what]


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
	# the tooltip says what THIS state does, and names the panel, so a collapsed rail is still a
	# labelled control rather than a bare chevron
	var tip := _collapse_tip()
	if _header != null:
		_header.tooltip_text = tip
	tooltip_text = tip


## Lay the title for the rail, or restore it for the expanded panel.
func _rotate_title(vertical: bool) -> void:
	if vertical:
		# the vertical title lives under the holder (a Container would reset its rotation)
		_title_label.reparent(_title_holder, false)
		_apply_rail_title()
	else:
		_title_label.rotation = 0.0
		_title_holder.visible = false
		if _title_label.get_parent() != _header:
			_title_label.reparent(_header, false)
		_title_label.text = _title_text


## Place the rotated title inside the rail. Safe to call repeatedly: it reads the CURRENT header
## size, so a resize, a late layout or a locale change is corrected rather than left wrong.
func _apply_rail_title() -> void:
	if _title_label == null or _title_holder == null or not _collapsed or _header == null:
		return
	var hs: Vector2 = _header.size
	if hs.x <= 1.0 or hs.y <= 1.0:
		return                      # not laid out yet; a visibility change or notification comes back
	_title_holder.visible = true
	# THE HOLDER IS CLAMPED TO WHAT IS ON SCREEN. The header's size can be stale (a rail built while
	# hidden, or measured before a resize), and sizing the holder to it put 818px of holder in a 720px
	# window - SG-02: `@Control@108 rect [9,73 46x818]` in a 1280x720 viewport. Clamp to the visible
	# rect so the measured box can never be larger than the window it sits in.
	var vis: Vector2 = hs
	var vp := get_viewport_rect()
	if vp.size.x > 1.0 and vp.size.y > 1.0:
		var gr: Rect2 = _header.get_global_rect()
		vis.y = minf(hs.y, maxf(1.0, vp.size.y - gr.position.y))
		vis.x = minf(hs.x, maxf(1.0, vp.size.x - gr.position.x))
	_title_holder.size = vis
	_title_holder.position = Vector2.ZERO
	_title_holder.pivot_offset = Vector2.ZERO
	# measure the word from the FONT: a rotated Label reports its ROTATED size, so `reset_size`
	# round-trips are unreliable (measured 18x98 assigned, 98x98 read back)
	var f: Font = _title_label.get_theme_font("font")
	var fs: int = _title_label.get_theme_font_size("font_size")
	var w: float = 0.0
	var h: float = 0.0
	if f != null:
		var m: Vector2 = f.get_string_size(_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		w = ceilf(m.x)
		h = ceilf(m.y)
	if w <= 0.0 or h <= 0.0:
		return
	_title_label.size = Vector2(w, h)
	_title_label.pivot_offset = Vector2(w, h) * 0.5
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# centre the label's own box on the rail; the rotation turns it about the same centre, so the
	# (h x w) footprint stays centred in the strip
	_title_label.position = hs * 0.5 - Vector2(w, h) * 0.5
	_title_label.rotation = deg_to_rad(-90.0 if _left_side else 90.0)


## A rail is BUILT HIDDEN and shown later, so its header has no real size until then - and a rotation
## placed while hidden is placed against a zero rect. Re-place the title when that changes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_rail_title()
