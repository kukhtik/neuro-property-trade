extends RefCounted
## Authoritative rules engine. Owns Board/players/Rng/EventLog/decks/settings.
## All input enters through submit_intent(); all other transitions are
## automatic. Append-only EventLog records every state change.

const PHASE_SETUP := "SETUP"
const PHASE_TURN_START := "TURN_START"
const PHASE_ROLL_RESOLVE := "ROLL_RESOLVE"
const PHASE_PURCHASE_WAIT := "PURCHASE_WAIT"
const PHASE_AUCTION := "AUCTION"
const PHASE_RENT_SETTLE := "RENT_SETTLE"
const PHASE_CARD_WAIT := "CARD_WAIT"
const PHASE_JAIL_DECISION := "JAIL_DECISION"
const PHASE_END_TURN := "END_TURN"

var settings
var board
var players: Array = []
var log
var rng
var decks: Dictionary = {}
var phase: String = PHASE_SETUP
var turn_player: int = 0
var consecutive_doubles: int = 0
var _forced_roll = null   # Variant: nullable Dictionary for test hook
var _last_roll = {}       # last roll dict, reused by tile resolution (Tasks 5-8)
var _last_doubles: bool = false

func setup(s, names: Array) -> void:
	settings = s
	board = load("res://core/board.gd").new()
	var board_file = FileAccess.open("res://data/board.json", FileAccess.READ)
	board.load_from_json(JSON.parse_string(board_file.get_as_text()))
	log = load("res://core/event_log.gd").new()
	rng = load("res://core/rng.gd").new()
	if settings.rng_seed != 0:
		rng.seed_rng(settings.rng_seed)
	players = []
	for i in names.size():
		var p = load("res://core/player.gd").new(names[i], "token%d" % i, Color.WHITE, settings.starting_cash)
		players.append(p)
	for kind in ["community", "chance"]:
		var d = load("res://core/card_deck.gd").new()
		var card_file = FileAccess.open("res://data/cards.json", FileAccess.READ)
		d.load_from_json(JSON.parse_string(card_file.get_as_text()))
		decks[kind] = d
	phase = PHASE_TURN_START
	turn_player = 0
	log.append("setup", {"players": names.size()})

func player_count() -> int:
	return players.size()

func player(i: int):
	return players[i]

func submit_intent(pid: int, action: String, params: Dictionary) -> Dictionary:
	if pid < 0 or pid >= players.size():
		return {"ok": false, "reason": "no such player", "legal": [], "events": []}
	if pid != turn_player:
		return {"ok": false, "reason": "not your turn", "legal": [], "events": []}
	match phase:
		PHASE_TURN_START:
			if action == "roll":
				return _resolve_roll()
			return {"ok": false, "reason": "must roll", "legal": ["roll"], "events": []}
	return {"ok": false, "reason": "phase %s not ready" % phase, "legal": [], "events": []}

func _resolve_roll() -> Dictionary:
	phase = PHASE_ROLL_RESOLVE
	var roll = _next_roll()
	_last_roll = roll
	_last_doubles = roll.doubles
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles, "sum": roll.sum})
	var p = players[turn_player]
	if p.in_jail:
		# Full jail decision tree (pay/card/doubles-out) lands in Task 8.
		# For this task: jailed turns are a no-op so the game doesn't stall.
		log.append("jail_skip", {"player": turn_player})
		_next_turn()
		return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
	if roll.doubles:
		consecutive_doubles += 1
		if settings.triple_doubles_to_jail and consecutive_doubles >= 3:
			_send_to_jail()
			_next_turn()
			return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
	else:
		consecutive_doubles = 0
	_move_and_resolve(roll)
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _next_roll() -> Dictionary:
	if _forced_roll != null:
		var r = _forced_roll
		_forced_roll = null
		return r
	return rng.roll_two_dice()

func _force_dice(sum: int, d1: int, d2: int, is_doubles: bool) -> void:
	# test-only override of the next roll
	_forced_roll = {"d1": d1, "d2": d2, "sum": sum, "doubles": is_doubles}

func _credit(pid: int, amount: int) -> void:
	# adjust a player's cash and log it (engine-authoritative)
	var p = players[pid]
	p.change_cash(amount)
	log.append("cash", {"player": pid, "amount": amount, "balance": p.money})

func _transfer(from_id: int, to_id: int, amount: int) -> void:
	# move cash between two players (no logging inside; caller logs context)
	players[from_id].change_cash(-amount)
	players[to_id].change_cash(amount)

func _send_to_jail() -> void:
	var p = players[turn_player]
	p.position = 10
	p.in_jail = true
	consecutive_doubles = 0
	log.append("jail", {"player": turn_player, "reason": "entered"})

func _next_turn() -> void:
	# advance to the next player, resetting turn state
	turn_player = (turn_player + 1) % players.size()
	consecutive_doubles = 0
	phase = PHASE_TURN_START
	_last_roll = {}

func _move_and_resolve(roll: Dictionary) -> void:
	var p = players[turn_player]
	var old = p.position
	var new_pos = (old + roll.sum) % 40
	# sum is always 2..12 < 40, so new_pos < old exactly means the move crossed tile 0
	var wrapped = new_pos < old
	if wrapped:
		_credit(turn_player, settings.go_bonus)
		log.append("go_bonus", {"player": turn_player, "amount": settings.go_bonus})
	p.position = new_pos
	log.append("move", {"player": turn_player, "from": old, "to": new_pos, "wrapped": wrapped})
	# For Task 4, tile resolution is minimal: just log landing. purchase/rent/etc land in Tasks 5-8.
	log.append("land", {"player": turn_player, "tile": new_pos, "type": board.type_at(new_pos)})
	# End the turn on non-doubles; on doubles, the same player rolls again (stays TURN_START).
	if _last_doubles:
		phase = PHASE_TURN_START   # same player again; but ensure NOT in a decision phase
	else:
		_next_turn()
