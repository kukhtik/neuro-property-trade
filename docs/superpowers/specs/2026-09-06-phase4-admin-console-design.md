# Phase 4 — Admin Console & Test Ladder (design)

Date: 2026-09-06. Status: design → implement. Branch: `phase4/admin-console`.
Authoritative spec: `docs/specs/game-concept-spec.md` §4 (admin console) and
the test ladder in `docs/plan.md` (Randy → Tony → Neuro). Engine already at
109 headless tests green; Phase 3 stubbed `seat_manager.push_admin_intent`.

## Scope (agreed with user)

This pass delivers the **deep engine + test-ladder slice** of Phase 4. The
visual layer (board art, camera/spectacle, SFX, stream overlay) is explicitly
**deferred** to a later pass that runs where a real stream can validate it.

In scope:
- Admin console (§4) as a **pure headless-testable `admin_controller`** + a
  **thin Godot Control panel** toggled by F12 in `main.tscn`.
- A full **`admin_override` engine entry point**: validated, fail-closed,
  executed through the authoritative engine, written to the same event log.
- **Snapshot export/import** (full engine state round-trip) + diagnostics.
- **Tony scripted scenarios** (test-ladder rung 3) on top of Randy (rung 2).
- **WebGL export build + smoke** (rung: buildable artifact).

Out of scope this pass: board art/SFX/camera/overlay, voice-chat spike,
`REMOTE` network client, real `evil` over a second SDK connection.

## Goals

1. Give Vedal, host-side and local-only, a hidden F12 panel that can unblock a
   stuck match, edit live state for scenarios/debug, and dump/restore state —
   **every edit routed through the engine and recorded in the event log
   (spec §4 hard rule #1)**, so determinism/replay survive intervention.
2. Prove the full test ladder end-to-end: headless unit → Randy soak → **Tony
   scripted** → (WebGL build artifact).
3. Extendable: the pure `admin_controller` is headless-testable and GUI-free,
   so a future full panel or remote (token-guarded) panel is a thin addition.

## Why engine-authoritative (the core invariant)

Admins must NEVER reach into engine internals directly. Each override is an
intent that goes through a dedicated `admin_override` branch in
`engine.submit_intent`, which reuses the existing `_charge` / `_transfer` /
`_cred(credit)` / `_send_to_jail` / player-mutation primitives and appends an
`admin_override` event to `log`. This keeps: (a) one input path, (b) fail-closed
validation (reject nonsense before mutating), (c) append-only replay, (d) the
same determinism semantics as normal play.

## Architecture (pure controller + thin Node shell + thin panel)

```
game/
  admin/
    admin_controller.gd   RefCounted (pure, headless-testable) — the policy
                          layer: builds admin_override intents from a simple
                          {op, params} command set against engine state,
                          and diagnostics/snapshot. ALL mutations via
                          engine.admin_override(...).
    admin_panel.gd        Control (thin) — F12-hidable panel; buttons/fields
                          call the controller by `pid`/op; displays live state
                          table + filtered log. No engine knowledge.
  core/engine.gd          (+ admin_override(op, params) entry + _admin_* executors)
  core/snapshot.gd        RefCounted (pure) — engine.to_snapshot()/from_snapshot()
                          round-trip serializer (players, phase, pending,
                          houses, mortgaged, decks, RNG state, event log, settings).
  tools/tony.tscn /.gd    scripted-scenario runner (test-ladder rung 3)
  main.tscn / main.gd     (+ host the seat_manager + admin_panel; F12 toggle)
  tests/
    admin_test.gd         controller + override + diagnostics tests
    snapshot_test.gd      full round-trip tests
    tony_test.gd          each scripted scenario asserts its invariant
```

`engine` gains a **snapshot contract** (it already owns board/rng/decks/log);
`snapshot.gd` is a thin pure helper that walks the engine's public members and
returns plain-JSON-able Dictionaries (no Godot nodes), so it can be exported to
a file and imported back. `from_snapshot` rebuilds a fresh engine from that
data (deterministic: re-seeds RNG + restores decks/phase/pending exactly).

## Admin override operations (validated, fail-closed)

`engine.admin_override(op: String, params: Dictionary) -> Dictionary` returns
`{ok, reason, events, ...}` (mirrors `submit_intent`). It is NOT gated by the
turn-player guard — an admin is host-local and may act any time — but every op
range-checks its params and rejects invalid ones *before* mutating.

**A — Unblocking (§4.A):**
- `force_roll` — submit a roll for the current holder (bypasses driver; sets
  `_forced_roll`), so a stuck LOCAL/ADMIN turn advances.
- `force_pass` — run `minimal_action.pick` for the current decision holder
  (purchase/auction/trade/jail) and submit it.
- `reset_seat_away` — clear a seat's `away` flag (back to awaiting turn).
- `rollback_decision` — pop the last `_pending` decision back to the prior
  decision point (limited to the immediately-previous pending context that is
  still reconstructible; conservative, documented).

**B — State editing (§4.B):**
- `set_balance` — set a player's money (≥0, <= some sane cap).
- `teleport` — move a token to a tile index (0..39).
- `force_dice` — set `{sum, d1, d2, doubles}` for the next roll.
- `grant_property` / `revoke_property` — give/take a tile by index (updates
  `player.owned_tiles`, clears houses/mortgage accordingly).
- `set_houses` — set house count 0..5 on a tile (even-build checked).
- `set_mortgage` — mortgage/unmortgage a tile.
- `set_go_jail` — put a player in jail (`_send_to_jail`).

**(§4.B "tweak tile cost/rent", insert/remove deck card, reorder players,
redo-turn) were deferred at Phase 4 — **all built 2026-09-06** as
`engine.admin_override` ops: `tweak_tile`, `deck_insert`, `deck_remove`,
`reorder_players`, `redo_turn`. See `docs/plan.md` "Live admin ops — DONE".

Every applied override appends `log.append("admin_override", {op, params})`.

## Diagnostics (§4.C)

- `dump_state` — a flattened Dictionary: per-player {money, position, jail,
  bankrupt, owned_tiles, houses per group}, pending decision, phase,
  turn_player — rendered by the panel as a table.
- `list_events(filter)` — `log.entries_of_type` / filtered view; panel shows a
  scrollable log.

## Snapshot (§4.C + replay)

`engine.to_snapshot() -> Dictionary`:
`{ settings, players:[{name,money,position,in_jail,jail_turns,bankrupt,
   tiles,get_out_of_jail_cards}], phase, turn_player, consecutive_doubles,
   last_roll, _pending, _pending_trade, houses:{tile:count}, mortgaged:[...],
   decks:{community:[...], chance:[...]} (remaining order), rng:{seed,state},
   log:[...] }`

`engine.from_snapshot(d) -> Engine` builds a fresh engine and restores every
member exactly. Round-trip property: `from_snapshot(engine.to_snapshot())`
produces an engine whose `to_snapshot()` equals the input — headless-tested
over several live mid-game states. Deck/RNG/log restoration makes replay-by-seed
survive a restore.

## F12 admin panel (thin)

`main.tscn` becomes the real entry: it sets up a `GameSettings` + seats, hosts
the `seat_manager`, and instantiates `admin_panel` (a `PanelContainer` with an
`OptionButton` of ops + param `LineEdit`s + an Apply button + a live
`dump_state` `RichTextLabel` + `list_events` log view). F12 toggles its
visibility. Panel calls `admin_controller` per pid. Because the controller is
pure, the panel is deliberately dumb (no logic worth unit-testing).

## Tony scripted scenarios (test-ladder rung 3)

`tools/tony.tscn` + `tony_test.gd` run deterministic scripted games using the
existing test hooks (`_force_dice`, `_teleport`, `_force_draw_card`) and assert
a named ending invariant, one scenario per test case:
1. `auction_resolve` — two players refuse a purchase → auction → affordable bid
   wins → tile + rent transfer; assert owner + cash.
2. `bankruptcy_transfer` — a player hits a rent they can't pay → assets transfer
   to creditor, player removed, `END_GAME`/winner detected.
3. `trade_chain` — three-way propose/respond chain settles cash+tiles correctly
   and the pending trade clears.
4. `admin_unblock` — a LOCAL seat times out; admin `force_roll` advances; state
   log records the `admin_override` event.
These run headless alongside Randy (soak) in the ladder: `headless units →
Randy soak → Tony scenarios → WebGL build`.

## WebGL build (rung 4 artifact)

Install Godot 4.7.2 export templates, add `export_presets.cfg` with a
`web`/HTML5 preset (and a `linux`/native fallback), and verify a headless
`--export-debug "web"` produces an index.html + wasm/js without errors. The
smoke is: the export succeeds (buildable artifact). Actual in-browser play
validation is deferred with the visual layer.

## Testing strategy

- `admin_test.gd` (headless, loaded by path): controller builds correct
  intents; each `admin_override` op applied to a known state produces the
  expected result + an `admin_override` log entry; invalid params fail-closed
  (no mutation). `dump_state` shape. `minimal_action.force_pass` path.
- `snapshot_test.gd`: round-trip equality over SETUP, mid-turn (pending
  purchase), mid-auction, mid-trade, post-bankruptcy, jail states.
- `tony_test.gd`: each scenario above asserts its invariant.
- Existing 109 tests stay green; `run.gd` registers the three new modules.

## Deferred / future (recorded)

- Tweak tile cost/rent live, deck-card insert/remove, player reorder,
  redo-turn-with-seed (needs deeper board/deck mutation + snapshot coupling).
- Full visual layer: board scene/art, camera/spectacle auto-focus, SFX,
  stream overlay, event-overlay on-stream.
- Remote token-guarded admin panel (spec §4 "later possible") — **built
  2026-09-06** as `game/admin/admin_gate.gd` (pure auth layer over
  `admin_controller`; `GameSettings.admin_token`; see `docs/plan.md`).
- Second SDK connection for real `evil`.

## Files touched (map)

- new: `game/admin/admin_controller.gd`, `game/admin/admin_panel.gd`,
  `game/core/snapshot.gd`, `game/tools/tony.tscn`, `game/tools/tony.gd`,
  `game/tests/admin_test.gd`, `game/tests/snapshot_test.gd`,
  `game/tests/tony_test.gd`, `export_presets.cfg`.
- modify: `game/core/engine.gd` (`admin_override` + `_admin_*` +
  `to_snapshot`/`from_snapshot`), `game/core/game_settings.gd` (seats already
  present), `game/main.gd`/`main.tscn` (host manager + panel + F12),
  `game/tests/run.gd` (register new modules).
