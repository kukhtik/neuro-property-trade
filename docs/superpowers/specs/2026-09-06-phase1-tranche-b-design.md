# Phase 1 Tranche B — Housing, Mortgage, Bankruptcy, Trades (Design)

Date: 2026-09-06 · Owner: profile `monopoly` · Status: APPROVED
Related: `docs/superpowers/specs/2026-09-06-phase1-turn-loop-design.md` (Tranche A
core), `docs/specs/game-concept-spec.md` (defaults), `docs/plan.md`.

## Goal

Finish Phase 1 remaining rules on the stable engine API: property-set/monopoly
rent ×2, houses/hotels with even-build, mortgage/unmortgage, bankruptcy with
asset transfer + winner detection, and player trades. All intents go through
the existing fail-closed `submit_intent`; every change is logged. Same headless
test conventions (load by path, no class_name, plain `=` for Variant returns).

## Rules to add (defaults per spec; all settings-backed)

1. **Property sets & monopoly rent ×2** (`settings.monopoly_rent_x2`, on).
   Owning all tiles of a color group, none mortgaged → rent = `rent_set`
   (already the doubled value in board.json) instead of `rent`.

2. **Houses/hotels** (`settings.housing`, on; `settings.even_build`, on).
   - Each property tile gains `"houses": [r1,r2,r3,r4,hotel_rent]` and
     `"house_cost"` in board.json.
   - `build_house(tile)` legal only when: player owns the full set, no tile in
     the set is mortgaged, and even-build holds (target tile's count ≤ min
     count in set — allows building the lowest). Max = 5 (4 houses + hotel).
     Cost = `house_cost`. Rent with houses: count≥1 → `houses[count-1]`.
   - `sell_house(tile)` refunds half `house_cost`, even-build (descending)
     enforced, min 0.

3. **Mortgage/unmortgage** (`settings.mortgage`, on; loan 50 / repay 110).
   - `mortgage_property(tile)`: owner, not already mortgaged, no houses on it
     (must sell houses first). Loan = 50% of `cost`. Mortgaged tiles collect no
     rent and break monopoly for the set.
   - `unmortgage_property(tile)`: repay 110% of `cost`.

4. **Bankruptcy** (`settings.bankruptcy`, "normal" = transfer-to-creditor).
   - Any payment that would leave a player with negative cash (rent, tax,
     auction, jail, card pay, trade) triggers insolvency: the insolvent
     player's properties (unmortgaged) + cash transfer to the creditor (the
     other party, or the bank when owed to the bank); player is removed
     (`bankrupt = true`, dropped from `players`/turn order). When one player
     remains → winner logged, phase = `PHASE_END_GAME` (new const).

5. **Trades** (`settings.trades`, on; window = any time, MVP: during the
   proposer's turn before roll).
   - `propose_trade(params: {to, give_tiles[], give_cash, want_tiles[],
     want_cash})` sets a pending offer. `respond_trade(params: {accept})`
     by the recipient resolves it. On accept, tiles + cash swap; mortgaged
     tiles transfer still mortgaged.

## Engine additions

- New const `PHASE_END_GAME`.
- Members: `_houses: Dictionary` (tile index → house count, engine-owned),
  `_mortgaged: Array` (tiles in mortgage), `_pending_trade: Dictionary`.
- New submit_intent actions (all in `PHASE_TURN_START` alongside `roll`, for
  the current player): `build_house`, `sell_house`, `mortgage_property`,
  `unmortgage_property`, `propose_trade`, `respond_trade`, plus keep `roll`.
- Helpers: `_owns_set(player, group) -> bool`, `_set_group(tile) -> String`,
  `_can_build(tile) -> String|""`, `_house_rent(tile) -> int`,
  `_go_bankrupt(player, creditor)`.

## Rent resolution order (owned-by-other, live in _move_and_resolve and
## _resolve_card_landing)
1. tile mortgaged → 0 rent.
2. houses > 0 → `houses[houses-1]`.
3. monopoly (full set, none mortgaged, `monopoly_rent_x2`) → `rent_set`.
4. else → `rent`.

## Testing

New test cases appended to engine_test.gd (and a house-rent table assert):
monopoly rent doubled; build requires full set + even-build; even-build blocks
uneven build; rent with 1..5 houses; sell refunds half; build blocked on
mortgaged set; mortgage blocks rent + breaks monopoly; unmortgage repays 110%;
bankruptcy transfers assets to creditor + removes player + winner detected;
trade proposal accept/reject + swap. All deterministic, seeded, fail-closed
rejections asserted.

## Order

Sequential subagent tasks over shared `engine.gd` (do NOT run parallel — file
conflicts): B1 data+monopoly, B2 houses, B3 mortgage, B4 bankruptcy, B5 trades,
B6 integration+docs+merge+push.
