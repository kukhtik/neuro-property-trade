class_name DiceStage
extends Control
## BG3-style dice animation (P3) — centered overlay showing 2 dice tumbling
## and settling on the rolled result. Honors settings.animations: when
## animations=false the result shows instantly (probe requirement: "dice with
## animations=false shows result instantly"). Purely visual — the engine
## already decided the outcome; this stage only presents it.

signal dice_rolled(d1: int, d2: int, sum: int)

const UiTheme := preload("res://ui/theme.gd")

## P6 CS-5: SVG dice faces (assets/dice/die_1..6.svg). Falls back to a plain
## number Label if the SVG isn't imported yet.
const DIE_SVG := "res://assets/dice/die_%d.svg"

var _dice1: int = 1
var _dice2: int = 1
var _animating := false
var _tween: Tween
var _dice_nodes: Array = []
var _animations_enabled := true
var _settle_time := 1.2
var _sfx = null   # optional Sfx instance for dice sounds (whoosh + bounce clicks)

## Set the procedural Sfx node so the tumble can play whoosh/bounce sounds.
func set_sfx(sfx) -> void:
	_sfx = sfx

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

## Enable/disable animations (from settings.animations).
func set_animations(on: bool) -> void:
	_animations_enabled = on

## Present a decided roll. animations=false → instant result (no tween),
## signal fires on the same frame.
func roll(d1: int, d2: int) -> void:
	_dice1 = clampi(d1, 1, 6)
	_dice2 = clampi(d2, 1, 6)
	visible = true
	# CanvasLayer-free: raise above siblings inside the board scene
	if get_parent() != null:
		get_parent().move_child(self, get_parent().get_child_count() - 1)

	if not _animations_enabled:
		_build_dice()      # final faces immediately
		_finish_instantly()
		return

	_animating = true
	_build_dice()
	if _sfx != null and _sfx.has_method("play_dice_whoosh"):
		_sfx.play_dice_whoosh()
	_animate_roll()

func _finish_instantly() -> void:
	_animating = false
	dice_rolled.emit(_dice1, _dice2, _dice1 + _dice2)
	_auto_hide()

func _auto_hide() -> void:
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(_hide)

func _build_dice() -> void:
	for n in _dice_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_dice_nodes.clear()

	var vp := get_viewport().get_visible_rect().size
	# C6: center on the BOARD (the parent control's rect), not the viewport — the
	# dice must land in the board's center, not the screen center (which is
	# offset by the left players panel + right journal). Use the parent's size
	# (the board scene) so it works even when this control's own size is 0 in
	# headless (HBox hasn't laid it out).
	var center: Vector2
	var host := get_parent()
	if host != null and host is Control and (host as Control).size.x > 0 and (host as Control).size.y > 0:
		center = (host as Control).size * 0.5
	elif size.x > 0 and size.y > 0:
		center = size * 0.5
	else:
		center = vp * 0.5
	var dice_size: float = clampf(minf(vp.x, vp.y) * 0.15, 64.0, 140.0)

	for i in 2:
		var dice := PanelContainer.new()
		dice.name = "Dice%d" % i
		dice.custom_minimum_size = Vector2(dice_size, dice_size)
		dice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dice.add_theme_stylebox_override("panel", UiTheme.box(
			UiTheme.skin().color("dice_bg"), UiTheme.COL().border_accent, 2, 12))
		dice.pivot_offset = Vector2(dice_size, dice_size) * 0.5

		var face := _make_face(i, dice_size)
		dice.add_child(face)

		dice.position = center - Vector2(dice_size * 1.15, dice_size * 0.5) \
			+ Vector2(i * dice_size * 1.3, 0)
		add_child(dice)
		_dice_nodes.append(dice)

## Build a die face: an SVG TextureRect when the asset is imported, else a
## plain number Label (CS-5). The face node is named "Face" so the tumble
## code can update it.
func _make_face(i: int, dice_size: float) -> Control:
	var face_val: int = _dice1 if i == 0 else _dice2
	var svg_path: String = DIE_SVG % face_val
	if ResourceLoader.exists(svg_path):
		var tex: Texture2D = load(svg_path)
		if tex != null:
			var tr := TextureRect.new()
			tr.name = "Face"
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tr
	var label := Label.new()
	label.name = "Face"
	label.text = str(face_val)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(dice_size * 0.5))
	label.add_theme_color_override("font_color", UiTheme.skin().color("dice_ink"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _animate_roll() -> void:
	# Tumble: decreasing position jitter + rotation, face flickers, then settle.
	var steps := 8
	var step_time := _settle_time / steps

	_tween = create_tween()
	_tween.set_parallel(true)

	for i in 2:
		var dice = _dice_nodes[i]
		var label = dice.get_node("Face")
		var start_pos: Vector2 = dice.position

		for s in steps:
			var t := float(s + 1) / float(steps)

			# Position jitter (decreases over time) + a bounce click sound
			var jitter_range: float = 40.0 * (1.0 - t)
			if _sfx != null and _sfx.has_method("play_dice_bounce"):
				_tween.tween_callback(_sfx.play_dice_bounce)
			var target_pos: Vector2 = start_pos + Vector2(
				randf_range(-jitter_range, jitter_range),
				randf_range(-jitter_range, jitter_range))
			_tween.tween_property(dice, "position", target_pos, step_time)

			# Rotation tumble (dampens over time)
			var target_rot: float = randf_range(-PI * 2.0, PI * 2.0) * (1.0 - t)
			_tween.tween_property(dice, "rotation", target_rot, step_time)

			# Face flicker during tumble
			if s < steps - 1:
				var rand_face := randi_range(1, 6)
				_tween.tween_callback(_set_face.bind(label, rand_face))
				_tween.tween_interval(step_time * 0.5)

	# Final settle: correct faces, zero rotation
	_tween.tween_callback(_settle_faces)
	_tween.finished.connect(_on_tween_finished)

func _set_face(node: Control, face: int) -> void:
	if not is_instance_valid(node):
		return
	if node is Label:
		(node as Label).text = str(face)
	elif node is TextureRect:
		var svg_path: String = DIE_SVG % face
		if ResourceLoader.exists(svg_path):
			(node as TextureRect).texture = load(svg_path)

func _settle_faces() -> void:
	for i in 2:
		var dice = _dice_nodes[i]
		var face: Control = dice.get_node("Face")
		_set_face(face, _dice1 if i == 0 else _dice2)
		dice.rotation = 0.0

func _on_tween_finished() -> void:
	_animating = false
	dice_rolled.emit(_dice1, _dice2, _dice1 + _dice2)
	_auto_hide()

func is_animating() -> bool:
	return _animating

func _hide() -> void:
	visible = false
	for n in _dice_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_dice_nodes.clear()