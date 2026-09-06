# Development Plan

Feasibility verdict (Sep 2026): standalone property-trading game with Neuro SDK.
Reasoning: commercial Monopoly targets blocked (NEW MONOPOLY 2024: Denuvo+IL2CPP,
36% reviews, trade-freeze bug; Monopoly Plus delisted; TTS stance of Vedal unknown),
while Vedal's own AI now handles routine integration mods — the community lane is
a full game (his words: creative/intellectual work stays with people).

## Model routing (this profile)

Game-concept decisions (seat model, full config schema, Vedal admin console)
are in `docs/specs/game-concept-spec.md` — authoritative before seat/lobby work.

| Role | Model | Note |
|---|---|---|
| DEV (heavy code / ARCH / REVIEW) | deepseek-v4-flash | smartest of the equal-cost pair; default of this profile |
| DEV (parallel) | minimax-m2.7 | same usage/cost tier |
| Executor on a crisply-specified goal (QA/DOCS/aggregation) | gemma4 | cheapest; needs fully-specified goals |

Rule of thumb: CREATE/design/undefined or investigate a discrepancy →
deepseek-v4-flash; bulk GDScript on a fixed interface → minimax-m2.7;
execute-a-listed-schema / tests/docs/aggregation → gemma4.
`delegation.reasoning_effort: high` is set for creative review.

## Phase 0 — Skeleton (target: 2–3 sessions)

- [x] Godot 4.7.2 skeleton in `game/` (headless-testable) — done, 2026-09-06
- [x] Core state model: 40 tiles (board.json + Board), Player, deterministic
      RNG (Rng), full event log (EventLog) — done
- [x] Unit tests headless (`godot --headless --path game --script res://tests/run.gd`)
      — 23 tests green
- [ ] Phase enum (turn-loop phases) — NOT yet done; first task of Phase 1
- [x] ASCII renderer (`ui/ascii_board.gd`) + demo (`tools/ascii_demo.gd`)

Status (handing off to a new session): Phase 0 core is committed. The clean
next task is to design the phase enum / turn-loop model before dispatching
parallel Phase 1 leaf agents — lock the phase machine first so leaves don't
diverge.

## Phase 1 — Rules engine (target: 1–2 weeks)

- [x] Turn loop: roll → move → resolve tile (buy/auction/rent/jail) — core
      in Tranche A: roll/move, GO bonus, doubles (extra turn),
      triple-doubles→jail, tax, free_parking (OFF), go_to_jail, jail decision
      (rule "both"), property purchase/pass→auction, railroad + utility rent,
      both card decks (original names + 8 effect tokens).
- [x] Doubles, jail 3-turns-or-pay, GO landing bonus
- [x] Houses/hotels (even-build), mortgage/unmortgage, bankruptcy transfer
      — Tranche B: houses/hotels + even-build rent table, mortgage (50 loan /
      110 repay) with rent-block + monopoly-break, bankruptcy
      transfer-to-creditor with player removal + END_GAME winner detection,
      player trades (propose/respond, tile+cash swap).
- [x] Auctions (all-pass fallback), rent with railroad/utility multiplier,
      monopoly rent ×2 on full set
- [x] Card decks (original names, classic effects), Free Parking house-rule OFF
- [x] Property set definitions in `game/data/board.json` (color groups;
      monopoly doubling + house-rent tables + house_cost per set)

**Phase 1 COMPLETE — 2026-09-06.** All rules engine features done. Design +
plans in `docs/superpowers/{specs,plans}/2026-09-06-phase1-*.md`. 81 headless
tests green (`godot --headless --path game --script res://tests/run.gd`).
Engine: authoritative state machine + fail-closed intent API
(`submit_intent`) covering roll/move/GO/doubles/jail, purchase/auction,
property/railroad/utility rent + monopoly doubling, houses/hotels (even-build),
mortgage/unmortgage, bankruptcy+winner, trades, and both card decks. Phase 2
(Neuro SDK adapter → `submit_intent`) is next, over this stable engine API.

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
---

## Setup log (2026-09-06)

- Profile `monopoly` created (default: deepseek-v4-flash; delegation per-task).
- 13 skills installed: superpowers stack (6), godot-gdscript + mastery +
  best-practices, tdd, WebSocket, board-game-master, hermes-agent.
- Profile AGENTS.md holds model routing table and domain invariants.
- Local clone moved to `~/projects/neuro-property-trade` (persistent), SSH remote.
