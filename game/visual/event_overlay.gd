class_name EventOverlay
extends PanelContainer
## Stream overlay (spec event_overlay). Shows recent event lines rendered from
## spectator-safe data (EventMessages.describe reads only public fields). No
## per-seat private info ever reaches this.

const EventMessages := preload("res://visual/event_messages.gd")

var _list: Label
var _max_lines := 6

func _init() -> void:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.05, 0.08, 0.12, 0.72)
	b.corner_radius_top_left = 8
	b.corner_radius_top_right = 8
	b.corner_radius_bottom_left = 8
	b.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", b)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -440
	offset_top = -210
	offset_right = -8
	offset_bottom = -8
	custom_minimum_size = Vector2(432, 202)

	var head := Label.new()
	head.text = "◆ EVENT LOG ◆"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color("9fd0ff"))
	add_child(head)

	_list = Label.new()
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_theme_font_size_override("font_size", 13)
	_list.add_theme_color_override("font_color", Color("f2f6fa"))
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list)
	visible = true

func append(entry: Dictionary) -> void:
	var line := EventMessages.describe(entry)
	var parts := _list.text.split("\n")
	parts.append(line)
	if parts.size() > _max_lines + 1:   # +1 for header
		parts = parts.slice(parts.size() - _max_lines)
	_list.text = "\n".join(parts)

## Replace with a full spectator markdown render (for_spectator output).
func set_markdown(md: String) -> void:
	if md != "":
		_list.text = md
