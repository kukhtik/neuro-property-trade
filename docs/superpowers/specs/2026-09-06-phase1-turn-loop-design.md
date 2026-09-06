# Phase 1 Tranche A — Turn-Loop Core + GameSettings (Design)

Date: 2026-09-06 · Owner: profile `monopoly` · Status: APPROVED
Related: `docs/plan.md`, `docs/specs/game-concept-spec.md` (DEFAULT blocks).

## Goal

Build the authoritative rules engine's core: a deterministic phase
state-machine + fail-closed intent API, wired to full 5-block `GameSettings`
(defaults per spec), covering the turn loop, GO/jail/doubles, basic tile
resolution, auctions, and both card decks. One commit. Subsequent Phase 1
rules (housing/mortgage, bankruptcy, monopoly-rent, trades) are parallelized
in later tranches.

## Architecture

`Engine` (core/engine.gd) is the single authoritative object. It owns
`Board`, `Player[]`, `Rng`, `EventLog`, `GameSettings`. All input enters via
`engine.submit_intent(player_id, action, params) -> Result`; nothing else
mutates state. Every state change is written to the EventLog. Intent API is
fail-closed: an invalid request in the current phase returns error + the list
of legal options and never executes.

## Components

### 1. GameSettings — core/game_settings.gd
Dictionary-backed, 5 blocks from the spec, defaults per the DEFAULT column.
`to_data()` / `from_data()` for serialization + replay. Settings-driven
values the engine reads: starting_cash, go_bonus (on/200), jail_rule (both),
free_parking (off), doubles (on), triple_doubles_to_jail (on), bankruptcy
(normal), auctions_on_refusal (on), auction_condition (not-bought), housing,
even_build, monopoly_rent_x2, mortgage + pcts, trades, deck_pairs, card
effects set, turn_timer (30s), auction_timer (15s), timeout_action
(auto-pass), rng_seed.

### 2. Engine phase machine (engine-level, one shared state)
SETUP → TURN_START → ROLL_RESOLVE → (tile handler) → END_TURN → next player.

Tile-resolution flows (sub-states via `pending_decision` field):
- property unowned → PURCHASE_WAIT (buy|pass→AUCTION)
- AUCTION: per-turn bid/pass round-robin; all-pass → awarded to no one
- property owned by other → RENT_SETTLE (auto; rent computed now w/o houses)
- railroad → RENT_SETTLE (25 × 2^(owned-1))
- utility → RENT_SETTLE (4× sum if own both, else 10× one)
- jail → JAIL_DECISION; go_to_jail → move to 10, set jail
- tax → auto pay; free_parking (off) → nothing; go → +GO_BONUS once per lap
- community/chance → draw card, CARD_WAIT; auto-effecting cards resolve;
  decision cards (go-to-jail) resolve through phase.

Doubles: doubles after roll → extra turn (unless landed in jail via go_to_jail).
3rd consecutive doubles → jail (state: consecutive_doubles).

Jail (rule "both"): on entry player may try doubles (up to 3 turns). While in
jail: options roll-doubles (leave on success, else spend turn) / pay fine /
use get-out-of-jail card. After 3 failed turns → must pay or use card. Auto
transitions keep engine always advancing.

### 3. Cards — core/card_deck.gd + data/cards.json
Two decks, original non-Hasbro names. Cards carry a typed `effect`:
move_to, move_amount (with relative/absolute + pass-go), collect, pay,
go_to_jail, get_out_of_jail_card, collect_from_all, pay_each_player,
advance_to_railroad/utility. Card draws flow through Rng. Deck reshuffle
per-game (settings).

### 4. Result object
`{ ok: bool, reason: String, legal: Array[String], events: Array[Dictionary],
   state_snapshot: Dictionary }`.

## Invariants
- Deterministic: all randomness via Rng seed; replay-from-log.
- Fail-closed intent: illegal action → no mutation, error lists legal opts.
- Auto-pass / auto-resolve so engine never stalls in a non-decision tile.
- No Hasbro trade dress; card names/effects original.

## Testing
- `engine_test.gd` + `card_test.gd` + `game_settings_test.gd` (headless,
  seeded). Covers: roll&move, GO bonus, taxes, doubles re-turn,
  triple→jail, purchase/pass→auction, auction all-pass, jail 4 paths,
  railroad/utility rent, card effects (each deck), fail-closed rejection.
- Runner: `godot --headless --path game --script res://tests/run.gd`.
