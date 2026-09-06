# Phase 3 — Seats & Lobby (design)

Date: 2026-09-06. Status: design → implement. Branch: `phase3/seats-lobby`.
Authoritative spec: `docs/specs/game-concept-spec.md` (seat-driver model,
timeout/auto-pass, admin console, spectator safety).

## Goal

Turn the single-seat, single-driver harness into a real **multi-seat game with
a driver layer**: human seats wait for input, AI seats self-drive, each seat is
routed through the same `engine.submit_intent`. Implement per Block 1 of the
spec (seat assignments), timeout/auto-pass (spec §3), a spectator-safe public
projection, and a second AI seat.

## Key constraint discovered (decides the evil-seat approach)

The vendored Godot SDK wires `Websocket` (the connection + `NeuroActionHandler`)
as **one process-wide autoload singleton** (`project.godot`,
`addons/neuro-sdk/plugin.gd`). It holds a single websocket, a single
`characterId`, and a single action registry. Therefore **two simultaneous SDK
sessions (Neuro + evil) cannot run in the same host process** without deep
re-vendoring of the addon (a second connection + handler stack + message
routing). That is out of scope for Phase 3.

Consequence (agreed with user, recommended default): the second AI seat uses an
**internal naive driver** this phase — it self-drives via the same
`engine.legal_actions(pid)` + `submit_intent` path (the same pattern the Randy
soak already proves). `seat_config` records the desired driver as `sdk:evil`,
but the seat *resolver* maps an unpaired SDK seat to the internal AI driver at
runtime. When a real two-connection SDK is supported, the swap is a one-line
resolver change — **no engine change required**, because the engine is already
seat-agnostic.

## Architecture (pure core + thin Node shell, mirroring Phase 2)

```
game/
  seats/
    seat.gd                 RefCounted — one seat's config (pure, testable)
    seat_config.gd          RefCounted — build seats from GameSettings + driver resolver
    minimal_action.gd       RefCounted — pick the timeout/auto-pass action (pure)
    trade_evaluator.gd      RefCounted — AI accept/decline heuristic for trades (pure)
    seat_manager.gd         Node       — poll loop, route decision point → driver, timeout
    drivers/
      local_driver.gd       Node — human seat: waits; intents pushed via submit_intent
      ai_driver.gd          Node — auto seat: submits first legal action each point
      sdk_driver.gd         Node — wraps the existing sdk_adapter for one SDK seat
      chat_driver.gd        Node — stub aggregator (majority of queued local intents)
  sdk/projection.gd         (+ for_spectator) — public view with NO private info
  sdk/markdown_renderer.gd  (+ render_spectator) — spectator markdown
  core/game_settings.gd     (+ Block 1 seat/assignment fields)
  core/engine.gd            (+ setup_ex(settings, seats) alternate constructor + admin_override stub)
  tools/seats_soak.tscn/.gd — mixed multi-seat runtime proof (SDK + AI + LOCAL)
```

Pure pieces (`seat`, `seat_config`, `minimal_action`, `trade_evaluator`,
`projection.for_spectator`) are loaded by path in headless tests and never touch
the SDK. Node pieces (`seat_manager`, drivers) are thin and exercised at runtime
by `seats_soak`.

## Seat model

`seat.gd` fields: `pid` (int), `name` (String), `input_driver` (String: one of
`LOCAL` / `CHAT` / `SDK` / `AI` / `ADMIN`), `driver_label` (String — the raw
assignment, e.g. `sdk:neuro` or `LOCAL`, kept for display + future routing),
`color` (Color), `token_id` (String), `away` (bool), `decision_waiting` (float —
elapsed seconds at the current decision point, for timeout).

`seat_config.from_settings(settings)` builds an Array[Seat] from Block 1:
`seat_count`, `seat_assignments`, per-seat `name`/`token_color`/`token_id`,
`starting_order`. Defaults when `seat_assignments` is empty: first seat `LOCAL`,
one `AI` (the auto evil), remaining `AI` fillers — so a session starts
headless-playable with zero config. `starting_order = "random"|"manual"` is
resolved here (random uses `settings.rng_seed`); `"manual"` keeps insertion order.

Driver resolution (`seat_config.resolve_driver`): maps the raw assignment to an
enabled driver. `sdk:neuro` and `sdk:evil` both resolve to `SDK` for the FIRST
SDK seat, and to `AI` for any additional SDK seat (the single-connection
constraint — see above). `LOCAL`/`CHAT`/`AI`/`ADMIN` map 1:1. This is the single
place future multi-connection support changes.

## Timeout / auto-pass (spec §3), pure picker

`minimal_action.pick(engine, pid) -> {action, params}` chooses the least-cost,
non-stalling intent for a seat that timed out:

- TURN_START, not in jail → `{roll, {}}` (the only advancing action; a stuck
  human just rolls).
- TURN_START, in jail → prefer `roll` if `jail_turns < 3`; else `pay` if the
  player can afford `jail_fine`; else `use_card` if they hold cards; else
  `roll` as a last resort (keeps them in jail; `legal` from the engine decides
  availability).
- PURCHASE_WAIT → `{pass, {}}`.
- AUCTION (this pid is bidder) → `{pass, {}}`.
- trade recipient (`legal` contains `respond_trade`) → `{respond_trade,
  {accept: false}}`.
- END_GAME / no legal action → `{}` (do nothing).

The seat is flagged `away = true`; the action is submitted through
`seat_manager` exactly once. `timeout_action = "mark-away"` (secondary option)
is honored by the manager: it marks away and does **not** submit (left for the
admin to unblock); the default `"auto-pass"` submits.

## Spectator-safe projection (no hidden-info leak)

`projection.for_spectator(engine)` returns the full public view — board,
players (money/position/jail/bankrupt/tiles), phase, turn_player, pending —
**with no `private` section** (a spectator/twitch overlay must never see any
seat's get-out-of-jail cards or hidden state). `markdown_renderer.render_spectator`
emits the same `##`-headed markdown without the "Your private info" block.
Headless tests assert the spectator output contains no jail-card field.

## Seat manager (Node orchestrator)

`seat_manager._process(delta)` polls at `POLL_INTERVAL = 0.4`:

1. If `engine.phase == END_GAME` → emit `game_over`.
2. Compute the **decision holder**: the pid with non-empty
   `engine.legal_actions(pid)` (the active turn player, or the auction bidder,
   or the trade recipient). Cache `_last_decision_key =
   phase|turn|holder|pending` so we don't re-drive unchanged points.
3. Route to the holder's driver:
   - `AI`: `ai_driver.act(engine, seat)` → submits the first legal action
     (with the same trade/heuristic handling as the soak `_auto_drive`).
   - `SDK`: `sdk_driver.tick(...)` → the existing adapter's `_force_if_needed`
     (extract it to a public `tick()` so the manager can call it; the adapter
     currently self-polls in `_process`). If the SDK seat times out with no
     result, apply `minimal_action`.
   - `LOCAL`: do nothing — wait. The seat's intents arrive asynchronously via
     `seat_manager.push_intent(pid, action, params)` (a human/UI calls this,
     which calls `engine.submit_intent`). On timer expiry → `minimal_action`.
   - `CHAT`: `chat_driver.act(...)` → resolve queued votes/commands
     (majority of the last `queue_len` non-empty commands; default
     `chat_mode = "majority"`). Stub this phase; `local_driver` fallback if no
     votes.
   - `ADMIN`: never auto-driven; only explicit admin intents, or timeout →
     auto-pass like any non-local seat.
4. **Timeout accounting** is per-seat (`seat.decision_waiting`): reset to 0
   when the decision key changes; increment by delta while this seat holds the
   point; when it exceeds the seat's window (`turn_timer` for turns, or
   `auction_timer` for a bid), call `minimal_action` (or `mark-away`).
5. Emit spectator-safe `state_changed(spectator_proj)` and `events(engine_events)`
   signals so a UI overlay + event log can render.

`push_intent` is the single human/SDK/admin entry — it forwards to
`engine.submit_intent(pid, action, params)` and returns `{ok, reason, legal}`.
This keeps EVERY driver on one path (fail-closed by the engine).

## Second AI seat / evil

Covered by the driver resolver + `ai_driver` (see above). `ai_driver` reuses the
soak's `_auto_drive` logic (first legal action, bid-above-high-or-pass, decline
trades with `trade_evaluator`). This makes an AI-vs-AI (and mixed) game fully
playable headless this phase.

## Admin console (out of Phase 3 core, stub only)

Per spec §4 the admin console is a real Phase-4 concern. Phase 3 provides the
**hook**: `seat_manager.push_admin_intent(action, params)` routes through the
engine (fail-closed, engine-authoritative) and writes to the same event log —
the invariant that "admin edits go through the authoritative engine" is
established even before the F12 panel exists. `engine.submit_intent` already
rejects out-of-turn intents, so the admin override path is a documented
`admin_override` entry point added in Phase 4 (not built here). No admin GUI
this phase.

## Testing

Headless (new `tests/seats_test.gd`, registered in `run.gd`):
- `seat_config_test` — defaults, assignment parsing, driver resolution incl.
  the second-SDK→AI fallback, starting_order random/manual.
- `minimal_action_test` — every phase/timeout branch above.
- `trade_evaluator_test` — accept vs decline heuristic.
- `spectator_projection_test` — `for_spectator` has no `private`, no jail-card
  leak; `render_spectator` omits the private block.

Runtime (mixed multi-seat proof): `seats_soak.tscn` + `seats_soak.gd` wires
`seat_manager` with seats `[SDK(neuro), AI, AI, LOCAL]`; the LOCAL seat is
auto-driven by a fake human thread (pushes intents on timer) while the SDK seat
talks to Randy. The soak passes when it reaches `END_GAME` or the turn cap
without stalling — proving the manager routes all four driver types on one
engine. Run:
`NEURO_SDK_WS_URL=ws://localhost:8000 godot --headless --path game res://tools/seats_soak.tscn`
(needs `godot --headless --import .` once so the SDK class cache exists).

## Deferred / not in Phase 3

- Network/browser human client (`REMOTE`) — later, another driver over the same engine.
- Real `evil` over SDK (second connection) — needs SDK re-vendor.
- Trade negotiation GUI for humans — engine supports propose/respond; the UI
  is Phase 4 (stream polish). AI-vs-AI auto-resolves via `trade_evaluator`.
- Full admin console (F12 panel) — Phase 4; the override entry point is stubbed here.
