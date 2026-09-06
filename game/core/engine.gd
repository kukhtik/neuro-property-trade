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
	var roll = rng.roll_two_dice()
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
