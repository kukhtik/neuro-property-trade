extends RefCounted
## Tests for the ASCII board renderer.

static func test_list() -> Array[String]:
	return [
		"test_returns_lines",
		"test_strip_has_40_cells",
		"test_token_placed_on_tile",
		"test_player_line_has_position_and_money",
	]

static func _make_board():
	var board = load("res://core/board.gd").new()
	var file := FileAccess.open("res://data/board.json", FileAccess.READ)
	var json: Variant = JSON.parse_string(file.get_as_text())
	board.load_from_json(json)
	return board

static func _players():
	return [
		{"name": "Neu", "position": 0, "money": 1500, "token_id": "n"},
		{"name": "Evil", "position": 24, "money": 900, "token_id": "e"},
	]

static func _renderer():
	return load("res://ui/ascii_board.gd")

static func test_returns_lines() -> String:
	var out: String = _renderer().render(_make_board(), _players())
	return "" if out.length() > 0 else "renderer returned empty string"

static func test_strip_has_40_cells() -> String:
	var out: String = _renderer().render(_make_board(), _players())
	var line: String = out.split("\n")[0]
	# strip is "Board(40): <40 chars>"
	var prefix := "Board(40): "
	if not line.begins_with(prefix):
		return "unexpected board line: %s" % line
	var strip: String = line.substr(prefix.length())
	return "" if strip.length() == 40 else "strip length %d != 40" % strip.length()

static func test_token_placed_on_tile() -> String:
	var out: String = _renderer().render(_make_board(), _players())
	var strip: String = out.split("\n")[0].substr("Board(40): ".length())
	# Evil token 'e' is on position 24.
	if strip[24] != "e":
		return "expected 'e' at tile 24, got '%s'" % strip[24]
	return ""

static func test_player_line_has_position_and_money() -> String:
	var out: String = _renderer().render(_make_board(), _players())
	var lines := out.split("\n")
	var found := false
	for ln in lines:
		if "pos=" in ln and "$" in ln:
			found = true
	if not found:
		return "no player status line with pos/money found"
	return ""
