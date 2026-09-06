extends RefCounted
## Tests for the deterministic seeded RNG.

static func test_list() -> Array[String]:
	return [
		"test_die_range",
		"test_two_dice_doubles_flag",
		"test_same_seed_same_result",
		"test_different_seed_different_result",
	]

static func _new_rng(seed_value: int):
	var r = load("res://core/rng.gd").new()
	r.seed_rng(seed_value)
	return r

static func test_die_range() -> String:
	var r = _new_rng(42)
	for i in 100:
		var d = r.roll_die()
		if d < 1 or d > 6:
			return "roll_die out of range: %d" % d
	return ""

static func test_two_dice_doubles_flag() -> String:
	var r = _new_rng(7)
	var roll: Dictionary = r.roll_two_dice()
	if roll["sum"] != roll["d1"] + roll["d2"]:
		return "sum inconsistent"
	if roll["doubles"] != (roll["d1"] == roll["d2"]):
		return "doubles flag inconsistent"
	return ""

static func test_same_seed_same_result() -> String:
	var a = _new_rng(123)
	var b = _new_rng(123)
	var seq_a := []
	var seq_b := []
	for i in 20:
		seq_a.append(a.roll_die())
		seq_b.append(b.roll_die())
	if seq_a != seq_b:
		return "same seed produced different sequences"
	return ""

static func test_different_seed_different_result() -> String:
	var a = _new_rng(1)
	var b = _new_rng(2)
	var seq_a := []
	var seq_b := []
	for i in 15:
		seq_a.append(a.roll_die())
		seq_b.append(b.roll_die())
	if seq_a == seq_b:
		return "different seeds produced identical sequences"
	return ""
