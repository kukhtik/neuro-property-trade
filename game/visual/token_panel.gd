class_name TokenPanel
extends Control
## A single animated player token (spec §4.3). The piece is the player's SVG
## sprite (assets/tokens/<token_id>.svg) drawn WITHOUT recoloring, sitting on a
## colored halo circle (PlayerIdentity color) so the player's color reads while
## the art stays clean. In compact mode an initial is drawn over the halo.
##
## Parking: pieces sharing a tile fan out along a 60° arc around the tile
## center (radius 0.35×cell), z-order by pid. The active player bobs gently.
## Movement: step-by-step walk along the ring (70ms/tile, ease-in-out); passing
## GO flashes gold. All animation is gated by settings.animations=false →
## instant positions. Cosmetic; never blocks the engine.

const TL := preload("res://visual/tile_layout.gd")
const PI := preload("res://core/player_identity.gd")

const STEP_MS := 0.07          # seconds per tile during a walk
const FAN_ARC_DEG := 120.0     # fan spread around the tile center
const FAN_RADIUS := 0.45       # fan radius as a fraction of the cell
const PIECE_FRAC := 0.38       # piece size as a fraction of the cell
const MIN_PIECE := 20          # minimum piece size in px
const HALO_FRAC := 0.52        # halo radius as a fraction of the piece size

var color: Color = Color.WHITE
var player_name: String = ""
var token_id: String = ""
var _animations := true
var _cell := 64
var _tile_count := 0   # set by build(); never assume 40 — the board is parametric
var _pid := 0
var _tile := 0
var _active := false
var _in_jail := false
var _piece := 20.0
var _sprite: TextureRect
var _initial: Label
var _has_sprite := false
var _bob_phase := 0.0
var _base_pos := Vector2.ZERO
var _walking := false

func setup(tok: String, col: Color, lbl: String, tile_count: int, cell: int,
		start_idx: int, pid: int) -> void:
	token_id = tok
	color = col
	player_name = lbl
	_tile_count = tile_count
	_cell = cell
	_pid = pid
	_piece = maxf(MIN_PIECE, cell * PIECE_FRAC)
	custom_minimum_size = Vector2(_piece, _piece)
	size = Vector2(_piece, _piece)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5 + pid   # z-order by pid so later players sit on top

	# sprite (SVG art, no recolor). Fall back to a plain circle if the asset
	# is missing (code-built seam so art can swap without logic changes).
	var tex: Texture2D = null
	if ResourceLoader.exists(PI.token_path(token_id)):
		tex = load(PI.token_path(token_id))
	if tex != null:
		_sprite = TextureRect.new()
		_sprite.texture = tex
		_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_sprite)
		_has_sprite = true

	# compact-mode initial (drawn over the halo when the cell is small)
	_initial = Label.new()
	_initial.text = _initial_of(lbl)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_size_override("font_size", maxi(8, int(_piece * 0.4)))
	_initial.add_theme_color_override("font_color", Color.WHITE)
	_initial.add_theme_color_override("font_outline_color", Color.BLACK)
	_initial.add_theme_constant_override("outline_size", 2)
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_initial.visible = false
	add_child(_initial)

	_tile = start_idx
	_base_pos = _fan_pos(start_idx, 0, 1, false)
	position = _base_pos

## First letter of the player name, uppercased (fallback to a pid letter).
func _initial_of(name: String) -> String:
	var n := name.strip_edges()
	if n.length() > 0:
		return n.substr(0, 1).to_upper()
	return "P"

func set_animations(on: bool) -> void:
	_animations = on

func set_active(v: bool) -> void:
	_active = v

## Compact mode: show the initial over the halo (cell below the readability
## threshold). Full mode hides it (the art is unique).
func set_compact(v: bool) -> void:
	if _initial != null:
		_initial.visible = v and not _has_sprite

## Move the token to a tile, fanned out among `fan_count` pieces sharing it.
## Walks step-by-step along the ring when animating; jumps instantly otherwise.
func move_to(tile_idx: int, fan_index: int, fan_count: int, in_jail: bool,
		animate: bool) -> void:
	_in_jail = in_jail
	var target := _fan_pos(tile_idx, fan_index, fan_count, in_jail)
	if animate and _animations and tile_idx != _tile:
		_walk_to(tile_idx, target)
	else:
		position = target
	_base_pos = target
	_tile = tile_idx

## Walk forward along the ring from the current tile to the target, tweening
## through each intermediate tile. Flashes gold when passing GO.
func _walk_to(target_tile: int, target_pos: Vector2) -> void:
	var path: Array[int] = []
	var cur := _tile
	var guard := 0
	while cur != target_tile and guard < _tile_count:
		cur = (cur + 1) % _tile_count
		path.append(cur)
		guard += 1
	# kill any in-flight tween so a new walk starts clean
	if has_meta("_walk_tween"):
		var old = get_meta("_walk_tween")
		if is_instance_valid(old):
			old.kill()
	_walking = false
	var tw := create_tween()
	set_meta("_walk_tween", tw)
	_walking = true
	tw.tween_callback(func(): _walking = false)
	var passed_go := false
	for step in path:
		var p := _fan_pos(step, 0, 1, false)
		tw.tween_property(self, "position", p, STEP_MS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if step == 0:
			passed_go = true
	tw.tween_property(self, "position", target_pos, STEP_MS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if passed_go:
		_flash_go()
	tw.play()

## Gold flash when the piece passes GO.
func _flash_go() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 0.83, 0.3, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color", Color(1, 0.83, 0.3, 0.55), 0.12)
	tw.tween_property(flash, "color", Color(1, 0.83, 0.3, 0.0), 0.25)
	tw.tween_callback(flash.queue_free)

## Pixel position for a piece on `tile_idx`, fanned out among `fan_count`
## pieces along a 60° arc around the tile center (radius 0.35×cell), pointing
## toward the board center. Jail pieces sit toward the corner center.
func _fan_pos(tile_idx: int, fan_index: int, fan_count: int, in_jail: bool) -> Vector2:
	var center := TL.pixel_pos(tile_idx, _tile_count, _cell)
	if in_jail:
		# toward the corner center (the "bars" of the jail corner)
		var dir := _toward_center(tile_idx)
		return center + dir * (_cell * 0.30)
	if fan_count <= 1:
		return center
	var radius := _cell * FAN_RADIUS
	var mid := _toward_center(tile_idx)
	var angle := deg_to_rad(FAN_ARC_DEG * 0.5)
	var t := float(fan_index) / float(fan_count - 1)
	var a := lerpf(-angle, angle, t)
	return center + mid.rotated(a) * radius

## Unit vector from the tile center toward the board center (in cell units).
func _toward_center(tile_idx: int) -> Vector2:
	var grid := TL.grid_cells(_tile_count)
	var c := TL.cell_center(tile_idx, _tile_count)
	var board_center := Vector2((grid - 1) * 0.5, (grid - 1) * 0.5)
	var d := board_center - c
	if d.length() < 0.001:
		return Vector2(0, -1)
	return d.normalized()

func _process(delta: float) -> void:
	# active-player bob (1 Hz) when animations are on; skip while walking so
	# the bob doesn't fight the walk tween's position writes.
	if _active and _animations and not _walking:
		_bob_phase += delta * TAU
		position.y = _base_pos.y + sin(_bob_phase) * 2.0
