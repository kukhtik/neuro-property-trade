extends RefCounted
## Tests for the append-only event log.

static func test_list() -> Array[String]:
	return [
		"test_starts_empty",
		"test_append_records_in_order",
		"test_entries_of_type_filters",
		"test_index_sequential",
		"test_clear_resets",
		"test_emit_fires",
	]

static func _new_log():
	return load("res://core/event_log.gd").new()

static func test_starts_empty() -> String:
	var l = _new_log()
	return "" if l.size() == 0 else "expected empty, size=%d" % l.size()

static func test_append_records_in_order() -> String:
	var l = _new_log()
	l.append("move", {"player": "A", "to": 5})
	l.append("purchase", {"tile": 5})
	var es = l.entries()
	if es.size() != 2:
		return "expected 2 entries"
	if es[0]["type"] != "move" or es[0]["data"].get("to") != 5:
		return "first entry wrong"
	if es[1]["type"] != "purchase":
		return "second entry wrong"
	return ""

static func test_entries_of_type_filters() -> String:
	var l = _new_log()
	l.append("move", {})
	l.append("rent", {})
	l.append("move", {})
	var moves = l.entries_of_type("move")
	return "" if moves.size() == 2 else "expected 2 move events, got %d" % moves.size()

static func test_index_sequential() -> String:
	var l = _new_log()
	var a = l.append("x", {})
	var b = l.append("x", {})
	if a != 0 or b != 1:
		return "indices should be sequential 0,1"
	return ""

static func test_clear_resets() -> String:
	var l = _new_log()
	l.append("x", {})
	l.clear()
	return "" if l.size() == 0 else "expected empty after clear"

static func test_emit_fires() -> String:
	var l = _new_log()
	var got := []
	l.event_appended.connect(func(entry): got.append(entry["type"]))
	l.append("move", {})
	return "" if got.size() == 1 and got[0] == "move" else "signal not emitted"
