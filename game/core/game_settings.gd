extends RefCounted
## Game configuration, 5 blocks from the spec. Defaults per DEFAULT column.

var seat_count: int = 4
var seat_assignments: Array = []   # per seat: {driver, name, token_color?, token_id?}
var starting_order: String = "random"   # "random" | "manual"

var starting_cash: int = 1500
var go_bonus: int = 200
var jail_rule: String = "both"
var jail_fine: int = 50
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
## Rounds after which the match ends and the RICHEST seat wins (0 = play until one survives).
##
## Without this a game can be unbounded: if no colour group is ever completed nothing is built,
## rent stays trivial, the bank keeps paying out for passing GO and bankruptcy becomes impossible.
## Measured on 4 seats: 17 of 20 seeds were still playing at 250 plies while a 2-seat match always
## ended. `ai_driver` trades and finishes far more often than the corpus policy, but 1 seed in 6
## still inflated instead of ending. This is Monopoly's own "short game" rule.
var round_limit: int = 0

var deck_pairs: int = 2
var deck_shuffle: String = "per_game"

var turn_timer: int = 30
var auction_timer: int = 15
## MULTI-SDK: one websocket endpoint per SDK seat, in seat order. Empty = every SDK seat that exists
## must share the process-wide NEURO_SDK_WS_URL, which only the FIRST one can (one socket, one
## character). With endpoints, each seat owns its connection and its own action registry.
var sdk_endpoints: Array = []
var timeout_action: String = "auto-pass"
var ai_aggression: int = 50
var evil_enabled: bool = false
var spectacle: bool = true
var event_overlay: bool = true
var animations: bool = true   # master toggle for cosmetic tweens (spec control)
var admin_token: String = ""  # token required by admin_gate for remote/override auth
var language: String = "ru"  # UI language ("ru" | "en"); full localization is a follow-up
var rng_seed: int = 0
var tile_count: int = 40  # board perimeter tiles (16..64, multiple of 4)

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
