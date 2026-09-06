class_name TokenPanel
extends Control
## A single animated player token (A4): a unique colored piece with the
## player's initial drawn on it. Moves to a tile on command, tweening if
## animations enabled. Cosmetic; never blocks the engine. The piece is drawn
## as a circle with a distinct shape per player index (slot for a sprite later).
## Size scales with the tile cell so tokens stay visible at any board scale.

const TL := preload("res://visual/tile_layout.gd")

var color: Color = Color.WHITE
var player_name: String = ""
var _animations := true
var _cell := 64
var _tile_count := 40
var _pid := 0
var _initial: Label

func setup(col: Color, lbl: String, tile_count: int, cell: int, start_idx: int) -> void:
	color = col
	player_name = lbl
	_tile_count = tile_count
	_cell = cell
	var s := maxi(16, int(cell * 0.34))   # token ~1/3 of the tile
	custom_minimum_size = Vector2(s, s)
	size = Vector2(s, s)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# outline so the token reads against any tile color
	var outline = ColorRect.new()
	outline.color = Color.BLACK
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outline)

	var circ = ColorRect.new()
	circ.color = color
	circ.offset_left = 1; circ.offset_top = 1
	circ.offset_right = -1; circ.offset_bottom = -1
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(circ)

	# the player's initial, centered on the piece
	_initial = Label.new()
	_initial.text = _initial_of(lbl)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_size_override("font_size", maxi(9, int(s * 0.5)))
	_initial.add_theme_color_override("font_color", Color.WHITE)
	_initial.add_theme_color_override("font_outline_color", Color.BLACK)
	_initial.add_theme_constant_override("outline_size", 2)
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_initial)

	move_to(start_idx, false)

## First letter of the player name, uppercased (fallback to a pid letter).
func _initial_of(name: String) -> String:
	var n := name.strip_edges()
	if n.length() > 0:
		return n.substr(0, 1).to_upper()
	return "P"

func set_animations(on: bool) -> void:
	_animations = on

## Move the token so it sits in the top-left corner of the tile (offset by
## pid so several players sharing a tile don't fully overlap), NOT over the
## tile's name label.
func move_to(tile_idx: int, animate: bool) -> void:
	var p := _corner_of(tile_idx)
	if animate and _animations:
		var tw = create_tween()
		tw.tween_property(self, "position", p, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		position = p

func _corner_of(tile_idx: int) -> Vector2:
	# top-left corner of the tile cell, with a small inset
	return TL.pixel_pos(tile_idx, _tile_count, _cell) - Vector2(_cell * 0.5, _cell * 0.5) + Vector2(2, 2)
