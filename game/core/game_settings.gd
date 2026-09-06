extends RefCounted
## Game configuration, 5 blocks from the spec. Defaults per DEFAULT column.

var seat_count: int = 4

var starting_cash: int = 1500
var go_bonus: int = 200
var jail_rule: String = "both"
var free_parking: bool = false
var doubles: bool = true
var triple_doubles_to_jail: bool = true
var bankruptcy: String = "normal"

var auctions_on_refusal: bool = true
var auction_condition: String = "not-bought"
var housing: bool = true
var even_build: bool = true
var monopoly_rent_x2: bool = true
var mortgage: bool = true
var mortgage_loan_pct: int = 50
var mortgage_repay_pct: int = 110
var trades: bool = true

var deck_pairs: int = 2
var deck_shuffle: String = "per_game"

var turn_timer: int = 30
var auction_timer: int = 15
var timeout_action: String = "auto-pass"
var ai_aggression: int = 50
var evil_enabled: bool = false
var spectacle: bool = true
var event_overlay: bool = true
var rng_seed: int = 0

func from_data(d: Dictionary) -> void:
	for k in d:
		if k in self:
			set(k, d[k])

func to_data() -> Dictionary:
	var out := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var name: String = prop.name
			out[name] = get(name)
	return out
