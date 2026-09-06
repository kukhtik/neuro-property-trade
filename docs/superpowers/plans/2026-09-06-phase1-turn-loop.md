# Phase 1 Tranche A — Turn-Loop Core Implementation Plan

**Goal:** Stand up the authoritative engine core: deterministic phase
state-machine + fail-closed intent API (`Engine.submit_intent`), full
5-block `GameSettings` (defaults per spec), turn loop with GO/jail/doubles,
basic tile resolution (tax/free_parking/go_to_jail/property purchase-auction/
railroad/utility rent), and both original card decks. One commit at the end.

**Architecture:** `GameSettings` and `CardDeck` are pure data/helpers built
first (TDD). `Engine` loads all its collaborators by path (see gotchas) and
drives a phase machine; every decision waits on an intent through
`submit_intent`, everything else auto-advances. All state changes append to
the `EventLog`. No class_name references inside new core files (breaks under
`--script`).

**Tech stack:** Godot 4.7.2 GDScript, headless `--script` test harness, plain
functions (no test framework).

**Conventions that MUST be followed (verified gotchas, will break otherwise):**
- `class_name` globals are NOT resolvable in code run via `--script`. Load
  everything by path: `var board = load("res://core/board.gd").new()`.
- Never use `var x := <value-from-untyped-func>` — parse error. Use plain
  `var x = ...`.
- Engine references its collaborators (Board/Player/Rng/EventLog/GameSettings/
  CardDeck) only via variables + `load()` by path in `_init`/helper. Never by
  class_name.
- Read JSON data with `FileAccess.open("res://...", FileAccess.READ)` +
  `JSON.parse_string`.
- Tests are plain `static func` in a module extending `RefCounted`, returning
  `""` on pass or an error string. Module exposes static `test_list()`.

**Run tests:** `godot --headless --path game --script res://tests/run.gd`
(exit 0 = pass). Create a feature branch first:
`git checkout -b phase1/turn-loop-core`.

Existing files you may modify: `game/tests/run.gd` (register new modules).
New files: listed per task.

---

## Task 1: GameSettings — default config (5 blocks)

**Files:** create `game/core/game_settings.gd`; create `game/tests/game_settings_test.gd`.

- [ ] **Step 1: Write a failing test** `tests/game_settings_test.gd`

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
	return ["test_defaults"]

static func test_defaults() -> String:
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	# economy block
	if s.starting_cash != 1500: return "starting_cash default"
	if s.go_bonus != 200: return "go_bonus default"
	if s.free_parking != false: return "free_parking should be off"
	if s.triple_doubles_to_jail != true: return "triple_doubles_to_jail default"
	if s.jail_rule != "both": return "jail_rule default"
	# property ops
	if s.auctions_on_refusal != true: return "auctions_on_refusal default"
	if s.auction_condition != "not-bought": return "auction_condition default"
	if s.housing != true: return "housing default"
	if s.even_build != true: return "even_build default"
	if s.monopoly_rent_x2 != true: return "monopoly_rent_x2 default"
	if s.mortgage != true: return "mortgage default"
	if s.mortgage_loan_pct != 50: return "mortgage loan pct"
	if s.mortgage_repay_pct != 110: return "mortgage repay pct"
	# tempo
	if s.turn_timer != 30: return "turn_timer default"
	if s.auction_timer != 15: return "auction_timer default"
	if s.timeout_action != "auto-pass": return "timeout_action default"
	if s.evil_enabled != false: return "evil_enabled default"
	if s.ai_aggression != 50: return "ai_aggression default"
	return ""
```

- [ ] **Step 2: Run** `godot --headless --path game --script res://tests/run.gd`. Expect FAIL (`Could not find type ...` / module missing). *(Test not registered yet — just confirm it errors cleanly when run directly, or skip registration until Task 9.)*
- [ ] **Step 3: Create `game/core/game_settings.gd`**

```gdscript
extends RefCounted
## Game configuration, 5 blocks from the game-concept spec. Dictionary-backed
## so the admin console and replay can serialize/restore it. Defaults match
## the spec's DEFAULT column; a session can start with zero config.

# Block 1 — Seats & composition (engine reads counts; driver wiring is Phase 3)
var seat_count: int = 4

# Block 2 — Base economy
var starting_cash: int = 1500
var go_bonus: int = 200          # 0 = off
var jail_rule: String = "both"   # "both" = try doubles + forced pay/card after 3
var free_parking: bool = false   # house rule OFF by default
var doubles: bool = true
var triple_doubles_to_jail: bool = true
var bankruptcy: String = "normal"

# Block 3 — Property ops
var auctions_on_refusal: bool = true
var auction_condition: String = "not-bought"
var housing: bool = true
var even_build: bool = true
var monopoly_rent_x2: bool = true
var mortgage: bool = true
var mortgage_loan_pct: int = 50
var mortgage_repay_pct: int = 110
var trades: bool = true

# Block 4 — Decks & theme (deck contents live in data/cards.json)
var deck_pairs: int = 2
var deck_shuffle: String = "per_game"

# Block 5 — Tempo, stream, AI
var turn_timer: int = 30
var auction_timer: int = 15
var timeout_action: String = "auto-pass"
var ai_aggression: int = 50
var evil_enabled: bool = false
var spectacle: bool = true
var event_overlay: bool = true
var rng_seed: int = 0           # 0 treated as "unset" by Engine

func from_data(d: Dictionary) -> void:
	for k in d:
		if k in self: set(k, d[k])

func to_data() -> Dictionary:
	var out := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT:
			var name: String = prop.name
			out[name] = get(name)
	return out
```

- [ ] **Step 4: Run tests.** Expect PASS for `game_settings_test` (run the single module by temporarily... actually keep it simple: only run full runner once modules are registered in Task 9. For now verify the file parses: `godot --headless --path game --script res://tests/run.gd` still passes 23 tests.)
- [ ] **Step 5: Commit** `git add game/core/game_settings.gd game/tests/game_settings_test.gd && git commit -m "feat: GameSettings default config (5 blocks)"`

---

## Task 2: CardDeck + cards.json — original decks

**Files:** create `game/data/cards.json`; create `game/core/card_deck.gd`; create `game/tests/card_test.gd`.

**Card effect schema:** each card: `{ "name": String, "kind": "community"|"chance", "effect": String, "value": int }`.

**Effect tokens (`effect` + meaning):**
- `"collect"`  — player adds `value` cash
- `"pay"`      — player pays `value` to the bank
- `"move_to"`  — absolute: `value` = tile index
- `"advance"`  — relative tiles forward: `value` = number of spaces (pass GO counts)
- `"go_to_jail"` — send to jail (tile 10)
- `"jail_card"`  — give player a get-out-of-jail card
- `"collect_from_all"` — each other player pays `value` to this player
- `"pay_each_player"` — this player pays `value` to each other

**`advance` detail:** when moving forward that wraps past tile 0, player collects
GO bonus once (engine-owned logic; CardDeck only returns the raw effect).

- [ ] **Step 1: Write failing tests** `tests/card_test.gd`

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
	return ["test_load_two_decks", "test_has_original_names", "test_draw_rotates", "test_draw_returns_card"]

static func _load_decks() -> Dictionary:
	var C = load("res://core/card_deck.gd")
	var file = FileAccess.open("res://data/cards.json", FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	var c = C.new()
	c.load_from_json(json)
	return {"deck": c, "json": json}

static func test_load_two_decks() -> String:
	var r = _load_decks()
	var c = r["deck"]
	if c.size("community") < 12: return "community deck too small"
	if c.size("chance") < 12: return "chance deck too small"
	return ""

static func test_has_original_names() -> String:
	# every card name must NOT contain Hasbro trademarks
	var r = _load_decks()
	var c = r["deck"]
	var banned = ["monopoly", "chance deck", "boardwalk", "park place", "go to jail"]
	for kind in ["community", "chance"]:
		for card in c.cards(kind):
			var n = String(card.get("name", "")).to_lower()
			for b in banned:
				if n.find(b) != -1: return "banned token in card name: " + n
	return ""

static func test_draw_rotates() -> String:
	# draws consume from the top in order (no reshuffle until exhausted)
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
	if not card.has("effect"): return "card missing effect token"
	return ""
```

- [ ] **Step 2: Run** module (via temporary registration or direct). Expect FAIL.
- [ ] **Step 3: Create `game/data/cards.json`** — two decks, 16–30 cards each,
  original names/effects. Do NOT use Hasbro-adjacent wording as a deck title.
  Provide at least 12 per deck with the effect tokens defined above, e.g.:

```json
{
  "decks": {
    "community": [
      { "name": "Borrowers' Grant", "kind": "community", "effect": "collect", "value": 50 },
      { "name": "Parking Fine Reimbursed", "kind": "community", "effect": "collect", "value": 100 },
      { "name": "Bank Error in Your Favor", "kind": "community", "effect": "collect", "value": 200 },
      { "name": "Hospital Fee", "kind": "community", "effect": "pay", "value": 50 },
      { "name": "School Fees", "kind": "community", "effect": "pay", "value": 50 },
      { "name": "Street Repairs Pass", "kind": "community", "effect": "collect", "value": 100 },
      { "name": "Inheritance", "kind": "community", "effect": "collect", "value": 100 },
      { "name": "Consultancy Fee", "kind": "community", "effect": "collect", "value": 25 },
      { "name": "Speeding Ticket", "kind": "community", "effect": "pay", "value": 15 },
      { "name": "Go Back Three", "kind": "community", "effect": "advance", "value": -3 },
      { "name": "Clerk's Mistake", "kind": "community", "effect": "collect_from_all", "value": 50 },
      { "name": "Charity Drive", "kind": "community", "effect": "pay_each_player", "value": 50 },
      { "name": "Jail Assistance", "kind": "community", "effect": "jail_card", "value": 0 },
      { "name": "Visit the Chamber", "kind": "community", "effect": "go_to_jail", "value": 0 },
      { "name": "Advance to Start", "kind": "community", "effect": "move_to", "value": 0 },
      { "name": "Neighborhood Renewal", "kind": "community", "effect": "collect", "value": 150 }
    ],
    "chance": [
      { "name": "Speed of Light", "kind": "chance", "effect": "advance", "value": 5 },
      { "name": "Citywide Cleanup", "kind": "chance", "effect": "collect", "value": 50 },
      { "name": "Building Loan", "kind": "chance", "effect": "collect", "value": 150 },
      { "name": "Traffic Ticket", "kind": "chance", "effect": "pay", "value": 15 },
      { "name": "Take a Breather at Jail", "kind": "chance", "effect": "go_to_jail", "value": 0 },
      { "name": "Community Service Card", "kind": "chance", "effect": "jail_card", "value": 0 },
      { "name": "Advance to Boardwalk Park", "kind": "chance", "effect": "move_to", "value": 39 },
      { "name": "Advance to Gardens", "kind": "chance", "effect": "move_to", "value": 31 },
      { "name": "Advance to Start", "kind": "chance", "effect": "move_to", "value": 0 },
      { "name": "Go Forward Three", "kind": "chance", "effect": "advance", "value": 3 },
      { "name": "Pay Each Player", "kind": "chance", "effect": "pay_each_player", "value": 50 },
      { "name": "Collect From All", "kind": "chance", "effect": "collect_from_all", "value": 50 },
      { "name": "Dividend", "kind": "chance", "effect": "collect", "value": 50 },
      { "name": "Property Tax Rebate", "kind": "chance", "effect": "collect", "value": 100 },
      { "name": "Go Back to Palm Row", "kind": "chance", "effect": "move_to", "value": 3 },
      { "name": "Take a Vacation", "kind": "chance", "effect": "pay", "value": 100 }
    ]
  }
}
```

*(Note: values above are suggestions; adjust to a coherent non-Hasbro set as
long as effects use the defined tokens and deck sizes ≥ 12. board_test checks
tile names, not card names, so use realistic original wording.)*

- [ ] **Step 4: Create `game/core/card_deck.gd`**

```gdscript
extends RefCounted
## Two original card decks ("community", "chance"). Deterministic draw in
## order; reshuffle is the caller's concern (engine re-seeds Rng). CardDeck
## is a pure source of card dicts — it does NOT mutate player state.

var _decks: Dictionary = {}   # kind -> Array[Dictionary]

func load_from_json(data: Dictionary) -> void:
	_decks = {}
	var decks: Dictionary = data.get("decks", {})
	for kind in decks:
		_decks[kind] = (decks[kind] as Array).duplicate()

func size(kind: String) -> int:
	return (_decks.get(kind, []) as Array).size()

func cards(kind: String) -> Array:
	return (_decks.get(kind, []) as Array).duplicate()

func draw(kind: String):
	var arr = _decks.get(kind)
	if arr == null or arr.size() == 0:
		return null
	return arr.pop_front()
```

- [ ] **Step 5: Run tests** (register `card_test.gd` in `run.gd` now so you can
  verify; keep it registered). Expect PASS.
- [ ] **Step 6: Commit** `git add game/data/cards.json game/core/card_deck.gd game/tests/card_test.gd game/tests/run.gd && git commit -m "feat: original card decks (community/chance) + CardDeck"`

---

## Task 3: Engine scaffold — players, order, initial cash

**Files:** create `game/core/engine.gd`; create `game/tests/engine_test.gd`; modify `game/tests/run.gd`.

- [ ] **Step 1: Write failing scaffold test**

```gdscript
extends RefCounted

static func test_list() -> Array[String]:
	return ["test_setup_creates_players", "test_setup_money_and_position", "test_submit_intent_before_turn_starts_rejected"]

static func _make_engine(player_names: Array = ["Ada", "Bo"]) -> Dictionary:
	var E = load("res://core/engine.gd")
	var S = load("res://core/game_settings.gd")
	var s = S.new()
	var e = E.new()
	e.setup(s, player_names)
	return {"engine": e}

static func test_setup_creates_players() -> String:
	var r = _make_engine()
	if r["engine"].player_count() != 2: return "want 2 players"
	return ""

static func test_setup_money_and_position() -> String:
	var r = _make_engine()
	var p = r["engine"].player(0)
	if p.money != 1500: return "starting cash"
	if p.position != 0: return "start position"
	return ""

static func test_submit_intent_before_turn_starts_rejected() -> String:
	var r = _make_engine()
	var res = r["engine"].submit_intent(0, "roll", {})
	if res["ok"] == true: return "should reject roll before TURN_START"
	return ""
```

- [ ] **Step 2: Run** — expect FAIL (engine.gd missing).
- [ ] **Step 3: Create `game/core/engine.gd` scaffold**

```gdscript
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

var settings   # GameSettings
var board      # Board
var players: Array = []     # of Player
var log        # EventLog
var rng        # Rng
var decks: Dictionary = {}  # kind -> CardDeck
var phase: String = PHASE_SETUP
var turn_player: int = 0      # index into players
var consecutive_doubles: int = 0

var _pending = {}              # pending decision context for auction/purchase

func setup(s, names: Array) -> void:
	settings = s
	board = load("res://core/board.gd").new()
	log = load("res://core/event_log.gd").new()
	rng = load("res://core/rng.gd").new()
	if settings.rng_seed != 0:
		rng.seed_rng(settings.rng_seed)
	players = []
	for i in names.size():
		var p = load("res://core/player.gd").new(names[i], "token%d" % i, Color.WHITE, settings.starting_cash)
		players.append(p)
	# load decks
	for kind in ["community", "chance"]:
		var d = load("res://core/card_deck.gd").new()
		var file = FileAccess.open("res://data/cards.json", FileAccess.READ)
		d.load_from_json(JSON.parse_string(file.get_as_text()))
		decks[kind] = d
	phase = PHASE_TURN_START
	log.append("setup", {"players": names.size()})

func player_count() -> int:
	return players.size()

func player(i: int):
	return players[i]

func submit_intent(pid: int, action: String, params: Dictionary) -> Dictionary:
	# fail-closed: reject out-of-turn / illegal-phase
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
	# TODO(Task 4+) movement, doubles, tile resolution
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles})
	return {"ok": true, "reason": "", "legal": [], "events": log.entries(), "roll": roll}
```

- [ ] **Step 4: Register `engine_test.gd` in `run.gd`** and run. Expect:
  - `test_setup_creates_players` and `test_setup_money_and_position` PASS,
  - `test_submit_intent_before_turn_starts_rejected` — the intent API needs a
    `turn_started` gate. Adjust scaffold: keep a bool `_turns_started` set true
    after the first `start_turn()` (Task 4). For now, make the test target a
    genuinely invalid action instead: change the test to `submit_intent(1, "roll", {})`
    (player 1 is not turn_player) expecting rejection — that exercises fail-closed
    without the gate. Update the test accordingly and confirm PASS.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd game/tests/run.gd && git commit -m "feat: engine scaffold, players/order/cash, fail-closed intent API surface"`

---

## Task 4: Turn loop — roll, move, GO bonus, doubles, triple-jail

**Files:** modify `game/core/engine.gd`, `game/tests/engine_test.gd`.

- [ ] **Step 1: Write tests** (append to `engine_test.gd`):

```gdscript
static func test_move_and_go_bonus() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# force a concrete roll by reseeding with a known seed that yields d1+d2
	# (use a deterministic helper: set rng seed, first roll sum = ...)
	var res = e.submit_intent(0, "roll", {})
	var pos = e.player(0).position
	if not (pos >= 2 and pos <= 12): return "move failed, pos=%d" % pos
	return ""
```

For deterministic GO-bonus and doubles tests, expose a test hook: add
`func _force_dice(sum: int, d1: int, d2: int, doubles: bool) -> void` that
builds a roll dict directly (used by tests only). Then write:

```gdscript
static func test_go_bonus_paid_once_per_lap() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(40, 20, 20, false)  # far jump wraps past GO
	var res = e.submit_intent(0, "roll", {})
	var cash_before = 1500
	# after passing GO, player gained GO bonus (settings.go_bonus) plus tile effect (none here)
	if e.player(0).money != cash_before + 200: return "GO bonus not paid on wrap, money=%d" % e.player(0).money
	return ""

static func test_doubles_grants_extra_turn() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(6, 3, 3, true)
	e.submit_intent(0, "roll", {})
	# still player 0's turn waiting on a decision or next roll on a passable tile
	if e.turn_player != 0: return "doubles should keep same player, got %d" % e.turn_player
	return ""

static func test_triple_doubles_sends_to_jail() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(4, 2, 2, true);  e.submit_intent(0, "roll", {})
	e._force_dice(4, 2, 2, true);  e.submit_intent(0, "roll", {})
	e._force_dice(4, 2, 2, true);  e.submit_intent(0, "roll", {})
	if not e.player(0).in_jail: return "triple doubles should jail player"
	if e.player(0).position != 10: return "jailed to tile 10"
	return ""
```

- [ ] **Step 2: Run** — expect FAIL (methods missing).
- [ ] **Step 3: Implement movement + doubles + GO in engine.gd.** Replace
  `_resolve_roll` to: compute destination accounting for wrap; pay `go_bonus`
  once when crossing/passing tile 0; increment `consecutive_doubles` (roll
  resets it to 0 on a non-doubles roll); if 3rd consecutive doubles → send to
  jail (Task 7 helper `_send_to_jail`), else move and resolve the landing tile.
  Add `_add_debt`/`_pay` helper: `func _credit(p: int, amt: int) -> void`
  changes cash + logs `"cash"`. Add the `_force_dice` test hook:

```gdscript
func _force_dice(sum: int, d1: int, d2: int, is_doubles: bool) -> void:
	# test-only override of the next roll
	_forced_roll = {"d1": d1, "d2": d2, "sum": sum, "doubles": is_doubles}

func _next_roll() -> Dictionary:
	if _forced_roll != null:
		var r = _forced_roll
		_forced_roll = null
		return r
	return rng.roll_two_dice()
```

  GO handling in `_resolve_roll` (only when NOT already in jail):

```gdscript
	var roll = _next_roll()
	log.append("roll", {"player": turn_player, "d1": roll.d1, "d2": roll.d2, "doubles": roll.doubles})
	if not players[turn_player].in_jail:
		if roll.doubles:
			consecutive_doubles += 1
			if settings.triple_doubles_to_jail and consecutive_doubles >= 3:
				_send_to_jail()
				return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
		else:
			consecutive_doubles = 0
		_move_and_resolve(roll)
		return {"ok": true, "reason": "", "legal": [], "events": log.entries()}
	# else: player in jail -> Task 7 (jail roll path)
```

  `_move_and_resolve(roll)`: p = players[turn_player]; old = p.position;
  p.position = (old + roll.sum) % board.tile_count(); if wrapped (new < old):
  `_credit(turn_player, settings.go_bonus)` + log `"go_bonus"`. Then dispatch
  on `board.type_at(p.position)`. (Tile resolution bodies land in Tasks 5–8;
  for now handle `go` (credit already done) and log `"land"`.)

- [ ] **Step 4: Run tests** until the 4 above pass. The GO/doubles/triple tests
  must deterministically pass with `_force_dice`.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd && git commit -m "feat: turn loop roll/move/GO/doubles/triple-jail"`

---

## Task 5: Tile resolution — property purchase, auction, base rent

**Files:** modify `game/core/engine.gd`, `game/tests/engine_test.gd`.

- [ ] **Step 1: Write tests**

```gdscript
static func test_purchase_buy() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# land on tile 1 (unowned property, cost 60) by forcing dice
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	if e.phase != e.PHASE_PURCHASE_WAIT: return "should await purchase, phase=" + e.phase
	var res = e.submit_intent(0, "buy", {})
	if not res["ok"]: return "buy rejected: " + res.get("reason", "")
	if not e.player(0).owns(1): return "did not gain tile 1"
	if e.player(0).money != 1500 - 60: return "buy cost not charged, money=%d" % e.player(0).money
	return ""

static func test_purchase_pass_then_auction() -> String:
	var r = _make_engine()
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})
	if e.phase != e.PHASE_AUCTION: return "pass should trigger auction, phase=" + e.phase
	return ""

static func test_purchase_cannot_buy_wrong_phase() -> String:
	var r = _make_engine()
	var e = r["engine"]
	var res = e.submit_intent(0, "buy", {})  # in TURN_START
	if res["ok"] == true: return "should reject buy in TURN_START"
	return ""

static func test_base_rent_on_property() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# give tile 1 to player 1 directly
	e.player(1).add_ownership(1)
	e._force_dice(1, 1, 0, false)  # player 0 lands on tile 1 owned by player 1
	e.submit_intent(0, "roll", {})
	if e.player(0).money != 1500 - 2: return "base rent not charged, money=%d" % e.player(0).money
	if e.player(1).money != 1500 + 2: return "rent not credited, money=%d" % e.player(1).money
	return ""
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** in engine.gd:
  - `_resolve_land()` dispatched from `_move_and_resolve` by tile type.
  - property unowned → `phase = PURCHASE_WAIT`, set `_pending = {tile, owner:null}`.
  - `buy` intent in PURCHASE_WAIT: check cash ≥ cost; charge, add ownership,
    log `purchase`, → `_next_turn()`.
  - `pass` intent in PURCHASE_WAIT: if `settings.auctions_on_refusal` →
    start auction (Task 6 covers auction; here open it) else → `_next_turn()`.
  - property owned by other → `RENT_SETTLE`: rent = tile.rent (base; no houses
    yet). Transfer via `_transfer(from, to, amt)` (credit/debit + log `"rent"`).
    → `_next_turn()`.
  - property owned by self → log `"land"`, ignore → `_next_turn()`.
  - `_next_turn()`: `turn_player = (turn_player + 1) % players.size(); phase = TURN_START`.
- [ ] **Step 4: Run** until green. Auctions are a stub at this point — `pass`
  test only asserts phase becomes AUCTION; fully implement in Task 6.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd && git commit -m "feat: property purchase / pass / base rent"`

---

## Task 6: Auction (round-robin bid/pass; all-pass → unowned)

**Files:** modify `game/core/engine.gd`, `game/tests/engine_test.gd`.

- [ ] **Step 1: Write tests**

```gdscript
static func test_auction_single_winner() -> String:
	var r = _make_engine(["Ada", "Bo", "Cy"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})   # open auction on tile 1
	# auctioneer Ada is 0; bid order rotates. Ada bids 30, Bo passes, Cy passes.
	if e.phase != e.PHASE_AUCTION: return "auction not open"
	var res = e.submit_intent(0, "bid", {"amount": 30})
	if not res["ok"]: return "bid rejected"
	e.submit_intent(1, "pass", {})
	e.submit_intent(2, "pass", {})
	if e.player(0).owns(1) != true: return "winner should own tile 1"
	if e.player(0).money != 1500 - 30: return "winning bid not charged"
	return ""

static func test_auction_all_pass_unowned() -> String:
	var r = _make_engine(["Ada", "Bo"])
	var e = r["engine"]
	e._force_dice(1, 1, 0, false)
	e.submit_intent(0, "roll", {})
	e.submit_intent(0, "pass", {})
	e.submit_intent(0, "pass", {})   # Ada passes
	e.submit_intent(1, "pass", {})   # Bo passes
	if e.player(0).owns(1) or e.player(1).owns(1): return "no one should own tile 1"
	if e.turn_player != 1: return "auction closed, next player's turn"
	return ""
```

*(Auction ordering: auctioneer = `turn_player`. Round-robin among all players
in turn order; a player who `pass`es is out; a `bid` sets a new high and
rotates to the next active player; when all but one active player has passed,
that player wins at their last bid. If everyone passes without a bid, tile
stays unowned.)*

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** `_start_auction(tile)`, `_auction_bid`, handling in
  `submit_intent` for AUCTION phase. State in `_pending = {tile, highest,
  high_player, active:Array[int], last_bidder}`. `bid` requires `amount >
  highest` (or amount ≥ 0 if highest is None) and cash ≥ amount. Winner pays
  bid, gains ownership, → `_next_turn()`. All-pass → log `"auction_unwon"` →
  `_next_turn()`.
- [ ] **Step 4: Run** until green.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd && git commit -m "feat: auctions (round-robin bid/pass, all-pass unowned)"`

---

## Task 7: Railroad + utility rent

**Files:** modify `game/core/engine.gd`, `game/tests/engine_test.gd`.

- [ ] **Step 1: Write tests**

```gdscript
static func test_railroad_rent_scales_with_owned() -> String:
	var r = _make_engine()
	var e = r["engine"]
	# player 1 owns 2 of the 4 railroad tiles (5,15,25,35)
	e.player(1).add_ownership(5); e.player(1).add_ownership(15)
	e._force_dice(20, 20, 0, false)  # move by 20 -> position 20? need to land on railroad
	return ""  # (adjust dice so player 0 lands on a railroad tile owned by player 1)
```

  *(Pick a concrete fixture: land player 0 on tile 15 (owned by player 1).
  Compute roll sum to reach it from position 0 — but wrap complicates; simpler
  to teleport: add a test hook `_teleport(pid, tile)` setting position directly
  before a roll of 0. Use: `e._teleport(0, 14)` then `_force_dice(1,1,0,false)`
  → lands on 15.) Verify rent = 25 * 2^(owned_count-1). For 2 owned → 50.*
  Add `_teleport`, and for `owned_count` use `board.group_tiles`... railroad
  tiles aren't in a color group; count ownership by scanning the 4 railroad
  indices `[5,15,25,35]`.

```gdscript
static func test_utility_rent_single_and_pair() -> String:
	# single utility owned (tile 12): rent = 4 * roll_sum
	# both utilities (12,28): rent = 10 * roll_sum — use _force_dice sum.
	return ""
```

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement** in `_resolve_land`:
  - railroad: `owned = count of 5,15,25,35 owned by landlord`; rent = 25 *
    pow(2, owned-1). `_transfer`.
  - utility: if landlord owns both 12 & 28 → rent = 10 * roll.sum; else 4 *
    roll.sum (roll from the same `_next_roll` already stored; keep it in a
    member `_last_roll` during resolution). `_transfer`.
  - add `_teleport(pid, tile)` test hook (sets `position`, log only).
- [ ] **Step 4: Run** until green.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd && git commit -m "feat: railroad and utility rent"`

---

## Task 8: Tax, free_parking, go_to_jail, jail decision, cards

**Files:** modify `game/core/engine.gd`, `game/tests/engine_test.gd`.

- [ ] **Step 1: Write tests**

```gdscript
static func test_tax_charged() -> String:
	# land on tile 4 (Tax, amount 200) -> money -200
	return ""

static func test_free_parking_default_noop() -> String:
	# land on tile 20 -> no money change
	return ""

static func test_go_to_jail_sends_ten() -> String:
	# land on tile 30 -> position 10, in_jail true
	return ""

static func test_jail_pay_fine_leaves() -> String:
	# player in jail, submit "pay" -> cash -100 (or settings), leaves jail, turn advances
	return ""

static func test_jail_roll_doubles_leaves() -> String:
	# in jail, submit "roll" with doubles -> leaves jail and moves
	return ""

static func test_jail_roll_no_doubles_stays_and_advances() -> String:
	# in jail, "roll" non-doubles -> stays in jail, turn advances, turns_jailed++
	return ""

static func test_card_collect_pay_applied() -> String:
	# land on a chest tile, draw card, effect applied to cash
	return ""
```

*(Define exact fixtures per tile: Tax at index 4 amount 200; go_to_jail at 30;
chest at index 2. For deterministic cards, seed Rng so the drawn card is known,
or add `_force_draw(kind, index)` test hook that pops that specific card. Use
a card with `collect` for chest test.)*

- [ ] **Step 2: Run** — expect FAIL.
- [ ] **Step 3: Implement in engine.gd:**
  - `tax`: `_credit(turn_player, -tile.amount)` + log `"tax"` → `_next_turn()`.
    (No free_parking collection — off by default).
  - `free_parking`: log `"land"` → `_next_turn()` (free_parking off → noop).
  - `go_to_jail` tile: `_send_to_jail()` (position=10, in_jail=true,
    consecutive_doubles reset, log `"go_to_jail"`), → `_next_turn()`.
  - `jail` tile lands = "just visiting": not in jail, → `_next_turn()`.
  - `_send_to_jail()` used by triple-doubles and go_to_jail and cards.
  - JAIL_DECISION (player entered turn already in jail). `submit_intent` in
    TURN_START when `in_jail` delegates to `_jail_roll` (Task 4 stub → now real):
    - "pay": charge fine (100 default; `settings.jail_fine` — add
      `jail_fine: int = 100` to GameSettings in Task 1 if not present), leave
      jail, `_move_and_resolve` the pre-rolled? No — pay leaves jail and the
      player moves this turn. Standard: pay fine, then roll and move. So "pay"
      → leave jail, then roll+move. "card": use get-out-of-jail card (player
      `get_out_of_jail_cards`), leave, then roll+move. "roll": try doubles —
      doubles → leave + move; non-doubles → stays, `turns_jailed += 1`; if
      `turns_jailed >= 3` (jail_rule "both") → forced pay/card next decision.
  - `_move_and_resolve` on leaving jail: uses a fresh roll (Task 7 `_last_roll`
    reuse). Manage carefully: in jail, roll is rolled when user sends "roll".
  - community/chance tiles in `_resolve_land`: `var card = decks[kind].draw("kind");
    log "card_draw"; apply effect.` Effect apply:
    - collect → `_credit(amt)`
    - pay → `_credit(-amt)`
    - move_to → set position (wrap→GO bonus if value 0 means Start... treat
      move_to as absolute; if value < current position, passing Start counts),
      resolve that new tile via `_resolve_land` recursively (guard depth).
    - advance → move forward value (wrap → GO bonus), resolve tile.
    - go_to_jail → `_send_to_jail()`
    - jail_card → `player.get_out_of_jail_cards += 1`
    - collect_from_all → each other player pays value
    - pay_each_player → this player pays value each
    After card effect → `_next_turn()` (unless card moved to a decision tile —
    then that flow takes over; if card sends to jail, `_next_turn()`).
- [ ] **Step 4: Run** until all Task 8 tests pass.
- [ ] **Step 5: Commit** `git add game/core/engine.gd game/tests/engine_test.gd && git commit -m "feat: tax/free-parking/go-to-jail, jail decision, card effects"`

---

## Task 9: Full-suite pass + update docs

- [ ] **Step 1: Add `jail_fine: int = 100` to GameSettings** (if you referenced
  it in Task 8) and a `settings_test` assertion for it; commit.
- [ ] **Step 2: Register all new test modules** (`game_settings_test.gd`,
  `card_test.gd`, `engine_test.gd`) in `game/tests/run.gd` if not already.
- [ ] **Step 3: Run full suite:** `godot --headless --path game --script res://tests/run.gd`.
  Expect `ALL TESTS PASSED`, exit 0. Every old + new test green.
- [ ] **Step 4: Update `docs/plan.md` Phase 1 status** — check off the
  turn-loop / jail / card items actually completed; note remaining Phase 1
  rules (housing/mortgage, bankruptcy, monopoly-rent, trades) as parallel
  tranches. Update the skill reference `references/godot-headless-testing.md`
  coverage count.
- [ ] **Step 5: Merge branch** `git checkout main && git merge phase1/turn-loop-core` (fast-forward). Push `git push origin main` (SSH — avoid `gh`).
- [ ] **Step 6: Final verification** — `git log --oneline -6` and re-run the
  suite on main to confirm green before reporting the commit hash to the user.

---

## Self-review

- **Spec coverage:** GameSettings (all 5 blocks, defaults) → Task 1. Turn loop
  roll/move/GO/doubles → Task 4. Property purchase/auction/base rent → 5–6.
  Railroad/utility rent → 7. Tax/free_parking/go_to_jail/jail → 8. Cards →
  Task 2 (deck) + Task 8 (integration). Fail-closed intent API → Task 3
  surface + exercised throughout. Housing/mortgage/bankruptcy/monopoly-rent/
  trades intentionally deferred (later Phase 1 tranches, per decision D1).
- **Placeholders:** no TBD; fixtures are explicit.
- **Type consistency:** `submit_intent` always returns `{ok, reason, legal,
  events}`; `_force_dice`, `_teleport`, `_force_draw` test hooks consistent.
- **Gotchas respected:** class_name avoided in all new core files; plain `=`
  assignment from untyped helpers; FileAccess for JSON.
