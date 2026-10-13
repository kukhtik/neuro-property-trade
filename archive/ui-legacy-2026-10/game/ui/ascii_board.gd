## ASCII renderer — produces a compact monospace snapshot of the board state.
## Phase 0 text-first: used for headless demos, debugging, and the future
## admin console / stream overlay. Deterministic, no assets, no randomness.

class_name AsciiBoard
extends RefCounted


## Render a full state snapshot to text.
##  - board: loaded Board instance (tile_at/tile_count)
##  - players: Array of players; each has .name, .position, .money, .token_id
## Returns a multi-line String.
static func render(board, players: Array) -> String:
	var lines: Array[String] = []
	for p in players:
		var toks := _tokens_at(players, p.position)
		var tile = board.tile_at(p.position)
		var tname: String = tile.get("name", "?")
		lines.append("  %s%s  pos=%2d  $%6d  tile=%s" % [
			str(p.token_id), str(p.name), p.position, p.money, tname
		])

	# Compact board strip: 40 cells in one line with token letters.
	var strip := ""
	for i in board.tile_count():
		var toks := _tokens_at(players, i)
		var ch := "."
		if toks != "":
			ch = toks[0]   # first token on the cell
		strip += ch
	lines.push_front("Board(%d): %s" % [board.tile_count(), strip])
	return "\n".join(lines)


static func _tokens_at(players: Array, position: int) -> String:
	var out := ""
	for p in players:
		if p.position == position:
			out += str(p.token_id)
	return out
