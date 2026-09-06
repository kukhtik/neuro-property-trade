extends SceneTree
## ASCII board demo — load the real board.json, place a few players, print the
## board snapshot. Run:  godot --headless --path game --script res://tools/ascii_demo.gd

func _init() -> void:
	var board = load("res://core/board.gd").new()
	var file := FileAccess.open("res://data/board.json", FileAccess.READ)
	if file == null:
		push_error("cannot open board.json")
		quit(1)
		return
	var json: Variant = JSON.parse_string(file.get_as_text())
	if json == null:
		push_error("board.json invalid")
		quit(1)
		return
	board.load_from_json(json)

	var players := [
		{"name": "Neu", "position": 0, "money": 1500, "token_id": "n"},
		{"name": "Evil", "position": 24, "money": 900, "token_id": "e"},
		{"name": "Host", "position": 10, "money": 1200, "token_id": "h"},
	]
	var ascii = load("res://ui/ascii_board.gd")
	print(ascii.render(board, players))
	quit(0)
