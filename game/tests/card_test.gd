extends RefCounted
## Tests for CardDeck (core/card_deck.gd) + data/cards.json.

static func test_list() -> Array[String]:
	return ["test_load_two_decks", "test_has_original_names", "test_draw_rotates", "test_draw_returns_card"]

static func _load_decks() -> Dictionary:
	var C = load("res://core/card_deck.gd")
	var file = FileAccess.open("res://data/cards.json", FileAccess.READ)
	if file == null: return {"deck": null, "json": null}
	var json = JSON.parse_string(file.get_as_text())
	var c = C.new()
	c.load_from_json(json)
	return {"deck": c, "json": json}

static func test_load_two_decks() -> String:
	var r = _load_decks()
	if r["deck"] == null: return "could not load deck"
	var c = r["deck"]
	if c.size("community") < 12: return "community deck too small: %d" % c.size("community")
	if c.size("chance") < 12: return "chance deck too small: %d" % c.size("chance")
	return ""

static func test_has_original_names() -> String:
	var r = _load_decks()
	var c = r["deck"]
	var banned = ["monopoly", "boardwalk", "park place", "go to jail"]
	for kind in ["community", "chance"]:
		for card in c.cards(kind):
			var card_dict = card as Dictionary
			var n = String(card_dict.get("name", "")).to_lower()
			for b in banned:
				if n.find(b) != -1:
					return "banned token '%s' in card name: %s" % [b, n]
	return ""

static func test_draw_rotates() -> String:
	var r = _load_decks()
	var c = r["deck"]
	var first = c.draw("community")
	var second = c.draw("community")
	if first == null or second == null: return "draw returned null"
	if first == second: return "draw did not advance"
	return ""

static func test_draw_returns_card() -> String:
	var r = _load_decks()
	var c = r["deck"]
	var card = c.draw("chance")
	if not (card is Dictionary): return "draw must return a card dict"
	if not (card as Dictionary).has("effect"): return "card missing effect token"
	return ""
