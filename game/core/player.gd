class_name Player
extends RefCounted
## A single player at the table. Engine-authoritative, hold-only data.
##
## A player never mutates board state directly — the engine reads player
## state and validates intents against it. Hidden info is projected per-seat.

signal cash_changed(old_amount: int, new_amount: int)

var name: String
var token_id: String
var token_color: Color
var money: int
var position: int
var in_jail: bool = false
var get_out_of_jail_cards: int = 0
var bankrupt: bool = false

var _owned: Array = []  # tile indices owned by this player

func _init(p_name: String, p_token: String, p_color: Color, start_money: int = 1500) -> void:
	name = p_name
	token_id = p_token
	token_color = p_color
	money = start_money
	position = 0

## Add money. Positive amount credits, negative debits.
func change_cash(amount: int) -> void:
	var old := money
	money += amount
	cash_changed.emit(old, money)

func owns(index: int) -> bool:
	return _owned.has(index)

func add_ownership(index: int) -> void:
	if not _owned.has(index):
		_owned.append(index)

func remove_ownership(index: int) -> void:
	_owned.erase(index)

func owned_tiles() -> Array:
	return _owned.duplicate()
