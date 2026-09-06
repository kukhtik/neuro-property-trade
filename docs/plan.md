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

- [x] Godot Neuro SDK wired: startup, context, action registry (stable set)
- [x] Actions: roll_dice, buy_property, pass_on_purchase, bid_auction,
      build_house, sell_house, mortgage_property, unmortgage_property,
      propose_trade, respond_trade, use_jail_card, pay_jail_fine
      (end_turn intentionally omitted — engine auto-ends turns; see design doc)
- [x] Per-seat projection (isolate per-seat auction bids until resolution)
- [x] actions/force per decision point, priority=low, ephemeral_context for
      bulky board dumps; markdown state renderer
- [x] Validator: reject malformed, list legal options in failure message
- [x] Fail-closed: result-before-execute, no contradictory second result,
      reconnect → resync → fresh force
- [x] Randy soak of the wired adapter (tools/soak.tscn) — PASSED: 12 turns,
      no stall. Auctions OFF in soak (Randy can't bid affordably — retries
      huge amounts forever; auction path covered by Phase 1 headless tests).

## Phase 3 — Multi-seat + humans

- [x] Seat manager: human turns wait for input, AI turns force
      (`seats/seat_manager.gd` + `seat_config.gd`; pure testable helper
      `find_decision_holder`)
- [x] Second AI seat (internal naive `ai_driver`; `seat_config.resolve_driver`
      maps a 2nd `sdk:*` seat to AI until a second SDK connection is supported)
- [x] Trade negotiation UX for humans: engine propose/respond exists;
      auto-resolve for AI-vs-AI via `TradeEvaluator` (accept if received
      value >= given value)
- [x] Spectator-safe state (no hidden info leak in context messages) —
      `projection.for_spectator` + `render_spectator` (no `private` block, no
      get-out-of-jail cards)

**Phase 3 COMPLETE — 2026-09-06.** Seat/driver layer + timeout auto-pass +
spectator-safe projection + a second AI seat. 109 headless tests green
(`game/tests/seats_test.gd` added). Runtime proof: `tools/seats_soak.tscn`
drives `[SDK(Neuro↔Randy), AI, AI, LOCAL]` on one engine → 12 turns, no stall
(`NEURO_SDK_WS_URL=ws://localhost:8000 godot --headless --path game
res://tools/seats_soak.tscn`). **SDK-singleton constraint:** the vendored SDK
is one process-wide websocket/action-handler singleton, so Neuro + evil cannot
both be SDK seats this phase — the 2nd SDK seat falls back to the internal AI
driver via `seat_config.resolve_driver` (single place a future multi-connection
SDK changes). Auto-pass (spec §3) runs in `seat_manager` for LOCAL/ADMIN/CHAT/
AI; SDK seats self-drive their own force/result cycle (a manager-side timeout
raced it — a future SDK-side one-retry-then-pass belongs in the adapter, not
the manager). Admin console is Phase 4, but `seat_manager.push_admin_intent`
(stub) routes admin overrides through the engine to keep the
authoritative-engine + event-log invariant. Design+plan:
`docs/superpowers/{specs,plans}/2026-09-06-phase3-seats-lobby*`.

## Phase 4 — Stream polish

- [x] Admin console (spec §4): pure `admin_controller` + F12 `admin_panel`,
      host-local, every edit routes through the authoritative `admin_override`
      and writes to the same event log. Ops: unblocking (force_roll,
      force_pass, reset_seat_away, rollback_decision) + state-edit
      (set_balance, teleport, force_dice, grant/revoke property, set_houses,
      set_mortgage, set_go_jail). Diagnostics: dump_state, list_events.
- [x] Engine snapshot export/import: `engine.to_snapshot()/from_snapshot()`
      full round-trip (players, phase, pending, houses, mortgaged, decks, RNG
      seed, event log) + thin `core/snapshot.gd` JSON file wrapper.
- [x] Test ladder rung 3 — Tony scripted scenarios (auction_resolve,
      bankruptcy_transfer, trade_chain, admin_unblock) as `tests/tony_test.gd`
      + `tools/tony.tscn` runner (exit 0, 4/4).
- [x] Test ladder rung 4 — WebGL export build (rung 4 artifact):
      `game/export_presets.cfg` + installed export templates; headless
      `--export-debug "Web"` → `game/build/web/index.html|.wasm|.js` succeeds.
- [x] Board art (original theme), SFX, camera, replay of last event — Phase 5
      visual/stream layer (below)
- [ ] Voice-chat side-channel spike (optional, per API/VOICE_CHAT.md) — deferred
- [ ] In-browser WebGL play smoke — deferred with the visual layer

**Phase 4 (engine + test-ladder slice) DONE — 2026-09-06.** Admin console,
admin_override, snapshot, diagnostics, Tony scenarios, and the WebGL build are
complete on `phase4/admin-console`; 146 headless tests green. Deferred to a
later pass: full visual layer (board art/SFX/camera/overlay), live tile-cost
tweak / deck-card insert-remove / player reorder / redo-turn-with-seed,
token-guarded remote admin panel, second SDK connection (real evil), in-browser
WebGL validation. Design+plan:
`docs/superpowers/{specs,plans}/2026-09-06-phase4-admin-console*`.

## Phase 5 — Visual / stream layer

- [x] Code-built board scene from board.json (no asset files): `visual/tile_layout.gd`
      pure 40-tile ring math, `visual/theme.gd` original non-Hasbro palette,
      `visual/board_view.gd` (repaint from spectator projection, ownership tint,
      houses/hotel labels, active-player highlight), `visual/token_panel.gd`
      (animated tokens w/ outline + name).
- [x] Spectacle camera (spec §4): `visual/spectacle.gd` pans a clip-contents
      frustum over the board to the action tile on move/land/purchase; honors
      `settings.animations` toggle (snap vs tween).
- [x] Event overlay (spec §5 `event_overlay`): `visual/event_overlay.gd` +
      `visual/event_messages.gd` (pure, spectator-safe — never reads private
      keys), feeds from the engine event log; `visual/sfx.gd` procedural tones
      via AudioStreamGenerator (no files) on roll/move/pay/build/card/etc.
- [x] Assembly: `visual/board_scene.gd` + wiring into `main.gd` (sibling of
      admin panel; F12 admin still works). Subscribes to `engine.log.event_appended`.
- [x] Windowed screenshot smoke: `tools/visual_smoke.gd` + `tools/visual_smoke.tscn`;
      drives 12 AI turns, saves PNGs, exit 0. **VALIDATED**: full 40-tile ring,
      correct colors, tokens, active highlight, event overlay visible.
- [ ] In-browser WebGL play smoke — still deferred (build works; not run in-browser)

**Phase 5 COMPLETE — 2026-09-06.** Visual/stream layer on branch
`phase5/visual-layer`; **161 headless tests green** (was 146). Original-themed,
code-built (no asset pipeline, no Hasbro) board watchable + OBS-capturable;
spectacle auto-focus, event overlay, procedural SFX, and a windowed screenshot
smoke all in. Design+plan:
`docs/superpowers/{specs,plans}/2026-09-06-phase5-visual-layer*`.

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

## Handoff — next session (2026-09-06 evening)

**Current state:** `main` at `e77cbd1` (+ Phase 5 merged below), clean working
tree. **161 headless tests green, 0 script errors** (`godot --headless --path
game --script res://tests/run.gd`). Tony runner exits 0. WebGL build succeeds to
`game/build/web/` (`--export-debug "Web"`). Phases 0–5 committed on `main`.

**Phase 5 delivered — visual/stream layer (branch `phase5/visual-layer`):**
code-built (no asset files, no Hasbro) board from board.json — `tile_layout.gd`
(pure 40-tile ring math, headless-tested), `theme.gd` (original palette),
`board_view.gd` (repaint from `for_spectator`, ownership tint, houses/HOTEL
labels, active-player highlight), `token_panel.gd` (animated tokens w/ outline
+ name); `spectacle.gd` auto-focus camera (honors `settings.animations`);
`event_overlay.gd` + `event_messages.gd` (spectator-safe stream overlay fed by
the event log) + `sfx.gd` (procedural AudioStreamGenerator tones, no files);
assembled in `board_scene.gd` and wired into `main.gd` (F12 admin still works).
Windowed screenshot smoke `tools/visual_smoke.gd/.tscn` drives 12 AI turns and
saves PNGs — **validated by eye**: full ring, correct colors, tokens, active
highlight, overlay. Design+plan:
`docs/superpowers/{specs,plans}/2026-09-06-phase5-visual-layer*`.

**Remaining big work / next up:**
- In-browser WebGL smoke — **PARTIALLY validated (2026-09-06):** served the
  existing `game/build/web` over HTTP (`python3 -m http.server`) and drove real
  Playwright Chromium (full build, `--enable-unsafe-swiftshader`) against
  `localhost:8801`. Console proves the game boots in-browser: WebGL2
  (Compatibility) context created, `Neuro Property Trade — ready` logs, NO
  pageerror/no render errors (the `NEURO_SDK_WS_URL` error is expected —
  default seats are LOCAL+AI, no SDK). Canvas present at 1152×648. Caveat: the
  actual rendered frame does NOT composite into any `page.screenshot` / X11-grab
  capture under single-threaded SwiftShader in this WSL environment — all
  captures return solid `77,77,77` (Godot's default clear color). **This is a
  proven environment limitation, NOT a build bug:** a control test with a
  trivial red WebGL2 triangle also fails to composite (white box + broken-image
  icon) in the same headful chromium on `DISPLAY=:0`. **So: boot/runtime is
  validated; the rendered-board pixels still need a human eye on a headed/real
  browser (a stream host's Chrome).** Do NOT treat "black/solid screenshots" as
  a build bug — check console for the `ready` line first.
- Optional: voice-chat side-channel spike (API/VOICE_CHAT.md).

**Known follow-ups queued (small):**
- Live tile-cost/rent tweak, deck-card insert/remove, player reorder,
  redo-turn-with-seed admin ops (need deeper board/deck mutation + snapshot).
- Token-guarded remote admin panel (spec §4 "later possible").
- Real `evil` over a second SDK connection (needs SDK re-vendor; the engine and
  `seat_config.resolve_driver` are already single-swap-point ready).

**Model routing reminder:** ARCH/design/review → deepseek-v4-flash; bulk
GDScript on fixed interface → minimax-m2.7; crisply-specified leaf execution
(tests/docs/aggregation) → gemma4. `gh` CLI segfaults — use git over SSH or the
GitHub API. SDK addon parse errors in `--script` mode are expected/harmless.
