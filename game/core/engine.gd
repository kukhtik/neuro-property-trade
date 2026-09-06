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
const PHASE_END_GAME := "END_GAME"

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
var _pending = {}         # decision context (e.g. {"tile": N} for purchase)
var _no_extra_turn: bool = false   # set when the current turn must NOT grant a bonus roll (jail-exit doubles, go-to-jail)
var _card_depth: int = 0           # recursion guard for card-triggered moves
var _forced_draw = null   # Variant: nullable Dictionary {kind, card} — test hook
var _houses: Dictionary = {}   # tile index -> house count (0..5; 5 = hotel)
var _mortgaged: Array = []   # tile indices currently mortgaged
var _pending_trade = {}   # {proposer, recipient, give_tiles[], give_cash, want_tiles[], want_cash} or {} when none

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
	# responder path (cross-player action during the trade window): a pending
	# trade may be answered by its recipient regardless of whose turn it is
	# (the proposer's TURN_START). Validated here against _pending_trade.recipient,
	# bypassing the not-your-turn guard below; _resolve_respond_trade re-checks.
	if action == "respond_trade" and _pending_trade.size() != 0:
		var t_rec: int = _pending_trade.get("recipient", -1)
		if pid != t_rec:
			return {"ok": false, "reason": "you are not the trade recipient", "legal": [], "events": []}
		return _resolve_respond_trade(params)
	# During an auction the acting player is tracked in _pending.bidder, not
	# turn_player (the auctioneer still owns the turn slot), so the turn guard
	# is bypassed there; the PHASE_AUCTION branch re-checks pid against bidder.
	if pid != turn_player and phase != PHASE_AUCTION:
		return {"ok": false, "reason": "not your turn", "legal": [], "events": []}
	if phase == PHASE_END_GAME:
		return {"ok": false, "reason": "game over", "legal": [], "events": []}
	match phase:
		PHASE_TURN_START:
			var cur = players[turn_player]
			if cur.in_jail:
				var can_roll: bool = cur.jail_turns < 3
				if action == "roll" and can_roll:
					return _resolve_jail_roll()
				if action == "pay":
					return _resolve_jail_pay()
				if action == "use_card":
					return _resolve_jail_use_card()
				if action == "roll":
					# jail_rule "both": after 3 failed attempts you must pay or use a card
					return {"ok": false, "reason": "must pay fine or use card", "legal": ["pay", "use_card"], "events": []}
				return {"ok": false, "reason": "in jail: roll doubles, pay, or use card", "legal": ["roll", "pay", "use_card"] if can_roll else ["pay", "use_card"], "events": []}
			if action == "roll":
				return _resolve_roll()
			if action == "build_house":
				return _resolve_build_house(params)
			if action == "sell_house":
				return _resolve_sell_house(params)
			if action == "mortgage_property":
				return _resolve_mortgage(params)
			if action == "unmortgage_property":
				return _resolve_unmortgage(params)
			if action == "propose_trade":
				return _resolve_propose_trade(params)
			if action == "respond_trade":
				return _resolve_respond_trade(params)
			var legal: Array = ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property", "propose_trade", "respond_trade"]
			return {"ok": false, "reason": "roll, build, sell, mortgage, or unmortgage", "legal": legal, "events": []}
		PHASE_PURCHASE_WAIT:
			var tile = _pending.get("tile", -1)
			if tile == -1: return {"ok": false, "reason": "no pending purchase", "legal": [], "events": []}
			if action == "buy":
				var tile_data = board.tile_at(tile)
				var cost: int = tile_data.get("cost", 0)
				var p = players[pid]
				if p.money < cost:
					return {"ok": false, "reason": "insufficient funds", "legal": ["pass"], "events": []}
				p.change_cash(-cost)
				p.add_ownership(tile)
				log.append("cash", {"player": pid, "amount": -cost, "balance": p.money})
				log.append("purchase", {"player": pid, "tile": tile, "cost": cost})
				_pending = {}
				# after purchase, end the turn honoring doubles
				_end_turn_or_continue()
				return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
			elif action == "pass":
				if settings.auctions_on_refusal:
					log.append("pass_on_purchase", {"player": pid, "tile": tile})
					_start_auction(tile)
					return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
				log.append("pass", {"player": pid, "tile": tile})
				_pending = {}
				_end_turn_or_continue()
				return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
			return {"ok": false, "reason": "must buy or pass", "legal": ["buy", "pass"], "events": []}
		PHASE_AUCTION:
			var t: int = _pending.get("tile", -1)
			if t == -1:
				return {"ok": false, "reason": "no active auction", "legal": [], "events": []}
			var cur: int = _pending.get("bidder", -1)
			if pid != cur:
				return {"ok": false, "reason": "not your bid", "legal": [], "events": []}
			if action == "bid":
				var amount: int = int(params.get("amount", 0))
				var high: int = _pending.get("high", -1)
				if high != -1 and amount <= high:
					return {"ok": false, "reason": "bid must exceed current high", "legal": ["bid", "pass"], "events": []}
				var bp = players[pid]
				if amount > bp.money:
					return {"ok": false, "reason": "insufficient funds", "legal": ["pass"], "events": []}
				_pending["high"] = amount
				_pending["high_player"] = pid
				log.append("auction_bid", {"player": pid, "amount": amount, "tile": t})
				_advance_bidder()
				return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
			elif action == "pass":
				_auction_pass(t)
				return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
			return {"ok": false, "reason": "must bid or pass", "legal": ["bid", "pass"], "events": []}
	return {"ok": false, "reason": "phase %s not ready" % phase, "legal": [], "events": []}

## Read-only legal-action query for a seat. Mirrors submit_intent's branches
## WITHOUT mutating state. Used by the SDK adapter to project what a seat may
## do at a decision point. Returns an Array[String] of legal action names.
func legal_actions(pid: int) -> Array:
	if pid < 0 or pid >= players.size():
		return []
	if phase == PHASE_END_GAME:
		return []
	# cross-player responder path: a pending trade may be answered by its
	# recipient regardless of whose turn it is
	if _pending_trade.size() != 0 and _pending_trade.get("recipient", -1) == pid:
		return ["respond_trade"]
	# during an auction the acting player is _pending.bidder, not turn_player
	if phase == PHASE_AUCTION:
		if _pending.get("bidder", -1) == pid:
			return ["bid", "pass"]
		return []
	if pid != turn_player:
		return []
	match phase:
		PHASE_TURN_START:
			var cur = players[turn_player]
			if cur.in_jail:
				var can_roll: bool = cur.jail_turns < 3
				var legal: Array = []
				if can_roll:
					legal.append("roll")
				if cur.money >= settings.jail_fine:
					legal.append("pay")
				if cur.get_out_of_jail_cards > 0:
					legal.append("use_card")
				return legal
			return ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property", "propose_trade", "respond_trade"]
		PHASE_PURCHASE_WAIT:
			var tile = _pending.get("tile", -1)
			if tile == -1:
				return []
			var legal: Array = ["pass"]
			var tile_data = board.tile_at(tile)
			if players[pid].money >= int(tile_data.get("cost", 0)):
				legal.append("buy")
			return legal
	return []

func _resolve_roll() -> Dictionary:
	phase = PHASE_ROLL_RESOLVE
	var roll = _next_roll()
	_last_roll = roll
	_last_doubles = roll.doubles
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles, "sum": roll.sum})
	var p = players[turn_player]
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

func _charge(payer: int, amount: int, creditor: int) -> Dictionary:
	# Attempt to transfer 'amount' from payer to creditor (creditor = -1 means the bank).
	# If payer goes insolvent, trigger bankruptcy. Returns {ok: bool, bankrupt: bool}.
	if amount <= 0:
		return {"ok": true, "bankrupt": false}
	var p = players[payer]
	if p.money >= amount:
		if creditor >= 0:
			_transfer(payer, creditor, amount)
			log.append("pay", {"from": payer, "to": creditor, "amount": amount, "balance": players[payer].money})
		else:
			p.change_cash(-amount)
			log.append("cash", {"player": payer, "amount": -amount, "balance": p.money})
		return {"ok": true, "bankrupt": false}
	# cannot cover full amount → insolvent
	_go_bankrupt(payer, creditor)
	return {"ok": false, "bankrupt": true}

func _go_bankrupt(payer: int, creditor: int) -> void:
	# transfer all assets to creditor (bank if creditor == -1). Then drop the player.
	var p = players[payer]
	p.bankrupt = true
	log.append("bankrupt", {"player": payer, "creditor": creditor, "cash": p.money, "tiles": p.owned_tiles().size()})
	var tile_list: Array = p.owned_tiles()
	for t in tile_list:
		p.remove_ownership(t)
		if creditor >= 0:
			players[creditor].add_ownership(t)
	# transfer cash
	if creditor >= 0:
		players[creditor].change_cash(p.money)
		p.change_cash(-p.money)
	_remove_player(payer)
	_check_winner()

func _remove_player(idx: int) -> void:
	players.remove_at(idx)
	if turn_player > idx:
		turn_player -= 1
	elif turn_player == idx:
		turn_player = turn_player % players.size()   # stays on same logical index now pointing at next player
	# reset consecutive doubles for safety
	consecutive_doubles = 0

func _check_winner() -> void:
	if players.size() <= 1:
		phase = PHASE_END_GAME
		if players.size() == 1:
			log.append("winner", {"player": 0, "name": players[0].name})

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
	if phase != PHASE_END_GAME:
		phase = PHASE_TURN_START
	_last_roll = {}

func _owner_of(tile: int) -> int:
	for i in players.size():
		if players[i].owns(tile):
			return i
	return -1

func _group_of(tile: int) -> String:
	return board.tile_at(tile).get("group", "")

func _owns_set(owner: int, group: String) -> bool:
	# true if 'owner' owns every tile in the color group
	if group == "": return false
	var group_tiles: Array = board.group_tiles(group)
	if group_tiles.size() == 0: return false
	for t in group_tiles:
		if not players[owner].owns(t): return false
		# a mortgaged tile in the group breaks the monopoly
		# (group_tiles holds JSON floats (1.0); int() normalizes for Array.has)
		if _mortgaged.has(int(t)): return false
	return true

func _property_rent(tile: int, owner: int) -> int:
	# returns rent owed when 'owner' collects from a lander on 'tile'.
	# Houses (count 1..5) take priority over monopoly doubling.
	# A mortgaged property collects no rent.
	if _mortgaged.has(tile): return 0
	var houses_on: int = _houses_on(tile)
	if houses_on > 0:
		var rents: Array = board.tile_at(tile).get("houses", [])
		var idx: int = houses_on - 1   # houses_on 1..5 -> rents[0..4]
		if idx >= 0 and idx < rents.size():
			return int(rents[idx])
		return board.tile_at(tile).get("rent", 0)
	if settings.monopoly_rent_x2 and _owns_set(owner, _group_of(tile)):
		return board.tile_at(tile).get("rent_set", board.tile_at(tile).get("rent", 0))
	return board.tile_at(tile).get("rent", 0)

func _houses_on(tile: int) -> int:
	return int(_houses.get(tile, 0))

func _set_min_houses(group: String) -> int:
	# min house count across a full group (even-build reference). Returns 99 if empty.
	var tiles: Array = board.group_tiles(group)
	var mn: int = 99
	for t in tiles:
		var h: int = _houses_on(t)
		if h < mn: mn = h
	return mn

func _set_max_houses(group: String) -> int:
	var tiles: Array = board.group_tiles(group)
	var mx: int = 0
	for t in tiles:
		var h: int = _houses_on(t)
		if h > mx: mx = h
	return mx

func _resolve_build_house(params: Dictionary) -> Dictionary:
	if not settings.housing:
		return {"ok": false, "reason": "housing disabled", "legal": ["roll", "sell_house"], "events": []}
	var tile: int = int(params.get("tile", -1))
	if tile == -1:
		return {"ok": false, "reason": "tile required", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var p = players[turn_player]
	if not p.owns(tile):
		return {"ok": false, "reason": "you do not own that tile", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var group: String = _group_of(tile)
	if group == "":
		return {"ok": false, "reason": "not a buildable property", "legal": ["roll", "build_house", "sell_house"], "events": []}
	if not _owns_set(turn_player, group):
		return {"ok": false, "reason": "must own the full set to build", "legal": ["roll", "sell_house"], "events": []}
	var houses_on: int = _houses_on(tile)
	if houses_on >= 5:
		return {"ok": false, "reason": "already a hotel", "legal": ["roll", "sell_house"], "events": []}
	if settings.even_build and houses_on > _set_min_houses(group):
		return {"ok": false, "reason": "even build required", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var unit_cost: int = board.tile_at(tile).get("house_cost", 0)
	if p.money < unit_cost:
		return {"ok": false, "reason": "insufficient funds", "legal": ["roll", "sell_house"], "events": []}
	p.change_cash(-unit_cost)
	_houses[tile] = houses_on + 1
	log.append("cash", {"player": turn_player, "amount": -unit_cost, "balance": p.money})
	log.append("build", {"player": turn_player, "tile": tile, "houses": _houses_on(tile), "cost": unit_cost})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_sell_house(params: Dictionary) -> Dictionary:
	var tile: int = int(params.get("tile", -1))
	if tile == -1:
		return {"ok": false, "reason": "tile required", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var p = players[turn_player]
	if not p.owns(tile):
		return {"ok": false, "reason": "you do not own that tile", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var houses_on: int = _houses_on(tile)
	if houses_on <= 0:
		return {"ok": false, "reason": "no houses to sell", "legal": ["roll", "build_house"], "events": []}
	var group: String = _group_of(tile)
	if settings.even_build and group != "" and _owns_set(turn_player, group) and houses_on < _set_max_houses(group):
		return {"ok": false, "reason": "even build required", "legal": ["roll", "build_house", "sell_house"], "events": []}
	var unit_cost: int = board.tile_at(tile).get("house_cost", 0)
	var refund: int = unit_cost / 2
	p.change_cash(refund)
	_houses[tile] = houses_on - 1
	log.append("cash", {"player": turn_player, "amount": refund, "balance": p.money})
	log.append("sell", {"player": turn_player, "tile": tile, "houses": _houses_on(tile), "refund": refund})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_mortgage(params: Dictionary) -> Dictionary:
	if not settings.mortgage:
		return {"ok": false, "reason": "mortgage disabled", "legal": ["roll", "build_house", "sell_house", "unmortgage_property"], "events": []}
	var tile: int = int(params.get("tile", -1))
	if tile == -1:
		return {"ok": false, "reason": "tile required", "legal": ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property"], "events": []}
	var p = players[turn_player]
	if not p.owns(tile):
		return {"ok": false, "reason": "you do not own that tile", "legal": ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property"], "events": []}
	if _mortgaged.has(tile):
		return {"ok": false, "reason": "already mortgaged", "legal": ["roll", "build_house", "sell_house", "unmortgage_property"], "events": []}
	if _houses_on(tile) > 0:
		return {"ok": false, "reason": "must sell houses first", "legal": ["roll", "sell_house"], "events": []}
	var cost: int = board.tile_at(tile).get("cost", 0)
	var loan: int = int(round(cost * (settings.mortgage_loan_pct / 100.0)))
	p.change_cash(loan)
	_mortgaged.append(tile)
	log.append("cash", {"player": turn_player, "amount": loan, "balance": p.money})
	log.append("mortgage", {"player": turn_player, "tile": tile, "loan": loan})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_unmortgage(params: Dictionary) -> Dictionary:
	if not settings.mortgage:
		return {"ok": false, "reason": "mortgage disabled", "legal": ["roll", "build_house", "sell_house", "mortgage_property"], "events": []}
	var tile: int = int(params.get("tile", -1))
	if tile == -1:
		return {"ok": false, "reason": "tile required", "legal": ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property"], "events": []}
	var p = players[turn_player]
	if not p.owns(tile):
		return {"ok": false, "reason": "you do not own that tile", "legal": ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property"], "events": []}
	if not _mortgaged.has(tile):
		return {"ok": false, "reason": "not mortgaged", "legal": ["roll", "build_house", "sell_house", "mortgage_property"], "events": []}
	var cost: int = board.tile_at(tile).get("cost", 0)
	var owe: int = int(round(cost * (settings.mortgage_repay_pct / 100.0)))
	if p.money < owe:
		return {"ok": false, "reason": "insufficient funds", "legal": ["roll", "build_house", "sell_house", "mortgage_property"], "events": []}
	p.change_cash(-owe)
	_mortgaged.erase(tile)
	log.append("cash", {"player": turn_player, "amount": -owe, "balance": p.money})
	log.append("unmortgage", {"player": turn_player, "tile": tile, "owe": owe})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

# --- Task B5: TRADES (propose/respond during the proposer's TURN_START) ---

func _resolve_propose_trade(params: Dictionary) -> Dictionary:
	if not settings.trades:
		return {"ok": false, "reason": "trades disabled", "legal": ["roll", "build_house", "sell_house", "mortgage_property", "unmortgage_property"], "events": []}
	if _pending_trade.size() != 0:
		return {"ok": false, "reason": "a trade is already pending", "legal": ["roll", "respond_trade"], "events": []}
	var recipient: int = int(params.get("to", -1))
	if recipient < 0 or recipient >= players.size():
		return {"ok": false, "reason": "invalid recipient", "legal": ["roll"], "events": []}
	if recipient == turn_player:
		return {"ok": false, "reason": "cannot trade with yourself", "legal": ["roll"], "events": []}
	var give_tiles: Array = params.get("give_tiles", [])
	var want_tiles: Array = params.get("want_tiles", [])
	var give_cash: int = int(params.get("give_cash", 0))
	var want_cash: int = int(params.get("want_cash", 0))
	# validate proposer owns all give tiles, has enough cash
	var p = players[turn_player]
	for t in give_tiles:
		if not p.owns(t):
			return {"ok": false, "reason": "you do not own all offered tiles", "legal": ["roll"], "events": []}
	if give_cash < 0 or p.money < give_cash:
		return {"ok": false, "reason": "insufficient cash for offer", "legal": ["roll"], "events": []}
	_pending_trade = {"proposer": turn_player, "recipient": recipient, "give_tiles": give_tiles.duplicate(), "give_cash": give_cash, "want_tiles": want_tiles.duplicate(), "want_cash": want_cash}
	log.append("trade_proposed", {"proposer": turn_player, "to": recipient, "give_tiles": give_tiles, "give_cash": give_cash, "want_tiles": want_tiles, "want_cash": want_cash})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_respond_trade(params: Dictionary) -> Dictionary:
	if _pending_trade.size() == 0:
		return {"ok": false, "reason": "no pending trade", "legal": ["roll"], "events": []}
	var recipient: int = _pending_trade.get("recipient", -1)
	if recipient < 0 or recipient >= players.size():
		return {"ok": false, "reason": "invalid recipient", "legal": ["roll"], "events": []}
	# pid == recipient is already enforced by the early responder path in
	# submit_intent; only accept/decline resolution remains here.
	var accept: bool = bool(params.get("accept", false))
	if accept:
		_execute_trade()
	else:
		log.append("trade_declined", {"proposer": _pending_trade.get("proposer"), "recipient": recipient})
		_pending_trade = {}
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _execute_trade() -> void:
	# mutual swap of tiles + cash. Mortgaged tiles transfer still mortgaged.
	var proposer: int = _pending_trade.get("proposer")
	var recipient: int = _pending_trade.get("recipient")
	var give_tiles: Array = _pending_trade.get("give_tiles", [])
	var want_tiles: Array = _pending_trade.get("want_tiles", [])
	var give_cash: int = _pending_trade.get("give_cash", 0)
	var want_cash: int = _pending_trade.get("want_cash", 0)
	var a = players[proposer]
	var b = players[recipient]
	for t in give_tiles:
		a.remove_ownership(t)
		b.add_ownership(t)
	for t in want_tiles:
		b.remove_ownership(t)
		a.add_ownership(t)
	# cash: proposer gives give_cash to recipient; recipient gives want_cash to proposer
	if give_cash > 0:
		a.change_cash(-give_cash)
		b.change_cash(give_cash)
	if want_cash > 0:
		b.change_cash(-want_cash)
		a.change_cash(want_cash)
	log.append("trade", {"proposer": proposer, "recipient": recipient, "give_tiles": give_tiles, "give_cash": give_cash, "want_tiles": want_tiles, "want_cash": want_cash})
	_pending_trade = {}

func _teleport(pid: int, tile: int) -> void:
	# test hook: deterministically place a player before a forced roll
	players[pid].position = tile
	log.append("teleport", {"player": pid, "tile": tile})

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
	_last_roll = roll   # ensure last roll is set before resolution (it is set in _resolve_roll, but keep for safety)
	log.append("move", {"player": turn_player, "from": old, "to": new_pos, "wrapped": wrapped})
	var ttype: String = board.type_at(new_pos)
	log.append("land", {"player": turn_player, "tile": new_pos, "type": ttype})
	if ttype == "property":
		var owner = _owner_of(new_pos)
		if owner == -1:
			# unowned — offer a purchase; the current player stays turn_player
			phase = PHASE_PURCHASE_WAIT
			_pending = {"tile": new_pos}
			return
		elif owner == turn_player:
			log.append("land_self", {"player": turn_player, "tile": new_pos})
		else:
			var rent: int = _property_rent(new_pos, owner)
			var c = _charge(turn_player, rent, owner)
			if c.bankrupt: return
			log.append("rent", {"from": turn_player, "to": owner, "tile": new_pos, "amount": rent})
	elif ttype == "railroad":
		var rowner = _owner_of(new_pos)
		if rowner != -1 and rowner != turn_player:
			var owned_count: int = 0
			for ridx in [5, 15, 25, 35]:
				if players[rowner].owns(ridx): owned_count += 1
			var rtable: Dictionary = {1: 25, 2: 50, 3: 100, 4: 200}
			var rrent: int = rtable.get(owned_count, 25)
			var c2 = _charge(turn_player, rrent, rowner)
			if c2.bankrupt: return
			log.append("rent", {"from": turn_player, "to": rowner, "tile": new_pos, "amount": rrent})
	elif ttype == "utility":
		var uowner = _owner_of(new_pos)
		if uowner != -1 and uowner != turn_player:
			var owns_both: bool = players[uowner].owns(12) and players[uowner].owns(28)
			var sum: int = roll.get("sum", _last_roll.get("sum", 7))
			var urent: int = (10 if owns_both else 4) * sum
			var c3 = _charge(turn_player, urent, uowner)
			if c3.bankrupt: return
			log.append("rent", {"from": turn_player, "to": uowner, "tile": new_pos, "amount": urent})
	elif ttype == "tax":
		var amt: int = board.tile_at(new_pos).get("amount", 0)
		var c4 = _charge(turn_player, amt, -1)
		if c4.bankrupt: return
		log.append("tax", {"player": turn_player, "tile": new_pos, "amount": amt})
	elif ttype == "free_parking":
		# house rule OFF by default — no money collected, nothing happens
		log.append("land", {"player": turn_player, "tile": new_pos, "type": ttype, "note": "free_parking off"})
	elif ttype == "go_to_jail":
		_send_to_jail()
		_no_extra_turn = true   # going to jail always ends your turn (even on doubles)
	elif ttype == "community" or ttype == "chance":
		var kind: String = "community" if ttype == "community" else "chance"
		var card = _draw_card(kind)
		if card == null:
			log.append("card_null", {"player": turn_player, "kind": kind})
		else:
			log.append("card_draw", {"player": turn_player, "kind": kind, "name": card.get("name", ""), "effect": card.get("effect", ""), "value": card.get("value", 0)})
			_apply_card_effect(card)
			# _apply_card_effect may have changed phase (e.g. PURCHASE_WAIT / jail) —
			# if it set a decision phase, return now WITHOUT the trailing end-of-turn.
			if phase == PHASE_PURCHASE_WAIT or phase == PHASE_JAIL_DECISION or phase == PHASE_CARD_WAIT:
				return
	# (no else for "go"/"jail" — they do nothing and fall through to end-of-turn)
	_end_turn_or_continue()

func _end_turn_or_continue() -> void:
	# Unified end-of-turn. Normally doubles grant the same player another roll;
	# _no_extra_turn (jail-exit doubles, going to jail) suppresses that.
	if phase == PHASE_END_GAME:
		return
	if _no_extra_turn:
		_no_extra_turn = false
		_next_turn()
	elif _last_doubles:
		phase = PHASE_TURN_START   # same player again
	else:
		_next_turn()

# --- Task 8: JAIL decision (rule "both") ---

func _resolve_jail_roll() -> Dictionary:
	var roll = _next_roll()
	_last_roll = roll
	var was_doubles: bool = roll.doubles
	_last_doubles = roll.doubles
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles, "sum": roll.sum})
	var p = players[turn_player]
	if was_doubles:
		p.in_jail = false
		p.jail_turns = 0
		log.append("jail", {"player": turn_player, "reason": "doubles, out"})
		_no_extra_turn = true   # rolling out of jail does NOT grant a bonus turn
		_move_and_resolve(roll)
	else:
		p.jail_turns += 1
		log.append("jail", {"player": turn_player, "reason": "no doubles", "turns": p.jail_turns})
		# failed attempt consumes the turn; if this was the 3rd failure they must pay next
		_next_turn()
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_jail_pay() -> Dictionary:
	var p = players[turn_player]
	if p.money < settings.jail_fine:
		# can't pay — but they have no alternative unless they hold cards; fail-closed:
		if p.get_out_of_jail_cards > 0:
			return {"ok": false, "reason": "insufficient funds, use a card", "legal": ["use_card"], "events": []}
		return {"ok": false, "reason": "insufficient funds to pay jail fine", "legal": [], "events": []}
	_credit(turn_player, -settings.jail_fine)
	p.in_jail = false
	p.jail_turns = 0
	log.append("jail", {"player": turn_player, "reason": "paid fine", "amount": settings.jail_fine})
	# after paying you still get a normal roll+move this turn
	var roll = _next_roll()
	_last_roll = roll
	_last_doubles = roll.doubles
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles, "sum": roll.sum})
	_move_and_resolve(roll)
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

func _resolve_jail_use_card() -> Dictionary:
	var p = players[turn_player]
	if p.get_out_of_jail_cards <= 0:
		return {"ok": false, "reason": "no get-out-of-jail cards", "legal": ["roll", "pay"], "events": []}
	p.get_out_of_jail_cards -= 1
	p.in_jail = false
	p.jail_turns = 0
	log.append("jail", {"player": turn_player, "reason": "used card"})
	var roll = _next_roll()
	_last_roll = roll
	_last_doubles = roll.doubles
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles, "sum": roll.sum})
	_move_and_resolve(roll)
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

# --- Task 8: CARD draw/apply (original decks, engine-authoritative) ---

func _force_draw_card(kind: String, effect: String, value: int, extra: Dictionary = {}) -> void:
	# test hook: override the next draw for 'kind' with a synthetic card
	_forced_draw = {"kind": kind, "card": {"name": "Forced Card", "kind": kind, "effect": effect, "value": value, "extra": extra}}

func _draw_card(kind: String):
	if _forced_draw != null:
		var d = _forced_draw
		if d["kind"] == kind:
			_forced_draw = null
			return d["card"]
	var deck = decks.get(kind)
	if deck == null: return null
	return deck.draw(kind)

func _apply_card_effect(card: Dictionary) -> void:
	var effect: String = card.get("effect", "")
	var value: int = card.get("value", 0)
	var p = players[turn_player]
	match effect:
		"collect":
			_credit(turn_player, value)
		"pay":
			var c = _charge(turn_player, value, -1)
			if c.bankrupt: return
		"go_to_jail":
			_send_to_jail()
			_no_extra_turn = true
		"jail_card":
			p.get_out_of_jail_cards += 1
			log.append("card_gain", {"player": turn_player, "type": "jail_card"})
		"collect_from_all":
			for i in players.size():
				if i != turn_player:
					if players[i].money >= value:
						_transfer(i, turn_player, value)
						log.append("rent", {"from": i, "to": turn_player, "amount": value, "tile": -1, "reason": "collect_from_all"})
		"pay_each_player":
			for i in players.size():
				if i != turn_player:
					if p.money >= value:
						var c5 = _charge(turn_player, value, i)
						if c5.bankrupt: break
						log.append("rent", {"from": turn_player, "to": i, "amount": value, "tile": -1, "reason": "pay_each_player"})
		"move_to":
			_card_depth += 1
			if _card_depth <= 5:
				_card_move_to(card.get("value", 0))
			_card_depth -= 1
		"advance":
			_card_depth += 1
			if _card_depth <= 5:
				var target = (p.position + value) % 40  # value may be negative
				_card_move_to_mod(target, value)
			_card_depth -= 1

func _card_move_to(target_tile: int) -> void:
	var p = players[turn_player]
	var from = p.position
	# moving FORWARD (target < from means wrapping past 0 → collect GO). Moving to Start (0) also pays GO bonus per classic.
	if target_tile == 0 or target_tile < from:
		_credit(turn_player, settings.go_bonus)
		log.append("go_bonus", {"player": turn_player, "amount": settings.go_bonus, "reason": "card"})
	p.position = target_tile
	log.append("move", {"player": turn_player, "from": from, "to": target_tile, "reason": "card"})
	_resolve_card_landing(target_tile)

func _card_move_to_mod(target_tile: int, raw_value: int) -> void:
	# for 'advance', collect GO only when moving forward and wrapping past 0
	var p = players[turn_player]
	var from = p.position
	var wrapped = raw_value > 0 and target_tile < from
	if wrapped or target_tile == 0:
		_credit(turn_player, settings.go_bonus)
		log.append("go_bonus", {"player": turn_player, "amount": settings.go_bonus, "reason": "card"})
	p.position = target_tile
	log.append("move", {"player": turn_player, "from": from, "to": target_tile, "reason": "card"})
	_resolve_card_landing(target_tile)

func _resolve_card_landing(tile: int) -> void:
	# When a card moves a player, the destination tile's effects apply (rent, purchase wait, another card, jail, tax...).
	var ttype: String = board.type_at(tile)
	var lander = players[turn_player]
	log.append("card_land", {"player": turn_player, "tile": tile, "type": ttype})
	match ttype:
		"property":
			var owner = _owner_of(tile)
			if owner == -1:
				phase = PHASE_PURCHASE_WAIT
				_pending = {"tile": tile}
			elif owner == turn_player:
				log.append("land_self", {"player": turn_player, "tile": tile})
			else:
				var rent: int = _property_rent(tile, owner)
				var c = _charge(turn_player, rent, owner)
				if c.bankrupt: return
				log.append("rent", {"from": turn_player, "to": owner, "tile": tile, "amount": rent})
		"railroad", "utility":
			# unowned → nothing; owned by other → rent (reuse compact logic)
			var r_owner = _owner_of(tile)
			if r_owner != -1 and r_owner != turn_player:
				if ttype == "railroad":
					var n: int = 0
					for ridx in [5, 15, 25, 35]:
						if players[r_owner].owns(ridx): n += 1
					var rt: int = ({1:25, 2:50, 3:100, 4:200}).get(n, 25)
					var c2 = _charge(turn_player, rt, r_owner)
					if c2.bankrupt: return
					log.append("rent", {"from": turn_player, "to": r_owner, "tile": tile, "amount": rt})
				else:
					var both: bool = players[r_owner].owns(12) and players[r_owner].owns(28)
					var usum: int = _last_roll.get("sum", 7)
					var ur: int = (10 if both else 4) * usum
					var c3 = _charge(turn_player, ur, r_owner)
					if c3.bankrupt: return
					log.append("rent", {"from": turn_player, "to": r_owner, "tile": tile, "amount": ur})
		"tax":
			var amt2: int = board.tile_at(tile).get("amount", 0)
			var c4 = _charge(turn_player, amt2, -1)
			if c4.bankrupt: return
			log.append("tax", {"player": turn_player, "tile": tile, "amount": amt2})
		"go_to_jail":
			_send_to_jail()
			_no_extra_turn = true
		"community", "chance":
			var kind2: String = "community" if ttype == "community" else "chance"
			var c2 = _draw_card(kind2)
			if c2 != null:
				log.append("card_draw", {"player": turn_player, "kind": kind2, "name": c2.get("name", ""), "effect": c2.get("effect", "")})
				_apply_card_effect(c2)
		_: # go, jail, free_parking → nothing
			pass

# --- Task 6: AUCTION phase (round-robin, engine-authoritative) ---

func _start_auction(tile: int) -> void:
	phase = PHASE_AUCTION
	var active: Array = []
	for i in players.size():
		active.append(i)
	_pending = {"tile": tile, "high": -1, "high_player": -1, "active": active, "bidder": turn_player}
	log.append("auction_start", {"tile": tile, "auctioneer": turn_player})

func _advance_bidder() -> void:
	# after a successful bid: rotate to the next ACTIVE player (wrap around)
	var active = _pending.get("active", [])
	if active.size() == 0: return
	var cur: int = _pending.get("bidder", -1)
	var idx: int = active.find(cur)
	if idx == -1:
		_pending["bidder"] = active[0]
		return
	var next_idx: int = (idx + 1) % active.size()
	_pending["bidder"] = active[next_idx]

func _auction_pass(t: int) -> void:
	var cur: int = _pending.get("bidder", -1)
	log.append("auction_pass", {"player": cur, "tile": t})
	var active: Array = _pending.get("active", [])
	var idx: int = active.find(cur)   # position of the passer in turn order
	active.erase(cur)
	_pending["active"] = active
	if active.size() == 0:
		# everyone passed: unowned if no bid ever made, else the last bidder wins
		var high: int = _pending.get("high", -1)
		if high != -1:
			var winner: int = _pending.get("high_player", -1)
			_resolve_auction(winner, t, high)
		else:
			log.append("auction_unwon", {"tile": t})
			_pending = {}
			_end_turn_or_continue()
	elif active.size() == 1 and _pending.get("high", -1) != -1:
		# one bidder left and someone has bid → they win at the current high
		_resolve_auction(active[0], t, _pending.get("high", 0))
	else:
		# auction stays open: rotate to the next surviving player after the
		# passer in turn order (wrap to the front if the passer was last)
		if idx != -1 and idx < active.size():
			_pending["bidder"] = active[idx]
		else:
			_pending["bidder"] = active[0]

func _resolve_auction(winner: int, tile: int, pay: int) -> void:
	var wp = players[winner]
	var c = _charge(winner, pay, -1)
	if c.bankrupt:
		# winner shouldn't be able to bid more than they hold; unreachable, but stay safe
		return
	wp.add_ownership(tile)
	log.append("cash", {"player": winner, "amount": -pay, "balance": wp.money})
	log.append("auction_win", {"player": winner, "tile": tile, "amount": pay})
	_pending = {}
	_end_turn_or_continue()

# --- Phase 4: ADMIN overrides (spec §4). Host-local, engine-authoritative. ---
## One admin entry — every edit validated, executed, and written to the SAME
## append-only event log (spec §4 hard rule #1). Never gate by the turn-player
## guard: an admin is host-local and may act any time, but every op range-checks
## its params and rejects invalid ones BEFORE mutating. Mirrors submit_intent's
## {ok, reason, legal, events} shape.
func admin_override(op: String, params: Dictionary) -> Dictionary:
	if settings == null or phase == PHASE_SETUP:
		return _admin_fail("game not started")
	match op:
		"set_balance":
			var pid: int = int(params.get("pid", -1))
			var amount: int = int(params.get("amount", -1))
			if pid < 0 or pid >= players.size():
				return _admin_fail("bad pid")
			if amount < 0:
				return _admin_fail("negative balance")
			players[pid].money = amount
			return _admin_ok(op, params)
		"teleport":
			var pid: int = int(params.get("pid", -1))
			var tile: int = int(params.get("tile", -1))
			if pid < 0 or pid >= players.size():
				return _admin_fail("bad pid")
			if tile < 0 or tile >= board.tile_count():
				return _admin_fail("bad tile")
			players[pid].position = tile
			return _admin_ok(op, params)
		"force_dice":
			var d1: int = int(params.get("d1", 0))
			var d2: int = int(params.get("d2", 0))
			# d1,d2 in 0..6; 0 marks a non-die (the engine's own _force_dice hook
			# uses d2=0 to force a specific non-doubles sum). Reject an all-zero roll.
			if d1 < 0 or d1 > 6 or d2 < 0 or d2 > 6 or (d1 == 0 and d2 == 0):
				return _admin_fail("dice out of 0..6 (not both zero)")
			_force_dice(d1 + d2, d1, d2, d1 == d2)
			return _admin_ok(op, params)
		"grant_property":
			var gpid: int = int(params.get("pid", -1))
			var gtile: int = int(params.get("tile", -1))
			if gpid < 0 or gpid >= players.size():
				return _admin_fail("bad pid")
			if gtile < 0 or gtile >= board.tile_count():
				return _admin_fail("bad tile")
			players[gpid].add_ownership(gtile)
			return _admin_ok(op, params)
		"revoke_property":
			var rpid: int = int(params.get("pid", -1))
			var rtile: int = int(params.get("tile", -1))
			if rpid < 0 or rpid >= players.size():
				return _admin_fail("bad pid")
			if rtile < 0 or rtile >= board.tile_count():
				return _admin_fail("bad tile")
			players[rpid].remove_ownership(rtile)
			_houses.erase(rtile)
			_mortgaged.erase(rtile)
			return _admin_ok(op, params)
		"set_houses":
			var stile: int = int(params.get("tile", -1))
			var count: int = int(params.get("count", -1))
			if stile < 0 or stile >= board.tile_count():
				return _admin_fail("bad tile")
			if count < 0 or count > 5:
				return _admin_fail("house count 0..5")
			_houses[stile] = count
			return _admin_ok(op, params)
		"set_mortgage":
			var mtile: int = int(params.get("tile", -1))
			var on: bool = bool(params.get("on", false))
			if mtile < 0 or mtile >= board.tile_count():
				return _admin_fail("bad tile")
			if on and not _mortgaged.has(mtile):
				_mortgaged.append(mtile)
			elif not on:
				_mortgaged.erase(mtile)
			return _admin_ok(op, params)
		"set_go_jail":
			var jpid: int = int(params.get("pid", -1))
			if jpid < 0 or jpid >= players.size():
				return _admin_fail("bad pid")
			var p = players[jpid]
			p.in_jail = true
			p.jail_turns = 0
			p.position = 10
			return _admin_ok(op, params)
		"force_roll":
			if _admin_decision_holder() == -1:
				return _admin_fail("no active decision")
			return _admin_submit_for_holder("roll", {}, "force_roll")
		"force_pass":
			var h: int = _admin_decision_holder()
			if h == -1:
				return _admin_fail("no active decision")
			var ma = load("res://seats/minimal_action.gd").pick(self, h)
			if ma.is_empty():
				return _admin_fail("no passive action for holder")
			return _admin_submit_for_holder(ma.get("action"), ma.get("params", {}), "force_pass")
		"rollback_decision":
			_pending = {}
			_pending_trade = {}
			return _admin_ok(op, params)
		"tweak_tile":
			# Live edit of a tile's static cost/rent data (spec §4.B deferred).
			# Mutates the in-memory board tile dict (board.json is the seed; the
			# running game uses the live copy). Only numeric fields are editable.
			var ttile: int = int(params.get("tile", -1))
			if ttile < 0 or ttile >= board.tile_count():
				return _admin_fail("bad tile")
			var td: Dictionary = board.tile_at(ttile)
			var changed := false
			for key in ["cost", "rent", "rent_set", "house_cost"]:
				if params.has(key):
					var v: int = int(params[key])
					if v < 0:
						return _admin_fail("negative %s" % key)
					td[key] = v
					changed = true
			if not changed:
				return _admin_fail("no editable field supplied")
			return _admin_ok(op, params)
		"deck_insert":
			# Insert a card at the FRONT of a deck (drawn next). Card must be a
			# valid dict with name/kind/effect/value. kind must match the deck.
			var dkind: String = str(params.get("kind", ""))
			if not decks.has(dkind):
				return _admin_fail("bad deck kind")
			var card: Dictionary = params.get("card", {})
			if card.is_empty() or not card.has("name") or not card.has("effect"):
				return _admin_fail("card needs name+effect")
			card["kind"] = dkind
			card["value"] = int(card.get("value", 0))
			decks[dkind]._decks[dkind].push_front(card)
			return _admin_ok(op, params)
		"deck_remove":
			# Remove the first card in a deck whose name matches (or the front
			# card if no name given). Returns the removed card in the event.
			var rkind: String = str(params.get("kind", ""))
			if not decks.has(rkind):
				return _admin_fail("bad deck kind")
			var arr: Array = decks[rkind]._decks[rkind]
			if arr.is_empty():
				return _admin_fail("deck empty")
			var rname: String = str(params.get("name", ""))
			var removed: Dictionary = {}
			if rname == "":
				removed = arr.pop_front()
			else:
				var idx := -1
				for i in arr.size():
					if str(arr[i].get("name", "")) == rname:
						idx = i
						break
				if idx == -1:
					return _admin_fail("no card named %s" % rname)
				removed = arr[idx]
				arr.remove_at(idx)
			return _admin_ok(op, {"op": op, "kind": rkind, "removed": removed})
		"reorder_players":
			# Reorder the players array by a permutation of pids. turn_player is
			# remapped so the SAME logical player keeps the turn. Each pid must
			# appear exactly once.
			var order: Array = params.get("order", [])
			if order.size() != players.size():
				return _admin_fail("order must list every pid exactly once")
			var seen := {}
			for pid in order:
				var p: int = int(pid)
				if p < 0 or p >= players.size() or seen.has(p):
					return _admin_fail("bad order permutation")
				seen[p] = true
			var cur: int = turn_player
			var new_players: Array = []
			for pid in order:
				new_players.append(players[int(pid)])
			players = new_players
			# remap turn_player: find where the old turn holder landed
			turn_player = order.find(cur)
			return _admin_ok(op, params)
		"redo_turn":
			# Re-seed the RNG and reset the current turn to TURN_START so the
			# same player re-rolls deterministically from the given seed. Clears
			# any pending decision/trade and the last roll.
			var seed: int = int(params.get("seed", 0))
			if seed == 0:
				return _admin_fail("seed must be non-zero")
			rng.seed_rng(seed)
			phase = PHASE_TURN_START
			_last_roll = {}
			_last_doubles = false
			_no_extra_turn = false
			_pending = {}
			_pending_trade = {}
			consecutive_doubles = 0
			return _admin_ok(op, params)
		_:
			return _admin_fail("unknown admin op %s" % op)

## The seat that is genuinely WAITING on a decision right now — NOT just any
## pid with nonzero legal_actions (the turn holder always has management
## actions like roll/build, which would wrongly shadow a waiting recipient /
## auction bidder). Priority: pending trade recipient > auction bidder > turn
## holder. Returns -1 when nothing is awaiting input (e.g. END_GAME).
func _admin_decision_holder() -> int:
	if phase == PHASE_END_GAME or players.size() == 0:
		return -1
	if _pending_trade.size() != 0:
		return _pending_trade.get("recipient", -1)
	if phase == PHASE_AUCTION:
		return _pending.get("bidder", -1)
	return turn_player

## Run the current decision holder's legal intent through the engine (the
## "unblocking" path). Records an admin_override event after a successful submit.
func _admin_submit_for_holder(action: String, params: Dictionary, tag: String) -> Dictionary:
	var h: int = _admin_decision_holder()
	if h == -1:
		return _admin_fail("no active decision")
	var res: Dictionary = submit_intent(h, action, params)
	if res.get("ok", false):
		log.append("admin_override", {"op": tag, "action": action, "params": params})
		return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
	return res

func _admin_fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "legal": [], "events": []}

func _admin_ok(op: String, params: Dictionary) -> Dictionary:
	log.append("admin_override", {"op": op, "params": params})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries()}

# --- Phase 4: SNAPSHOT (export/import full engine state, spec §4.C) ---
## Serialize the entire authoritative state to plain JSON-able dictionaries:
## settings, players, phase, pending, houses, mortgaged, decks (remaining
## order), RNG seed, and the event log — enough to restore "this exact state".
func to_snapshot() -> Dictionary:
	var players_d: Array = []
	for p in players:
		players_d.append({
			"name": p.name, "token_id": p.token_id,
			"money": p.money, "position": p.position,
			"in_jail": p.in_jail, "jail_turns": p.jail_turns,
			"bankrupt": p.bankrupt,
			"get_out_of_jail_cards": p.get_out_of_jail_cards,
			"tiles": p.owned_tiles(),
		})
	var decks_d: Dictionary = {}
	for kind in decks:
		decks_d[kind] = decks[kind].cards(kind)
	var names: Array = []
	for p in players:
		names.append(p.name)
	return {
		"settings": settings.to_data(),
		"names": names,
		"players": players_d,
		"phase": phase,
		"turn_player": turn_player,
		"consecutive_doubles": consecutive_doubles,
		"last_roll": _last_roll,
		"last_doubles": _last_doubles,
		"no_extra_turn": _no_extra_turn,
		"card_depth": _card_depth,
		"pending": _pending,
		"pending_trade": _pending_trade,
		"houses": _houses,
		"mortgaged": _mortgaged,
		"decks": decks_d,
		"log": log.entries(),
	}

## Rebuild a fresh authoritative engine from a snapshot. Uses the engine's
## standard setup (board/cards/settings) then overwrites every live member.
func from_snapshot(d: Dictionary):
	var E = load("res://core/engine.gd")
	var e = E.new()
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	s.from_data(d.get("settings", {}))
	var names: Array = d.get("names", [])
	e.setup(s, names)
	e._restore_from_snapshot(d)
	return e

func _restore_from_snapshot(d: Dictionary) -> void:
	phase = d.get("phase", PHASE_TURN_START)
	turn_player = int(d.get("turn_player", 0))
	consecutive_doubles = int(d.get("consecutive_doubles", 0))
	_last_roll = d.get("last_roll", {})
	_last_doubles = bool(d.get("last_doubles", false))
	_no_extra_turn = bool(d.get("no_extra_turn", false))
	_card_depth = int(d.get("card_depth", 0))
	_pending = d.get("pending", {})
	_pending_trade = d.get("pending_trade", {})
	_houses = d.get("houses", {})
	_mortgaged = (d.get("mortgaged", []) as Array).duplicate()
	var pdata: Array = d.get("players", [])
	for i in pdata.size():
		if i >= players.size(): break
		var pd: Dictionary = pdata[i]
		var pp = players[i]
		pp.name = pd.get("name", pp.name)
		# token_id is per-piece identity (survives player removal); must be
		# serialized explicitly or a shifted survivor gets the wrong index token.
		pp.token_id = pd.get("token_id", pp.token_id)
		pp.money = int(pd.get("money", pp.money))
		pp.position = int(pd.get("position", pp.position))
		pp.in_jail = bool(pd.get("in_jail", false))
		pp.jail_turns = int(pd.get("jail_turns", 0))
		pp.bankrupt = bool(pd.get("bankrupt", false))
		pp.get_out_of_jail_cards = int(pd.get("get_out_of_jail_cards", 0))
		pp._owned = (pd.get("tiles", []) as Array).duplicate()
	var decks_d: Dictionary = d.get("decks", {})
	for kind in decks_d:
		if decks.has(kind):
			decks[kind]._decks[kind] = (decks_d[kind] as Array).duplicate()
	if settings.rng_seed != 0:
		rng.seed_rng(settings.rng_seed)
	log.clear()
	var entries: Array = d.get("log", [])
	for entry in entries:
		log._entries.append(entry as Dictionary)
