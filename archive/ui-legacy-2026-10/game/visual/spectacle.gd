class_name Spectacle
extends Control
## Auto-focus "camera" (spec §4 spectacle): pans a container over the board to
## the active action tile, driven by engine events. Cosmetic only — never
## blocks the engine. Animations toggle (settings.animations): false => snap.
##
## Implemented as a clip container that pans its child (the board) so the same
## math works headless/windowed without Camera2D viewport coupling.

signal focus_changed(tile_index: int)

const TL := preload("res://visual/tile_layout.gd")

var _board: Control
var _viewport: Control
var _enabled := true
var animations := true
var _cell := 64
var _tile_count := 0   # set by build(); never assume 40 — the board is parametric
var _tween: Tween

## Setup with the viewport container (the "camera") and the board control.
func setup(viewport: Control, board: Control, cell: int, tile_count: int) -> void:
	_viewport = viewport
	_board = board
	_cell = cell
	_tile_count = tile_count

## Center the viewport on a tile index (pans the board).
func focus_on_tile(tile_idx: int, animate: bool) -> void:
	if _viewport == null or _board == null or not _enabled: return
	var target := Vector2.ZERO - TL.pixel_pos(tile_idx, _tile_count, _cell)
	if animate and animations:
		if _tween: _tween.kill()
		_tween = create_tween()
		_tween.tween_property(_viewport, "position", target, 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_viewport.position = target
	focus_changed.emit(tile_idx)

## React to an engine event entry.
func on_event(entry: Dictionary) -> void:
	var t: String = entry.get("type", "")
	if not _enabled: return
	var tile_idx := -1
	if t == "move":
		tile_idx = int(entry.get("to", entry.get("new_pos", -1)))
	elif t == "land" or t == "purchase":
		tile_idx = int(entry.get("tile", -1))
	elif t in ["roll", "auction_start", "auction_bid"]:
		return
	if tile_idx >= 0:
		focus_on_tile(tile_idx, true)

func set_animations(on: bool) -> void:
	animations = on

## P6 CS-7: enable/disable the spectacle entirely (settings.spectacle). When
## disabled the camera stays put and the board is always fully visible.
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on and _viewport != null:
		_viewport.position = Vector2.ZERO
