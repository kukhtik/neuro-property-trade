# Development Plan

Feasibility verdict (Sep 2026): standalone property-trading game with Neuro SDK.
Reasoning: commercial Monopoly targets blocked (NEW MONOPOLY 2024: Denuvo+IL2CPP,
36% reviews, trade-freeze bug; Monopoly Plus delisted; TTS stance of Vedal unknown),
while Vedal's own AI now handles routine integration mods — the community lane is
a full game (his words: creative/intellectual work stays with people).

## Model routing (this profile)

| Role | Model | Note |
|---|---|---|
| DEV (heavy code) | deepseek-v4-flash | smartest of the equal-cost pair |
| DEV (parallel) | minimax-m2.7 | same usage/cost tier |
| QA/DOCS/misc | gemma4 | cheapest |

Rule of thumb: ARCH/REVIEW → deepseek-v4-flash; bulk GDScript tasks → minimax-m2.7;
tests/docs/aggregation → gemma4.

## Phase 0 — Skeleton (target: 2–3 sessions)

- [ ] Godot 4 project skeleton in `game/` (headless-testable)
- [ ] Core state model: 40 tiles, 2–4 players, money, position, phase enum
- [ ] Deterministic RNG (seeded), full event log
- [ ] Unit tests headless (`godot --headless --script tests/run.gd`)

## Phase 1 — Rules engine (target: 1–2 weeks)

- [ ] Turn loop: roll → move → resolve tile (buy/auction/rent/card/jail)
- [ ] Doubles, jail 3-turns-or-pay, GO landing bonus
- [ ] Houses/hotels (even-build), mortgage/unmortgage, bankruptcy transfer
- [ ] Auctions (all-pass fallback), rent with monopoly doubling
- [ ] Card decks (original names, classic effects), Free Parking house-rule OFF
- [ ] Property set definitions in `game/data/board.json` (renamable theme)

## Phase 2 — Neuro adapter

- [ ] Godot Neuro SDK wired: startup, context, action registry (stable set)
- [ ] Actions: roll_dice, buy_property, pass_on_purchase, bid_auction,
      build_house, sell_house, mortgage_property, unmortgage_property,
      propose_trade, respond_trade, use_jail_card, pay_jail_fine, end_turn
- [ ] Per-seat projection (isolate per-seat auction bids until resolution)
- [ ] actions/force per decision point, priority=low, ephemeral_context for
      bulky board dumps; markdown state renderer
- [ ] Validator: reject malformed, list legal options in failure message
- [ ] Fail-closed: result-before-execute, no contradictory second result,
      reconnect → resync → fresh force

## Phase 3 — Multi-seat + humans

- [ ] Seat manager: human turns wait for input, AI turns force
- [ ] Second AI seat (evil) — separate SDK session/characterId
- [ ] Trade negotiation UX for humans; auto-resolve for AI-vs-AI
- [ ] Spectator-safe state (no hidden info leak in context messages)

## Phase 4 — Stream polish

- [ ] Board art (original theme), SFX, camera, replay of last event
- [ ] Voice-chat side-channel spike (optional, per API/VOICE_CHAT.md)
- [ ] WebGL build + Web Game Runner smoke test
- [ ] Randy → Tony → real Neuro test ladder

## Test ladder (per SDK best practices)

1. Headless engine unit tests (deterministic seeds, property-based invariants)
2. Randy random-action soak (never crashes, always valid results)
3. Tony scripted scenarios (auction, bankruptcy, trade chains)
4. Real Neuro dry-run (private session) before stream

## Risks

- Hasbro trade dress → mitigated in `docs/licensing.md`, enforced by review.
- Neuro action spam mid-animation → force only at decision points, engine queue.
- WebGL export quirks with the SDK → POC in Phase 2, fallback native build.