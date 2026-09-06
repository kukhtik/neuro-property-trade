class_name TokenPanel
extends Control
## A single animated player token. Moves to a tile on command, tweening if
## animations enabled. Cosmetic; never blocks the engine.

const TL := preload("res://visual/tile_layout.gd")

var color: Color = Color.WHITE
var player_name: String = ""
var _animations := true
var _cell := 64
var _tile_count := 40

func setup(col: Color, lbl: String, tile_count: int, cell: int, start_idx: int) -> void:
	color = col
	player_name = lbl
	_tile_count = tile_count
	_cell = cell
	custom_minimum_size = Vector2(22, 22)
	size = Vector2(22, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# outline so the token reads against any tile color
	var outline = ColorRect.new()
	outline.color = Color.BLACK
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outline)

	var circ = ColorRect.new()
	circ.color = color
	circ.offset_left = 2; circ.offset_top = 2
	circ.offset_right = -2; circ.offset_bottom = -2
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(circ)

	var name_lbl = Label.new()
	name_lbl.text = player_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_lbl)

	move_to(start_idx, false)

func set_animations(on: bool) -> void:
	_animations = on

## Move the token so its center lands on the tile's pixel center.
func move_to(tile_idx: int, animate: bool) -> void:
	var p := _center_of(tile_idx)
	if animate and _animations:
		var tw = create_tween()
		tw.tween_property(self, "position", p, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		position = p

func _center_of(tile_idx: int) -> Vector2:
	return TL.pixel_pos(tile_idx, _tile_count, _cell) - Vector2(12, 12)
