## Thin wrapper around the board layout data. Loads board.json once and
## exposes typed accessors for the engine. Deterministic — pure functions of
## the loaded JSON (no randomness).

class_name Board
extends RefCounted

var _tiles: Array[Dictionary] = []
var _by_group: Dictionary = {}

func load_from_json(data: Dictionary) -> void:
	# Board meta must specify tile_count and the tile list.
	var list: Array = data.get("tiles", [])
	_tiles.clear()
	_by_group.clear()
	for entry in list:
		var d: Dictionary = entry
		_tiles.append(d)
		# Index groups by color group for monopoly checks.
		var g: String = d.get("group", "")
		if g != "":
			if not _by_group.has(g):
				_by_group[g] = []
			_by_group[g].append(d.get("index", 0))

func tile_count() -> int:
	return _tiles.size()

func tile_at(index: int) -> Dictionary:
	if index >= 0 and index < _tiles.size():
		return _tiles[index]
	return {}

func type_at(index: int) -> String:
	# Bounds-checked: GDScript indexes negatively from the end, so an
	# out-of-range tile used to silently read as the last tile on the board.
	if index < 0 or index >= _tiles.size():
		return ""
	return _tiles[index].get("type", "property")

func group_tiles(group: String) -> Array:
	return _by_group.get(group, [])
