extends RefCounted
## Board tests — verify board.json loads and typed accessors behave.

static func test_list() -> Array[String]:
	return [
		"test_loads_40_tiles",
		"test_go_tile_index_0",
		"test_property_groups_counted",
		"test_no_hasbro_names",
	]

static func _load():
	var board = load("res://core/board.gd").new()
	var file := FileAccess.open("res://data/board.json", FileAccess.READ)
	if file == null:
		push_error("cannot open board.json")
		return board
	var json: Variant = JSON.parse_string(file.get_as_text())
	if json == null:
		push_error("board.json is not valid JSON")
		return board
	board.load_from_json(json)
	return board

static func test_loads_40_tiles() -> String:
	var b = _load()
	return "" if b.tile_count() == 40 else "expected 40 tiles, got %d" % b.tile_count()

static func test_go_tile_index_0() -> String:
	var b = _load()
	var t = b.tile_at(0)
	if t.get("type") != "go":
		return "tile 0 should be 'go', got %s" % str(t.get("type"))
	return ""

static func test_property_groups_counted() -> String:
	var b = _load()
	var groups := []
	for i in b.tile_count():
		var g: String = b.tile_at(i).get("group", "")
		if g != "" and not groups.has(g):
			groups.append(g)
	return "" if groups.size() == 8 else "expected 8 color groups, got %d" % groups.size()

static func test_no_hasbro_names() -> String:
	var b = _load()
	var bad := ["chance", "boardwalk", "monopoly", "reading railroad", "park place"]
	for i in b.tile_count():
		var nm: String = str(b.tile_at(i).get("name", "")).to_lower()
		if nm in bad:
			return "Hasbro/trade-dress name on tile %d: '%s'" % [i, nm]
	return ""
