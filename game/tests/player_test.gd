extends RefCounted
## Tests for the Player data class.

static func test_list() -> Array[String]:
	return [
		"test_initial_state",
		"test_cash_change_credits_and_debits",
		"test_ownership_add_remove",
		"test_owns_only_added",
		"test_no_duplicate_ownership",
	]

static func _new_player(money: int = 1500):
	return load("res://core/player.gd").new("Ada", "tophat", Color.GOLD, money)

static func test_initial_state() -> String:
	var p = _new_player()
	if p.money != 1500:
		return "initial money should be 1500, got %d" % p.money
	if p.position != 0:
		return "initial position should be 0, got %d" % p.position
	if p.name != "Ada":
		return "name not preserved"
	return ""

static func test_cash_change_credits_and_debits() -> String:
	var p = _new_player(1000)
	p.change_cash(250)
	if p.money != 1250:
		return "credit failed: expected 1250, got %d" % p.money
	p.change_cash(-500)
	if p.money != 750:
		return "debit failed: expected 750, got %d" % p.money
	return ""

static func test_ownership_add_remove() -> String:
	var p = _new_player()
	p.add_ownership(5)
	p.add_ownership(15)
	if not p.owns(5) or not p.owns(15):
		return "ownership not recorded"
	p.remove_ownership(5)
	if p.owns(5):
		return "ownership not removed"
	return ""

static func test_owns_only_added() -> String:
	var p = _new_player()
	if p.owns(99):
		return "should not own a tile that was never added"
	return ""

static func test_no_duplicate_ownership() -> String:
	var p = _new_player()
	p.add_ownership(3)
	p.add_ownership(3)
	if p.owned_tiles().size() != 1:
		return "duplicate ownership stored"
	return ""
