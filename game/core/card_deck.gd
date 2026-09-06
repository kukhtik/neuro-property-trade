extends RefCounted
## Two original card decks ("community","chance"). Deterministic draw in order;
## reshuffle is the caller's concern (engine re-seeds Rng). Pure source of card
## dicts — never mutates player state.

var _decks: Dictionary = {}

func load_from_json(data: Dictionary) -> void:
	_decks = {}
	var decks: Dictionary = data.get("decks", {})
	for kind in decks:
		_decks[kind] = (decks[kind] as Array).duplicate()

func size(kind: String) -> int:
	var arr = _decks.get(kind, [])
	return (arr as Array).size()

func cards(kind: String) -> Array:
	var arr = _decks.get(kind, [])
	return (arr as Array).duplicate()

func draw(kind: String):
	var arr = _decks.get(kind)
	if arr == null or (arr as Array).size() == 0:
		return null
	return (arr as Array).pop_front()
