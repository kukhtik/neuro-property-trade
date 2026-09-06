extends RefCounted
## Tests for GameSettings (core/game_settings.gd).
## Defaults must match the spec's DEFAULT column.

static func test_list() -> Array[String]:
	return ["test_defaults"]

static func test_defaults() -> String:
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	if s.starting_cash != 1500: return "starting_cash default"
	if s.go_bonus != 200: return "go_bonus default"
	if s.free_parking != false: return "free_parking should be off"
	if s.triple_doubles_to_jail != true: return "triple_doubles_to_jail default"
	if s.jail_rule != "both": return "jail_rule default"
	if s.auctions_on_refusal != true: return "auctions_on_refusal default"
	if s.auction_condition != "not-bought": return "auction_condition default"
	if s.housing != true: return "housing default"
	if s.even_build != true: return "even_build default"
	if s.monopoly_rent_x2 != true: return "monopoly_rent_x2 default"
	if s.mortgage != true: return "mortgage default"
	if s.mortgage_loan_pct != 50: return "mortgage loan pct"
	if s.mortgage_repay_pct != 110: return "mortgage repay pct"
	if s.turn_timer != 30: return "turn_timer default"
	if s.auction_timer != 15: return "auction_timer default"
	if s.timeout_action != "auto-pass": return "timeout_action default"
	if s.evil_enabled != false: return "evil_enabled default"
	if s.ai_aggression != 50: return "ai_aggression default"
	return ""
